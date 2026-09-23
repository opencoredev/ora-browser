#!/bin/bash
# Builds Ora, runs unit and UI tests, and collects screenshots and logs.
# Meant for a disposable macOS runner (.github/workflows/agent-test.yml). From Linux,
# use scripts/agent-test/remote.sh instead.
#
# Environment:
#   ORA_AGENT_STAGE            all (default), build, unit, or ui
#   ORA_AGENT_UI_ONLY_TESTING  optional -only-testing filter, e.g. oraUITests/OraSmokeUITests
#   ORA_AGENT_SANDBOX          1 (default) signs with the app sandbox; 0 signs without entitlements
#   ORA_AGENT_FIXTURE_PORT     port for the local fixture server (default 8765)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT" || exit 1

STAGE="${ORA_AGENT_STAGE:-all}"
UI_ONLY_TESTING="${ORA_AGENT_UI_ONLY_TESTING:-}"
SANDBOX="${ORA_AGENT_SANDBOX:-1}"
FIXTURE_PORT="${ORA_AGENT_FIXTURE_PORT:-8765}"
BUNDLE_ID="com.orabrowser.app"
LOG_SUBSYSTEM="com.orabrowser.ora"

OUT="$ROOT/build/agent-test"
DERIVED="$OUT/DerivedData"
EVIDENCE="$OUT/evidence"
PRODUCTS="$DERIVED/Build/Products/Debug"
APP="$PRODUCTS/Ora.app"

case "$STAGE" in
    all | build | unit | ui) ;;
    *)
        echo "error: unknown ORA_AGENT_STAGE '$STAGE' (use all, build, unit, or ui)" >&2
        exit 2
        ;;
esac

if [[ "$(uname)" != "Darwin" ]]; then
    echo "error: run.sh needs macOS. From Linux, use scripts/agent-test/remote.sh." >&2
    exit 2
fi

rm -rf "$EVIDENCE"
mkdir -p "$EVIDENCE"
touch "$EVIDENCE/.started"
START_TIME="$(date '+%Y-%m-%d %H:%M:%S')"
RESULTS=()
FAILED=0
SERVER_PID=""

cleanup() {
    if [[ -n "$SERVER_PID" ]]; then
        kill "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

record() {
    # record <name> <exit-code>
    if [[ "$2" -eq 0 ]]; then
        RESULTS+=("| $1 | passed |")
    else
        RESULTS+=("| $1 | failed (exit $2) |")
        FAILED=1
    fi
}

beautify() {
    if command -v xcbeautify >/dev/null 2>&1; then
        xcbeautify --quieter
    else
        cat
    fi
}

xcode() {
    # xcode <log-name> <xcodebuild args...>
    local name="$1"
    shift
    xcodebuild -project Ora.xcodeproj -destination "platform=macOS" -derivedDataPath "$DERIVED" "$@" 2>&1 |
        tee "$EVIDENCE/$name.log" | beautify
    return "${PIPESTATUS[0]}"
}

write_environment() {
    {
        echo "commit: $(git rev-parse HEAD)"
        echo "branch: $(git rev-parse --abbrev-ref HEAD)"
        echo "stage: $STAGE"
        echo "sandbox: $SANDBOX"
        echo "arch: $(uname -m)"
        sw_vers
        xcodebuild -version
    } >"$EVIDENCE/environment.txt" 2>&1
}

build() {
    echo "==> Generating Xcode project"
    xcodegen generate --quiet 2>&1 | tee "$EVIDENCE/xcodegen.log"
    [[ "${PIPESTATUS[0]}" -eq 0 ]] || return 1

    # The checked-in signing settings need Ora's Developer ID and provisioning profile.
    # Build unsigned here and ad-hoc sign afterwards.
    local unsigned=(CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="")
    # Build only what the stage runs. The build stage compiles both schemes.
    local schemes
    case "$STAGE" in
        unit) schemes="ora" ;;
        ui) schemes="ora-ui" ;;
        *) schemes="ora ora-ui" ;;
    esac
    local scheme
    for scheme in $schemes; do
        echo "==> Building scheme $scheme for testing"
        xcode "build-$scheme" build-for-testing -scheme "$scheme" "${unsigned[@]}" || return 1
    done
    sign
}

