#!/bin/bash
# Runs scripts/agent-test/run.sh on a disposable macOS runner through the Agent Test
# workflow, waits for it, and downloads the evidence into build/agent-test/runs/<run-id>/.
#
# Usage:
#   scripts/agent-test/remote.sh [--stage all|build|unit|ui] [--only-testing FILTER]
#                                [--ref BRANCH] [--runner LABEL] [--repo OWNER/REPO]
#   scripts/agent-test/remote.sh --run-id ID     # download evidence from an existing run
#
# The branch must already be pushed. This script never pushes.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

WORKFLOW="agent-test.yml"
ARTIFACT="agent-test-evidence"
STAGE="all"
ONLY_TESTING=""
RUNNER="${ORA_AGENT_RUNNER:-tenki-macos-26-medium}"
REF="$(git rev-parse --abbrev-ref HEAD)"
REPO="${ORA_AGENT_REPO:-}"
RUN_ID=""
WATCH_TIMEOUT="${ORA_AGENT_WATCH_TIMEOUT:-90m}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --stage) STAGE="$2"; shift 2 ;;
        --only-testing) ONLY_TESTING="$2"; shift 2 ;;
        --ref) REF="$2"; shift 2 ;;
        --runner) RUNNER="$2"; shift 2 ;;
        --repo) REPO="$2"; shift 2 ;;
        --run-id) RUN_ID="$2"; shift 2 ;;
        -h | --help) sed -n '2,10p' "$0"; exit 0 ;;
        *) echo "error: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

if [[ -z "$REPO" ]]; then
    # Default to the repository behind the `origin` remote, not gh's upstream guess.
    REPO="$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')"
fi

download() {
    local dest="$ROOT/build/agent-test/runs/$RUN_ID"
    rm -rf "$dest"
    mkdir -p "$dest"
    if ! gh run download "$RUN_ID" -R "$REPO" -n "$ARTIFACT" -D "$dest"; then
        echo "error: run $RUN_ID has no $ARTIFACT artifact. Check the job log:" >&2
        echo "  gh run view $RUN_ID -R $REPO --log-failed" >&2
        return 1
    fi
    echo
    [[ -f "$dest/summary.md" ]] && cat "$dest/summary.md"
    echo
    echo "Evidence: $dest"
}

if [[ -n "$RUN_ID" ]]; then
    download
    exit $?
fi

SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git ls-remote origin "refs/heads/$REF" | cut -f1)"
if [[ "$REMOTE_SHA" != "$SHA" ]]; then
    echo "error: origin/$REF is at '${REMOTE_SHA:-missing}', local HEAD is $SHA. Push the branch first." >&2
    exit 1
fi

list_runs() {
    gh run list -R "$REPO" --workflow "$WORKFLOW" --branch "$REF" --event workflow_dispatch -L 20 \
        --json databaseId,headSha --jq ".[] | select(.headSha == \"$SHA\") | .databaseId"
}

BEFORE="$(list_runs || true)"
echo "Dispatching $WORKFLOW on $REPO@$REF ($STAGE, $RUNNER)"
gh workflow run "$WORKFLOW" -R "$REPO" --ref "$REF" \
    -f stage="$STAGE" -f ui_only_testing="$ONLY_TESTING" -f runner="$RUNNER"

for _ in $(seq 1 30); do
    sleep 4
    RUN_ID="$(list_runs | grep -vxF -e "${BEFORE:-none}" | head -1 || true)"
    [[ -n "$RUN_ID" ]] && break
done
if [[ -z "$RUN_ID" ]]; then
    echo "error: the dispatched run did not appear within two minutes" >&2
    exit 1
fi

echo "Run: https://github.com/$REPO/actions/runs/$RUN_ID"
STATUS=0
timeout "$WATCH_TIMEOUT" gh run watch "$RUN_ID" -R "$REPO" --interval 30 --exit-status >/dev/null || STATUS=$?
if [[ "$STATUS" -eq 124 ]]; then
    echo "error: run $RUN_ID is still going after $WATCH_TIMEOUT. Download later with --run-id $RUN_ID." >&2
    exit 1
fi

download || STATUS=1
exit "$STATUS"
