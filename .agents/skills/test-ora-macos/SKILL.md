---
name: test-ora-macos
description: Build, test, and screenshot the Ora macOS browser from a Linux or remote agent by dispatching the Agent Test workflow to a disposable macOS 26 runner. Use when asked to run, test, verify, reproduce, or screenshot Ora, or before reporting any Ora code change as working.
---

# Test Ora on a disposable macOS runner

Ora is a SwiftUI, AppKit, and WebKit app. It only builds and runs on macOS. Agents usually work from Linux, so every build, test, and screenshot runs on a fresh macOS VM through `.github/workflows/agent-test.yml` and comes back as a downloaded artifact.

Never build, launch, or drive Ora on a maintainer's personal Mac. The runner VM is the only machine this skill controls, and it is destroyed after each job, so UI tests there are authorized by default.

## Prerequisites

Check these once per session. Stop and report the missing piece instead of working around it.

1. `gh auth status` succeeds, and `git remote get-url origin` points at a repository you can push to.
2. The Tenki Runners GitHub App is installed on that repository. Without it, jobs for `tenki-macos-*` labels sit in the queue forever.
3. `agent-test.yml` exists on the repository's default branch. GitHub only lets you dispatch workflows that exist there. The run itself uses the workflow and scripts from the branch you dispatch.

Each run bills macOS runner minutes. Do not dispatch in a loop without changing code in between.

## Run the loop

1. Commit your change and push the branch. `remote.sh` refuses to dispatch when `origin/<branch>` differs from local `HEAD`.
2. Dispatch and wait:

   ```bash
   scripts/agent-test/remote.sh                 # build, unit tests, UI tests
   scripts/agent-test/remote.sh --stage build   # compile check only
   scripts/agent-test/remote.sh --stage unit    # logic-only changes
   scripts/agent-test/remote.sh --stage ui --only-testing oraUITests/OraSmokeUITests
   ```

   Useful flags: `--runner tenki-macos-15-medium` for macOS 15 with Xcode 16, `--repo OWNER/REPO`, and `--run-id ID` to re-download evidence without a new run. A new dispatch on the same branch cancels the previous run.
3. Read `build/agent-test/runs/<run-id>/summary.md`, then look at every image in `screenshots/`. Xcode 26 exports attachments as `.heic` stills and `.mp4` screen recordings; convert them first (for example `ffmpeg -i in.heic out.png`, or `ffmpeg -ss 5 -i in.mp4 -frames:v 1 out.png` for a frame) and open the PNGs with the image reader. A passing test proves only what it asserts. Look at the screenshots yourself.
4. On failure, read the matching log before changing code (see Evidence). `gh run view <run-id> --log-failed` shows setup failures that happen before the evidence exists.

Run `scripts/agent-test/run.sh` directly only on a disposable macOS machine. It takes the same settings through `ORA_AGENT_*` environment variables, documented at the top of the script.

## What a run does

`run.sh` generates the project with XcodeGen and runs `build-for-testing` without signing, for the schemes the stage needs (`ora` for unit, `ora-ui` for UI, both for `build` and `all`). It ad-hoc signs `Ora.app` with `get-task-allow`, which XCTest needs. Unit tests (`oraTests`) run in a build signed without the sandbox, because XCTest can't connect to an ad-hoc signed sandboxed host. Before UI tests it re-signs with the real sandbox entitlements, minus the two `com.apple.developer.web-browser*` keys that need Ora's provisioning profile. It then serves `scripts/agent-test/fixtures/` on `http://127.0.0.1:8765/`. Last, it runs UI tests (`oraUITests`) and exports their screenshot attachments.

Because of that signing, runner builds cannot test passkeys, default-browser registration, iCloud Keychain, or Sparkle updates. Say so when a change touches them. The VM starts empty, so every run is a first launch with no Spaces, history, or saved state.

## Evidence

Everything lands in `build/agent-test/runs/<run-id>/`, which is gitignored:

