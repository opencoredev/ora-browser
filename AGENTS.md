# Ora Browser

Ora is a native macOS browser built with SwiftUI, AppKit, and WebKit. It targets people who want a fast, low-friction browser with vertical tabs, Spaces, and built-in privacy protections. It is in active development and not yet ready for daily use. See `README.md` for the overview and `ROADMAP.md` for what is shipped versus planned.

## Ground rules

- `project.yml` is the source of truth for targets, schemes, signing, entitlements, and `Info.plist` keys. XcodeGen generates `Ora.xcodeproj`, which is gitignored. Never edit the generated project. Regenerate with `xcodegen` after changing `project.yml`.
- The deployment target is macOS 15.0. Guard newer APIs with `if #available` or `@available`.
- All web content goes through the engine layer in `ora/Core/BrowserEngine/` (`BrowserEngine`, `BrowserPage`, `BrowserEngineProfile`). Feature code should not create its own `WKWebView` or data stores.
- Each Space owns a separate `WKWebsiteDataStore`, keyed by the Space's UUID in `BrowserEngineProfile`. Private windows use a non-persistent store. Never share cookies, storage, or history across Spaces or leak private browsing into persistent state.
- SwiftData persists Spaces, history, and downloads in `~/Library/Application Support/Ora/OraData.sqlite` (see `ora/Core/Extensions/ModelConfiguration+Shared.swift`). Model changes need a migration path for existing users' data.
- Use the project `Logger` with subsystem `com.orabrowser.ora` instead of `print`.
- Pre-commit hooks run SwiftFormat and SwiftLint (`.swiftformat`, `.swiftlint.yml`). Match the surrounding code style.
- Never commit signing identities, provisioning profiles, `.env` files, or Sparkle keys. Release signing lives in `scripts/build.sh`, `scripts/release.sh`, and `scripts/publish.sh`. Do not run those scripts unless explicitly asked.

## Glossary

- **Space**: a named group of tabs with its own website data. Implemented as `TabContainer` in `ora/Features/Tabs/Models/`.
- **Tab types**: `TabType` is `.fav`, `.pinned`, or `.normal`. Favorite and pinned tabs remember a saved URL across sessions; normal tabs do not.
- **Launcher**: the quick-open palette for URLs, search, and tab switching (`ora/Features/Launcher/`).
- **Engine profile**: `BrowserEngineProfile`, the WebKit data store that backs one Space or private window.

## Testing

Ora only builds and runs on macOS, and agents here usually work from Linux. Do not try to build it locally with Swift on Linux. Never build, run, or control Ora on a maintainer's personal Mac.

Read `.agents/skills/test-ora-macos/SKILL.md` before any task that builds, tests, verifies, reproduces, or screenshots Ora. It dispatches `.github/workflows/agent-test.yml` to a disposable macOS 26 runner and downloads logs and screenshots into `build/agent-test/runs/`. That workflow is manual only and separate from the push and pull request checks in `build-and-test.yml`.

- Unit tests live in `oraTests/` (Swift Testing, `ora` scheme). UI tests live in `oraUITests/` (XCTest, `ora-ui` scheme).
- Add or update tests when behavior changes. Put UI test pages in `scripts/agent-test/fixtures/` rather than depending on live websites.

## Verification standard

- A change is verified only when the runner evidence covers it: a clean build for compile-level changes, passing unit tests for logic, and a UI test with inspected screenshots for anything visible.
- Check the neighbors of what you changed: other readers of the same state (sidebar, launcher, history, settings), the reverse action, empty and error states, private windows, and a second Space.
- Report checks that did not run and why, such as the missing runner signing entitlements, network-dependent behavior, or runner capacity. Never describe static review as runtime proof.

## Working in parallel

One writer per checkout. Parallel agents use separate git worktrees and separate branches. Each branch gets its own agent test runs, because a new dispatch on the same branch cancels the previous run.