sign() {
    echo "==> Ad-hoc signing test products"
    [[ -d "$APP" ]] || {
        echo "error: $APP was not built" >&2
        return 1
    }

    # Sign nested code (Sparkle, test bundles) without entitlements first, then the app itself.
    codesign --force --deep --sign - "$APP" || return 1
    if [[ "$SANDBOX" == "1" ]]; then
        # Keep the real sandbox, but drop the entitlements that require Ora's provisioning profile.
        local entitlements="$OUT/ora-agent.entitlements"
        cp ora/Info/ora.entitlements "$entitlements"
        /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.web-browser" "$entitlements" 2>/dev/null
        /usr/libexec/PlistBuddy -c "Delete :com.apple.developer.web-browser.public-key-credential" "$entitlements" 2>/dev/null
        sed -i '' "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" "$entitlements"
        codesign --force --sign - --entitlements "$entitlements" "$APP" || return 1
    fi
    codesign --display --entitlements - "$APP" >"$EVIDENCE/entitlements.txt" 2>&1

    local runner
    for runner in "$PRODUCTS"/*-Runner.app; do
        [[ -d "$runner" ]] && { codesign --force --deep --sign - "$runner" || return 1; }
    done
    return 0
}

start_fixture_server() {
    echo "==> Serving fixtures on 127.0.0.1:$FIXTURE_PORT"
    python3 -m http.server "$FIXTURE_PORT" --bind 127.0.0.1 --directory "$ROOT/scripts/agent-test/fixtures" \
        >"$EVIDENCE/fixture-server.log" 2>&1 &
    SERVER_PID=$!
    for _ in $(seq 1 20); do
        if curl -fsS "http://127.0.0.1:$FIXTURE_PORT/basic.html" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.5
    done
    echo "error: fixture server did not become ready" >&2
    return 1
}

export_results() {
    # export_results <name>
    local bundle="$EVIDENCE/$1.xcresult"
    [[ -d "$bundle" ]] || return 0
    xcrun xcresulttool get test-results summary --path "$bundle" --compact >"$EVIDENCE/$1-summary.json" 2>/dev/null || true
    xcrun xcresulttool get test-results tests --path "$bundle" --compact >"$EVIDENCE/$1-tests.json" 2>/dev/null || true

    local dest="$EVIDENCE/screenshots"
    local raw="$OUT/attachments-$1"
    rm -rf "$raw"
    mkdir -p "$raw" "$dest"
    # A failed export returns non-zero so the summary cannot pass with missing screenshots.
    xcrun xcresulttool export attachments --path "$bundle" --output-path "$raw" \
        >"$EVIDENCE/$1-attachments-export.log" 2>&1 || return 1

    # Give exported attachments readable names: <test>__<attachment>.<ext>
    python3 - "$raw" "$dest" <<'PY' >>"$EVIDENCE/$1-attachments-export.log" 2>&1
import json, os, re, shutil, sys
raw, dest = sys.argv[1], sys.argv[2]
try:
    manifest = json.load(open(os.path.join(raw, "manifest.json")))
except (OSError, ValueError) as error:
    sys.exit(f"cannot read manifest.json: {error}")
def clean(value):
    return re.sub(r"[^A-Za-z0-9._-]+", "-", value).strip("-") or "attachment"
for test in manifest:
    test_name = clean(test.get("testIdentifier", "test").split("/")[-1].replace("()", ""))
    for index, item in enumerate(test.get("attachments", [])):
        source = os.path.join(raw, item.get("exportedFileName", ""))
        if not os.path.isfile(source):
            continue
        ext = os.path.splitext(source)[1]
        label = clean(os.path.splitext(item.get("suggestedHumanReadableName", str(index)))[0])
        shutil.copy(source, os.path.join(dest, f"{test_name}__{label}{ext}"))
PY
}

run_unit() {
    echo "==> Running unit tests"
    xcode unit-tests test-without-building -scheme ora -resultBundlePath "$EVIDENCE/unit.xcresult"
    local status=$?
    export_results unit || true
    return "$status"
}

run_ui() {
    start_fixture_server || return 1
    echo "==> Running UI tests"
    local filter=()
    [[ -n "$UI_ONLY_TESTING" ]] && filter=("-only-testing:$UI_ONLY_TESTING")
    # xcodebuild strips the TEST_RUNNER_ prefix and passes the variable to the UI test runner.
    export TEST_RUNNER_ORA_FIXTURE_BASE_URL="http://127.0.0.1:$FIXTURE_PORT/"
    # The ${a[@]+...} form keeps macOS's bash 3.2 happy with an empty array under set -u.
    xcode ui-tests test-without-building -scheme ora-ui -resultBundlePath "$EVIDENCE/ui.xcresult" \
        ${filter[@]+"${filter[@]}"}
    local status=$?
    export_results ui
    record "UI screenshot export" $?
    return "$status"
}

collect_diagnostics() {
    log show --start "$START_TIME" --style compact --predicate "subsystem == \"$LOG_SUBSYSTEM\"" \
        >"$EVIDENCE/ora-unified.log" 2>&1 || true
    mkdir -p "$EVIDENCE/crashes"
    find "$HOME/Library/Logs/DiagnosticReports" -maxdepth 1 -name 'Ora*' -newer "$EVIDENCE/.started" \
        -exec cp {} "$EVIDENCE/crashes/" \; 2>/dev/null || true
    rmdir "$EVIDENCE/crashes" 2>/dev/null || true

    # xcresult bundles are large; keep them zipped for artifact upload.
    local bundle
    for bundle in "$EVIDENCE"/*.xcresult; do
        [[ -d "$bundle" ]] || continue
        (cd "$EVIDENCE" && ditto -c -k --keepParent "$(basename "$bundle")" "$(basename "$bundle").zip") &&
            rm -rf "$bundle"
    done
}

write_summary() {
    local shots
    shots="$(find "$EVIDENCE/screenshots" -type f 2>/dev/null | sort | sed "s|$EVIDENCE/||")"
    {
        echo "## Ora agent test"
        echo
        echo "Commit \`$(git rev-parse --short HEAD)\`, stage \`$STAGE\`, $(sw_vers -productName) $(sw_vers -productVersion), $(xcodebuild -version | head -1)"
        echo
        echo "| Step | Result |"
        echo "| --- | --- |"
        printf '%s\n' "${RESULTS[@]}"
        echo
        echo "Screenshots:"
        if [[ -n "$shots" ]]; then
            printf '%s\n' "$shots" | sed 's/^/- /'
        else
            echo "- none"
        fi
    } >"$EVIDENCE/summary.md"
    cat "$EVIDENCE/summary.md"
    [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && cat "$EVIDENCE/summary.md" >>"$GITHUB_STEP_SUMMARY"
    return 0
}

write_environment

build
BUILD_STATUS=$?
record "build and sign" "$BUILD_STATUS"

if [[ "$BUILD_STATUS" -eq 0 ]]; then
    if [[ "$STAGE" == "all" || "$STAGE" == "unit" ]]; then
        run_unit
        record "unit tests (scheme ora)" $?
    fi
    if [[ "$STAGE" == "all" || "$STAGE" == "ui" ]]; then
        run_ui
        record "UI tests (scheme ora-ui)" $?
    fi
fi

collect_diagnostics
write_summary
exit "$FAILED"