| File | Use it for |
| --- | --- |
| `summary.md` | Pass or fail per step, OS and Xcode versions, screenshot list |
| `environment.txt` | Commit, stage, sandbox mode, `sw_vers`, Xcode version |
| `build-ora.log`, `build-ora-ui.log` | Full compiler output |
| `unit-tests.log`, `unit-tests.json`, `unit-summary.json` | Unit test output and per-test results |
| `ui-tests.log`, `ui-tests.json`, `ui-summary.json` | UI test output and per-test results |
| `screenshots/<test>__<name>.heic`, `.mp4` | Attachments and screen recordings from UI tests, including failure screenshots |
| `ui-attachments-export.log` | Why screenshots are missing when the "UI screenshot export" step fails |
| `ora-unified.log` | Ora's `Logger` output (subsystem `com.orabrowser.ora`) |
| `crashes/` | Ora crash reports from the run, if any |
| `entitlements-sandbox-0.txt`, `entitlements-sandbox-1.txt` | Entitlements the app had for unit tests and for UI tests |
| `*.xcresult.zip` | Full result bundles for Xcode on a Mac |

Confirm `environment.txt` shows the commit you pushed before trusting a result.

## Write UI tests

UI tests live in `oraUITests/` and run in the `ora-ui` scheme. `OraSmokeUITests.swift` shows the patterns:

- Launch with `XCUIApplication().launch()` and wait for `app.windows.firstMatch`.
- Load pages with `app.open(url)`. Ora handles `http` URLs the same way as links opened from other apps. Serve pages from `scripts/agent-test/fixtures/` through the `ORA_FIXTURE_BASE_URL` environment variable instead of loading real websites.
- Assert on visible results, such as `app.webViews.staticTexts["..."]` for page text. Add `.accessibilityIdentifier(...)` to SwiftUI views when a test needs a stable handle. None exist yet, so add them where you need them.
- Attach a named screenshot after each meaningful step with `XCTAttachment(screenshot:)` and `lifetime = .keepAlways`. The name becomes part of the file name.
- Test the reverse action and the shared state a change touches too. For example, check that closing a tab removes it from the sidebar and that a Space's data stays separate from another Space's.

For layout changes, capture both appearances. `OraUITestsLaunchTests` already runs once per light and dark configuration.

## Report honestly

- State which stage ran, the run URL, the macOS and Xcode versions, and which screenshots you inspected.
- Keep "compiled", "tests passed", and "looked correct in screenshots" separate. Only claim what the evidence shows.
- Name what the runner cannot cover: the signing gaps above, real extension stores, and anything that only a person clicking through the app would notice.

## Troubleshooting

- **Run never starts**: `gh run view <id>` shows it queued. Check the Tenki app installation and the `--runner` label.
- **`remote.sh` says the workflow is not found**: `agent-test.yml` is missing from the default branch.
- **Build fails on signing or provisioning**: the build must pass `CODE_SIGNING_ALLOWED=NO`. Check the `xcodebuild` line in `build-ora.log`.
- **Ora exits at launch with a code signature error**: read `entitlements-sandbox-1.txt`. A restricted `com.apple.developer.*` key may have been added to `project.yml` and needs to be stripped in `run.sh`. Dispatching with `gh workflow run agent-test.yml --ref <branch> -f sandbox=0` runs UI tests without the sandbox to isolate sandbox problems.
- **UI tests time out before the first action**: UI automation was not enabled. Look for `automationmodetool` in the job log.
- **Screenshots are blank or missing**: if the "UI screenshot export" step failed, read `ui-attachments-export.log`. Otherwise check `ui-tests.json` to see whether the test reached its attachment step, then read `ui-tests.log`.
- **Fixture test is skipped**: `ORA_FIXTURE_BASE_URL` was not passed through. Check `fixture-server.log` and the `TEST_RUNNER_` export in `run.sh`.
- **UI tests fail and screenshots show a lock screen or screen saver**: Tenki's macOS 15 and 26 images auto-log in `runner` with `autoLoginUserScreenLocked = 1`, so the GUI session is locked from boot. Synthetic keystrokes, System Events, and `screencapture` on macOS 26 all fail against it, even with the correct password. There is no in-job workaround yet. Report UI tests as blocked and rely on build and unit evidence.
