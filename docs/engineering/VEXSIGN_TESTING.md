# VexSign Testing Guide

Phase 1 (test foundation) established how tests are configured, run and gated.
This document is the reference for the exact commands and conventions; the
discovery baseline lives in `VEXSIGN_BASELINE.md`.

## Test target configuration (verified)

- **Target**: `VexSignTests` — hosted unit-test bundle
  (`TEST_HOST = VexSign.app`, `BUNDLE_LOADER` set), bundle id
  `com.vexsign.appTests`.
- **Platform**: iOS, deployment target 16.0; Swift 5.0 language mode.
- **Code signing**: `CODE_SIGN_IDENTITY = ""` (tests build unsigned).
- **Project format**: `objectVersion 77` with *file system synchronized
  groups* — any file added under `VexSignTests/` (Swift or fixture) joins the
  test target automatically; no `project.pbxproj` edits are needed for new
  tests or fixtures.
- **Scheme**: the `VexSignTests` scheme runs the tests. The main `VexSign`
  scheme runs **no** tests. Always test through the workspace:
  `VexSign.xcworkspace` (SPM dependencies resolve at workspace level).

## Exact test command

```sh
xcodebuild test \
  -workspace VexSign.xcworkspace \
  -scheme VexSignTests \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=<simulator-udid>' \
  -derivedDataPath build/DerivedData \
  -resultBundlePath build/TestResults.xcresult \
  -skipPackagePluginValidation -skipMacroValidation \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""
```

Notes:

- Submodules must be checked out recursively first (`Zsign`, `IDeviceKitten`).
- A real iOS Simulator is required (hosted bundle); this does not run on
  macOS destinations.
- `quick_check.py` / `check-pbxproj.py` stay green when adding fixtures: the
  duplicate-name check only covers `.swift` files and the resource check
  parses committed `.json`/`.plist` fixtures.

## CI gate

`.github/workflows/swift-tests.yml` (macos-15) is the Swift test gate:

1. Recursive submodule checkout, latest matching Xcode via
   `tools/select_xcode.sh`, SPM dependency caching, `xcodebuild -resolvePackageDependencies`.
2. Selects the newest available iPhone simulator from `xcrun simctl list`.
3. Runs the exact command above with a result bundle; failure lines are
   mirrored as check-run **annotations** so failures stay readable from the
   REST API even when log/artifact storage is unreachable.
4. Publishes a summary and uploads logs + `.xcresult` as artifacts
   (`if: always()`).

Environment switches:

| Variable | Effect |
| --- | --- |
| `VEXSIGN_INTEGRATION_TESTS=1` | Enables live-network integration tests (e.g. `testRepoParsing`, which fetches every default repo). Default: skipped, so PR runs are deterministic. |

Workflow dispatch inputs allow choosing an Xcode prefix and toggling
integration tests per run.

## Test conventions

- **Network isolation**: the PR suite must be deterministic. Network-dependent
  tests are gated behind `IntegrationGate.skipUnlessEnabled()`
  (`VexSignTests/Fixtures/FixtureSupport.swift`) and paired with offline
  fixture-based equivalents.
- **Fixtures**: committed under `VexSignTests/Fixtures/` and produced by
  `python3 tools/make_test_fixtures.py` (deterministic — regeneration is
  byte-identical). Adversarial archives (path traversal, symlinks, oversize)
  are *not* committed; tests build them at runtime via `MiniZipWriter` /
  `UnsafeArchiveFactory`.
- **Shared state**: tests that touch the library (`Storage`), downloads
  (`DownloadManager.shared`), install queue (`InstallQueue.shared`) or task
  center (`UnifiedTaskCenter.shared`) must clean up after themselves
  (delete imported apps, cancel downloads, `clear()` the queue). Core Data
  access goes through the main actor.
- **Device boundary**: nothing in CI claims real-device installs; the device
  boundary (AppInstaller/IDeviceKit) is never activated from tests.

## Backends

- **Python server**: `cd server && .venv/bin/python -m pytest tests/`
  — baseline 84 passed, 1 skipped (network).
- **Cloud signing**: `cd cloud-signing && npm test` (node:test) — 25 tests
  covering contracts, OTA, security, jobs, API auth and webhook SSRF/retry.
