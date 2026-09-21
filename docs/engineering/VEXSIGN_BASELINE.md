# VEXSIGN BASELINE — Phase 0 Discovery Report

Date: 2026-09-21 · Branch: `arena/01a0c515-vexsign` · Base commit: `5602d49` (main)

This is the Phase 0 discovery/baseline document. **No production code was
changed to produce it.** Everything below was verified against the working
tree, not taken from older documentation. Where this report conflicts with
older docs (`docs/STABILIZATION_BASELINE.md` from the previous audit cycle,
README, etc.), this report reflects the current source.

> Prior-art note: main already contains one completed stabilization cycle
> (`5602d49 refactor: code audit, crash elimination, and stability hardening`).
> Several audit targets therefore already exist and must be **improved, not
> re-created**: `UnifiedTaskCenter`, `ArchiveSafetyValidator`, `SourceURLPolicy`,
> `BackupCrypto`, `CertificateSecrets`/`SecureSecretStore`, `EcosystemDatabase`,
> source-health tracking, per-app update rules, offline snapshot cache.

---

## 1. Repository architecture (verified)

```
VexSign/                        iOS app (main target, iOS 16.0, Swift 5 mode)
├── VexSignApp.swift            App + AppDelegate (URL routing, BG tasks, Nuke pipeline)
├── Analytics/                  privacy-preserving local analytics store
├── Backend/
│   ├── AppIntents/             Shortcuts/App Intents (download control, entities)
│   ├── CloudSigning/           CloudSigningClient (talks to cloud-signing service)
│   ├── Companion/              Watch companion bridge
│   ├── Observable/             ~55 ObservableObject managers/state objects  ← CORE LOGIC
│   ├── Server/                 local Vapor-based HTTP/HTTPS server, OTA manifest,
│   │                           WebManager (HTTP API + WebDAV)
│   └── Storage/                Core Data stack (Storage + 5 extensions, xcdatamodel)
├── CertificateDashboard/       certificate UI
├── CloneWizard/ Discovery/ Ecosystem/ OTA/ RepositoryBuilder/ RepositorySync/
├── Extensions/                 app-wide Swift/UIKit helpers
├── Resources/                  assets, Settings.bundle, icons
├── Security/                   AppLockManager, CertificateSecrets, SecureSecretStore
├── Utilities/
│   ├── ARDecompression/        ar/tar/deb decompression (hardened)
│   ├── CertificateReader/      X.509/provisioning parsing
│   ├── Handlers/               SigningHandler, TweakHandler(+Analyzer/Extractor),
│   │                           AppFileHandler, ArchiveHandler/Engine/AppArchiver,
│   │                           ZsignHandler, BackupCrypto, DirectInstaller, …
│   ├── IPAExplorer/            IPAWorkspace (+ change journal, undo)
│   ├── MachO/                  Obj-C Mach-O utils (LC patch/thin/fixup, bridged)
│   ├── Security/               SourceURLPolicy, TempStorageSweeper
│   ├── ArchiveSafetyValidator  ZIP pre-extraction security boundary
│   ├── FileIntegrity           streaming SHA-256
│   └── FR.swift                "feature router": static entry points wiring handlers
└── Views/                      SwiftUI + some UIKit (12 feature areas)

AltSourceKit/                   local SPM package: AltStore source models/parsing
NimbleKit/                      local SPM package: extensions + UI primitives
Tweaks/FilePickerFix            bundled tweak dylib source
VexSignWidgetExtension/         iOS widgets + Live Activities (iOS 26 target)
VexSignWatch/ VexSignWatchWidgets/ VexSignTV/ VexSignVision/   companion targets
VexSignTests/                   XCTest target (7 test files, 78 test methods)
Zsign/                          SUBMODULE: C++ signer + SwiftPM wrapper (branch `package`)
IDeviceKitten/                  SUBMODULE: IDeviceKit (Rust idevice xcframework + Swift)
server/                         Python FastAPI backend (self-hosted tools/repo store)
cloud-signing/                  TypeScript Fastify + BullMQ cloud signing orchestrator
docs/ tools/ .github/           docs, local tooling, CI workflows
```

Layering as it exists today (target state per the roadmap is NOT yet in place):

```
Views (SwiftUI/UIKit) ──► Backend/Observable managers (singletons, ObservableObject)
                              │
                              ├─► FR (static facade) ─► Utilities/Handlers ─► Zsign (submodule)
                              ├─► Backend/Server (Vapor) — OTA + WebManager
                              ├─► Backend/Storage (Core Data) / Keychain / UserDefaults
                              └─► IDeviceKitten (InstallationProxy/Heartbeat)
```

---

## 2. Major-module inventory

| Module | Location | Size | Responsibility |
|---|---|---:|---|
| App entry/lifecycle | `VexSignApp.swift` | 803 L | scene, URL routing (`_handleURL`), BG task registration, Nuke pipeline, legacy key migration |
| Download system | `Backend/Observable/DownloadManager*.swift` (3 files) | 934+395+246 L | fg/bg URLSessions, pause/resume/cancel, resume-data persistence, Live Activities, notifications, keep-alive |
| Download model | `Download.swift` | 129 L | per-download observable state + phase enum |
| Signing facade | `Utilities/FR.swift` | 411 L | `handlePackageFile`, `signPackageFile`, cert import, source handling, cert export |
| Signing pipeline | `Utilities/Handlers/SigningHandler.swift` | 637 L | copy→modify→inject→sign→move→register |
| Zsign adapter | `Utilities/Handlers/ZsignHandler.swift` | 95 L | only direct consumer of `ZsignSwift` signing API |
| Tweak injection | `Handlers/TweakHandler.swift`, `TweakAnalyzer.swift`, `TweakExtractor.swift`, `Observable/TweakManager.swift`, `TweakModels.swift`, `TweakRepository.swift` | 613+410+… L | deb/dylib/framework/bundle/appex injection, ElleKit handling, tweak repos |
| Import pipeline | `Handlers/AppFileHandler.swift` | 307 L | IPA copy→extract→move→Core Data |
| Archive engine | `Handlers/ArchiveHandler.swift`, `ArchiveEngine.swift`, `AppArchiver.swift` | — | zip/unzip with compression levels |
| Archive security | `Utilities/ArchiveSafetyValidator.swift` | 99 L | ZIP pre-validation (traversal/symlink/bomb) |
| IPA workspace | `Utilities/IPAExplorer/IPAWorkspace.swift` | 498 L | extract→edit→rebuild→sign→install, undo journal |
| Task center | `Backend/Observable/UnifiedTaskCenter.swift` | 414 L | unified task phases + history JSON; mirrors DownloadManager |
| Install pipeline | `Observable/AppInstaller.swift`, `InstallQueue.swift`, `InstallCleanup.swift`, `Handlers/DirectInstaller.swift` | 385+297+… L | OTA (itms-services) + idevice (InstallationProxy) paths with fallbacks |
| Local server | `Backend/Server/*` | 1926 L | Vapor app: OTA manifest/itms links (ServerInstaller), TLS, WebManager HTTP API + WebDAV |
| Storage | `Backend/Storage/*` | — | Core Data (Signed/Imported/Sources/Certificates), Feather→VexSign store migration |
| Security | `Security/*`, `Utilities/Security/*` | — | app lock, Keychain secret store, HTTPS source policy, temp sweeper |
| Integrity | `Utilities/FileIntegrity.swift` | 48 L | streaming SHA-256 (1 MiB chunks) |
| Backups | `Observable/BackupManager.swift`, `Handlers/BackupCrypto.swift` | 403+95 L | AES-GCM + PBKDF2(200k) encrypted `.vexbackup` |
| Sources/repos | `AltSourceKit`, `Views/Sources/*`, `RepositoryBuilder/`, `RepositorySync/`, `Observable/SourcePreferences` | — | AltStore-compatible sources, health, snapshots, builder/import/export |
| Updates | `Observable/AppUpdateChecker.swift`, `PerAppUpdateRules.swift`, `UpdateAllManager.swift`, `SkippedUpdatesManager.swift`, `SelfUpdateManager.swift` | — | version checks, per-app rules, self-update |
| Automation | `Observable/BackgroundAutomation.swift`, `AutoSignManager.swift`, `CleanupManager.swift` | — | BG maintenance: sources→updates→sign→queue→cleanup |
| Certificates | `Utilities/NexCerts.swift`, `CertificateReader/`, `CertificateAutoImporter.swift`, `CertificateExpiryMonitor.swift`, `Handlers/CertificateExporter.swift`, `CertificateFileHandler.swift`, `BatchCertChecker.swift`, `Utilities/P12Cracker.swift` | — | import/export/parse/expiry/status |
| Mach-O | `Utilities/MachO/MachOUtils.{h,m}`, `MachOReader.swift`, `MachOEntitlements.swift`, bridged `LC*` functions | — | SDK26 patch, ARM64 thinning, arm64e fixup, entitlement extraction |
| Cloud signing client | `Backend/CloudSigning/CloudSigningClient.swift` | 268 L | client for the TS cloud service |
| Companion | `Companion/*`, `Backend/Companion/CompanionBridge.swift`, Watch target | — | Watch snapshots/bridge |
| Widgets/Live Activities | `VexSignWidgetExtension/`, `DownloadProgressAttributes`, `SigningActivityAttributes`, `SigningLiveActivityManager`, `DownloadManager+LiveActivity` | — | ActivityKit progress UI |
| App Intents | `Backend/AppIntents/*` | — | Shortcuts: download control, app entities |
| Python backend | `server/` | ~4.8k L | FastAPI: repo store, web signer console, cert inspector, UDID grabber, repo creator/decoder, app installer page |
| Cloud orchestrator | `cloud-signing/` | ~600 L TS | Fastify + Zod + BullMQ + pg/ioredis + S3; hardened contracts, OTA capabilities, signed webhooks |

Swift LOC (first-party, `wc -l`): app 64,067 · AltSourceKit 1,539 · NimbleKit 2,490 ·
tests 1,367 · widget 1,059 · watch/tv/vision ~1,140. Total ≈ 71.7k lines, 455 `.swift` files.

---

## 3. Submodule status

| Submodule | URL | Pinned commit | Status |
|---|---|---|---|
| `Zsign` | `github.com/claration/Zsign-Package.git` (branch `package`) | `6ffe703` | ✅ initialized (`git submodule update --init --recursive` succeeded in this sandbox) |
| `IDeviceKitten` | `github.com/claration/IDeviceKit.git` | `837cf1e` | ✅ initialized |

* `Zsign` provides SwiftPM products `zsign` (C++/Obj-C) and `ZsignSwift`
  (Swift facade: `sign`, `checkSigned`, `injectDyLib`, `removeDylibs`,
  `listDylibs`, `changeDylibPath`). Depends on `krzyzanowskim/OpenSSL`.
* `IDeviceKitten` provides `IDevice` (binary xcframework, Rust `idevice`
  v0.1.57) and `IDeviceSwift` (InstallationProxy, Heartbeat/pairing, tracing).
* Both were missing from the fresh checkout and were fetched from their real
  Git remotes — no guessing or vendoring was needed.

---

## 4. Build status

| Artifact | Command | Result in this sandbox | Oracle |
|---|---|---|---|
| iOS app (`VexSign` scheme) | `xcodebuild -project VexSign.xcodeproj -scheme VexSign …` / `make` | ⛔ **cannot run** — Linux sandbox, no Xcode/swiftc; app needs Xcode 26 on macOS | GitHub Actions `build-check.yml` (macos-15) |
| Swift syntax parse | `swiftc -parse` via `quick-check.yml` (swift:6.4 container) | ⛔ no local swiftc; local proxy: `tools/check-swift-syntax.py` (tree-sitter) → **419/434 files parse clean**; the 15 flagged files match the tool's documented tree-sitter grammar-noise patterns (string interpolation, `try await` in switch cases) — CI's real `swiftc -parse` is authoritative and was green on `5602d49` | `quick-check.yml` |
| pbxproj integrity | `python3 tools/check-pbxproj.py` | ✅ pass (`pbxproj structure OK`, 7 targets) | local |
| quick-check resources/dupes | `python3 .github/scripts/quick_check.py --root .` | ✅ pass (0 errors; swiftc step skipped locally) | local + CI |
| Python backend | `server/.venv/bin/python -m pytest` deps per `server/requirements.txt` (exact pins) | ✅ import/collect OK | `server-tests.yml` |
| Cloud TS | `npm ci && npm run check` (`tsc --noEmit`) | ✅ **clean, exit 0** | `ecosystem.yml` |

**Platform limitation (recorded, not a defect):** no Xcode, no Swift
toolchain, no Docker in this environment. All Swift compile/test verification
goes through GitHub Actions CI, which is the project's established build
oracle (documented in the earlier `docs/STABILIZATION_BASELINE.md` and still
true).

---

## 5. Test status (executed in this checkout)

| Suite | Command | Result |
|---|---|---|
| Python backend | `cd server && pytest tests/` | ✅ **84 passed, 1 skipped** in 1.00 s. The skip is `test_inspect_parses_a_public_certificate` (needs outbound network to fetch a public cert). This verifies — not assumes — the previously reported "85/85" figure: 85 collected, 84 pass offline. |
| Cloud signing | `cd cloud-signing && npm test` (`tsx --test`) | ✅ **12/12 passed** (api, jobs, security: idempotency, owner isolation, quotas, password envelopes, OTA capability expiry, webhook policy, contract rejection of shell args/oversized batches, missing-signer failure) |
| Cloud typecheck | `npm run check` | ✅ clean |
| Swift unit tests (`VexSignTests`) | `xcodebuild test -scheme VexSignTests` | ⛔ cannot execute on Linux (needs iOS simulator + Xcode). **No CI job executes them either** — see §6 gap. |

## 6. Existing test coverage

**Swift (`VexSignTests/`, 7 files, 78 `func test…`):**

| File | Tests | Covers |
|---|---:|---|
| `StabilityAndArchitectureTests.swift` | 14 | source health, HTTPS source policy, archive entry-name sanitization, per-app update rules, unified task pipeline, backup crypto round-trip, feature-status registry |
| `MissingFeatureTests.swift` | 23 | feature contracts (tabs, settings→persistence→consumer chains) |
| `EcosystemTests.swift` | 12 | repo sync/ecosystem |
| `CompanionAndWidgetTests.swift` | 11 | companion payloads, widget payloads |
| `ImportAndInstallationTests.swift` | 8 | import + install preparation |
| `IntegrityAndParsingTests.swift` | 8 | SHA-256, plist/parsing |
| `VexSignTests.swift` | 2 | live repo JSON decode (network), repo deobfuscation |

Coverage is real but biased toward preferences/policies/crypto. **Missing:**
signing golden tests, fixture-corpus IPA tests, archive-extraction security
corpus (only entry-name policy is tested), download resume/recovery tests,
install-path mock tests, workspace round-trip tests.

**Coverage tooling:** no coverage reports are generated in CI; no percentage
is claimed here (per instructions, none is fabricated).

**CI gap (critical for Phase 1):** `build-check.yml` builds the app scheme
only; *no workflow runs `xcodebuild test`*, so the 78 Swift tests compile at
best implicitly and never execute. A test job is the single highest-leverage
Phase 1 item.

---

## 7. Dependency status

* **SwiftPM (42 pins, committed `Package.resolved` in the xcworkspace):**
  notable — Vapor 4.104 (+ NIO 2.94 stack, NIO-SSL, HTTP/2), Nuke 12.8,
  SWCompression 4.8.6, ZIPFoundation 0.9.20, Zip 2.1.2, swift-crypto 3.15.1,
  swift-certificates 1.17.1, swift-asn1, Yams, XcodeEdit, LicensePlist,
  OpenSSL 3.6.1 (via Zsign). All pinned by version; resolution happens in CI.
* **Local packages:** `AltSourceKit`, `NimbleKit` (in-repo, no remotes).
* **Submodules:** see §3 — both fetchable and pinned.
* **Python (`server/requirements.txt`, exact pins):** fastapi 0.141.1,
  uvicorn 0.53.0, python-multipart 0.0.32, httpx 0.28.1 (+ pytest to run
  tests). Installed cleanly into a venv; no conflicts.
* **Node (`cloud-signing/package-lock.json`):** Node ≥ 22 (sandbox has 22.22.3);
  `npm ci` clean; fastify 5, bullmq 5, pg, ioredis, zod 4, AWS SDK v3, tsx.
* **Cloud infra deps at runtime:** PostgreSQL, Redis, S3-compatible storage —
  not needed for unit tests (tests use fakes); documented in
  `cloud-signing/README.md` + `render.yaml`/`Dockerfile`.

---

## 8. Major architectural hotspots (verified, with sizes)

1. **`Views/TabView/AppStoreView.swift` — 1,567 L.** Largest view; mixes
   search, categories, collections, sources, header. Split candidate (§18).
2. **`Backend/Observable/DownloadManager.swift` — 934 L (+246 delegates, +395
   Live Activity).** One NSObject owns sessions, keep-alive, notifications,
   Live Activities, resume-data files, timers, speed tracking. Hotspot for
   Phase 3.
3. **`VexSignApp.swift` — 803 L.** URL routing (~200 L of `_handleURL`),
   background-task handlers, Nuke setup, migration all inline. Phase 7.
4. **`Views/Library/LibraryView.swift` — 747 L**, `HomeView.swift` — 685 L:
   large but coherent for now.
5. **`Utilities/Handlers/SigningHandler.swift` — 637 L** and **`FR.swift` —
   411 L**: signing pipeline is procedural (copy/modify/move/register) with
   implicit stage ordering; no engine abstraction, no post-sign verification.
6. **`TweakManager.swift` 627 L / `TweakHandler.swift` 613 L /
   `TweakAnalyzer.swift` 410 L**: injection works but planning is implicit;
   no plan/dry-run model yet.
7. **Singleton gravity:** ~27 `ObservableObject` managers in
   `Backend/Observable/`, almost all `.shared` singletons reached directly
   from views and from each other (DownloadManager ↔ UnifiedTaskCenter ↔
   AutoSignManager ↔ CleanupManager …). This is the main obstacle to testing.
8. **`Views/Sources/*` + `SourceAppsView` etc.** — source UI spread across
   several 450–570 L files; version/update logic partially centralized
   already (`AppUpdateChecker`, `PerAppUpdateRules`).

## 9. Security hotspots

| Area | Current state | Risk |
|---|---|---|
| ZIP extraction | `ArchiveSafetyValidator` (paths, `..`, absolute, `~`, NUL, symlinks, 50k-entry & 8 GB limits) runs before `Zip.unzipFile` in IPAWorkspace; `Zip` lib also sanitizes | ✅ strong; needs a malicious-archive fixture corpus (§Phase 1) |
| tar/deb extraction | `Decompression._isSafeArchiveEntryName` + regular/dir-only materialization | ✅ hardened last cycle; same corpus gap |
| WebManager server | binds **0.0.0.0**; has token auth (constant-time compare) and `resolve()` path sanitization | ⚠️ exposure policy is implicit — no explicit LocalhostOnly/LocalNetwork mode; WebDAV path surface deserves adversarial tests (Phase 10) |
| OTA/local server | ServerInstaller with TLS options; itms-services links | ✅ functional; manifest hosting (Semi Local) depends on external service |
| Sources | `SourceURLPolicy` HTTPS-by-default with opt-in HTTP | ✅ |
| Secrets | P12 passwords in Keychain (`CertificateSecrets`, fail-closed), Core Data field nulled post-migration; URL-scheme cert import passes password in query (by design, Feather-compatible) | ✅ mostly; diagnostics redaction should be re-verified |
| Cloud | Zod contracts, owner-scoped queries, idempotency keys, AES-GCM sealed secrets via stdin, HMAC capabilities, webhook allowlist+HTTPS, no shell | ✅ strong; SSRF/DNS-rebinding on fetch-side endpoints + artifact expiry are the remaining items (Phase 10) |
| `P12Cracker.swift` | local brute-force of user's own forgotten P12 password | legal/legitimate feature; keep isolated, never networked |
| Force unwraps/`try!`/`as!` | ≈19 force unwraps repo-wide (≈15 app-only), **0 `try!`**; 2 `as!` confined to `NimbleKit/NBVariableBlurView.swift` (private-API blur bridge); 2 `fatalError` = required `init(coder:)` boilerplate only (was 4 `try!`/3 `as!` before `5602d49`) | ✅ much improved; remaining unwraps to be reviewed on networking/download paths |
| `try?` | 393 occurrences — most are cleanup (`try? FileManager.removeItem`), some on paths that matter (e.g. resume-data writes) | triage in Phases 2/3 |

## 10. Concurrency hotspots (counts re-measured on `5602d49`)

| Pattern | Count | Notes |
|---|---:|---|
| `@MainActor` annotations | 149+ | incl. `UnifiedTaskCenter`, `InstallQueue`, `IPAWorkspace`, `AppInstaller` |
| `DispatchQueue.main.async` | 108 | mostly UI hops; contract-audit partially done last cycle |
| `Task.detached` | 27 | `FR.*` pipelines, IPAWorkspace copy/zip, install progress polling |
| `DispatchQueue.global` | 19 | hashing, imports, BG-task polling loops |
| `actor` | 5 | `EcosystemDatabase` etc. |
| `NotificationCenter` observers | ~43 | |
| `Task.sleep`/`Thread.sleep` polling | several | BG task handlers use `Thread.sleep` loops (acceptable in BGProcessing context but worth modernizing later) |

Known issues: `Download` model is mutated from session-delegate threads and
main (mitigated by hops but not enforced); `SigningHandler` is not isolated
(run in `Task.detached`, touches `SigningLog` + FileManager only — OK);
`DownloadManager` mixes Combine, timers, delegates. Language mode is Swift
5.0 everywhere (widget has `SWIFT_APPROACHABLE_CONCURRENCY=YES`), so the
compiler does not catch races — CI green-build remains the oracle.

## 11. Persistence/storage map (ownership as implemented)

| Mechanism | Owner | Contents |
|---|---|---|
| Core Data (`VexSign.xcdatamodel`) | `Storage` (+Certificate/Imported/Shared/Signed/Sources) | library metadata: signed/imported apps, certificates (public fields), sources; legacy Feather store auto-migrated; aggressive-reload load path |
| SQLite (WAL) | `EcosystemDatabase` actor (`Application Support/Ecosystem/cache.sqlite`) | disposable ecosystem/repo sync cache (key/blob), `user_version=1` |
| Keychain | `SecureSecretStore`/`CertificateSecrets` | P12 passwords; AppLock secret |
| UserDefaults | ~all preference objects (`SourcePreferences`, `PerAppUpdateRules`, `DownloadPreferences`, `TabBarPreferences`, health records, legacy Feather/Ryuk key migration in `VexSignApp.init`) | preferences + small JSON blobs (rules, health) |
| Filesystem — Documents | `FileManager+documents` | `Signed/<uuid>/`, `Unsigned/<uuid>/`, `Archives/`, `Certificates/`, `IPAWorkspaces/`, `SourceSnapshots/`, `ResumeData_<id>.data` |
| Filesystem — App Support | | `UnifiedTaskHistory.json`, `Ecosystem/` |
| Filesystem — temp | | `VexSigning_<uuid>/`, `VexSignShared*/`, install staging; `StorageManager.purgeStaleTemporary()` + `TempStorageSweeper` on launch |
| S3 | cloud-signing only | private cloud artifacts (presigned URLs, expiry) |

Risk notes: `ResumeData_*.data` lives at Documents root (clutter + no index);
UnifiedTask history is titles/outcomes only (good); no schema-version field in
the task-history JSON yet.

## 12. Signing pipeline map (as implemented today)

```
UI (SigningView / Library re-sign / BatchSignView / IPAWorkspace.signAndInstall
    / AutoSignManager after download / Web Manager)
  └─► FR.signPackageFile(app, options, icon, certificate)      [Task.detached]
        ├─ SigningLog.reset + SigningLiveActivityManager.start
        ├─ UnifiedTaskCenter.begin(.sign) … transition(.completed/.failed)
        ├─ BackgroundTaskManager keep-alive
        └─► SigningHandler
              copy()     → temp/VexSigning_<uuid>/<App.app> (input IPA/app untouched)
              modify()   → Info.plist plan (InfoPlistPlan.apply), plugin bundle-id
                           rewrite, display name locales, icon replace, file removal,
                           watch/appex stripping (opt-in), LiquidGlass SDK26 patch,
                           ARM64 thinning, TweakHandler.getInputFiles() injection,
                           arm64e slice fixup, keychain isolation, JIT entitlements,
                           ZsignHandler.disinject() (remove dylibs),
                           ZsignHandler.sign()  → Zsign.sign(...) [C++ submodule]
              move()     → Documents/Signed/<uuid>/
              addToDatabase() → Core Data `Signed`
        (cloud alternative: CloudSigningClient → cloud-signing service)
```

Gaps vs. target (§7–§10 of the mandate): no `SigningEngine` protocol, no
explicit stage machine (stages are implicit in method order), **no post-sign
verification boundary** (success = Zsign returned true; `Zsign.checkSigned`
exists but is not called after signing), no input/output SHA-256 recorded for
sign jobs, no workspace-commit semantics (partial `Signed/<uuid>` is cleaned
only via `clean()` heuristics).

## 13. Download pipeline map

```
Sources tab / DownloadsTab / deep links (vexsign://direct-install, /install/)
 / share-sheet IPA import / Web Manager
  └─► DownloadManager.startDownload(url)  | startArchive(localURL)   [@MainActor-ish]
        • guards: GameMode, wifi-only, charge-only, maxParallel slot
        • dedupe by URL (resume existing)
        • foreground vs background URLSession chosen by isAppInBackground
        • premium auth headers (VexSignAPI)
  └─► URLSession delegate callbacks (DownloadManager+Delegates)
        • progress → Download model → Live Activity / notifications (throttled 2 s)
        • completion → handlePackageFile(url, dl)
             ├─ SHA-256 of package logged (FileIntegrity, background)
             ├─ dl.pendingFileURL = url  (retry point)
             └─ FR.handlePackageFile → AppFileHandler.copy/extract/move/addToDatabase
                  └─ optional AutoSignManager.sign(app)
        • pause → cancel-by-resume-data; ResumeData_<id>.data persisted
        • appWillTerminate → cancel running tasks, save resume data (500 ms budget)
```

Gaps: no launch-time reconciliation of persisted resume data against live
session state (jobs lost across termination unless `pendingFileURL` retry
fires); duplicate-dedupe is URL string equality; destination-conflict policy
lives inside `AppFileHandler.move`; Live-Activity state machine is spread
across 3 files.

## 14. Installation pipeline map

```
Library/Sign result/Batch → InstallQueue.shared.enqueue(app)   [@MainActor, serial]
  └─► AppInstaller(app)                                          [@MainActor]
        _package()  → ArchiveHandler.move()+archive()  (Task.detached) → .ipa staging
        then by VexSign.installationMethod:
          1 → InstallationProxy.install(at:)         [IDeviceKitten: pairing/tunnel/idevice]
          0 → ServerInstaller (Vapor, 0.0.0.0:<port>, TLS optional)
                ├─ Fully Local: manifest + itms-services link served locally
                ├─ Semi Local: ManifestService external manifest
                ├─ selfCheck() then open itms-services URL
                └─ decline-watch (prompt dismissal heuristic) + progress polling
        fallbacks: server failure → idevice path if pairing file exists (one retry)
        InstallCleanup.flushOnLaunch() cleans staging
```

Gaps: verification of installation relies on installd progress-poll heuristic
(drop-to-zero ⇒ done) — documented behavior, keep; no `InstallService`
protocol boundary yet; OTA vs idevice selection is UserDefaults-integer based.

## 15. Feature inventory (implemented today — verified in source)

IPA import ✅ · IPA inspection/exploration (IPA Explorer + journal/undo) ✅ ·
Info.plist editing (SigningInfoPlistView + InfoPlistPlan) ✅ · Mach-O
inspection (MachOReader, listDylibs) ✅ · arch thinning (LCThinMachOToARM64) ✅ ·
dylib/framework/bundle/appex/tweak injection (TweakHandler) ✅ ·
ElleKit/Substrate handling (bundled ellekit.deb, substrate-hook detection) ✅ ·
signing profiles (SigningProfileStore, NamedSigningProfileStore) ✅ ·
certificate/P12 management incl. expiry monitor, batch cert check, P12
recovery cracker ✅ · provisioning handling ✅ · entitlement editor +
EntitlementBuilder (JIT, keychain isolation) ✅ · local signing (Zsign) ✅ ·
batch signing (BatchJobRunner/BatchSignView) ✅ · signing queue/logs
(SigningLog, Live Activity) ✅ · background signing (BG tasks + keep-alive) ✅ ·
download management (fg/bg, pause/resume/cancel/retry slots, wifi/charge
guards, Game Mode) ✅ · installation (OTA itms-services + idevice + share
sheet + DirectInstaller URL install) ✅ · device communication/pairing
(HeartbeatManager, pairing files, tunnel) ✅ · AFC-style pathways via
IDeviceKitten InstallationProxy ✅ · local HTTP/HTTPS serving (Vapor,
optional TLS with LocalCAProfile) ✅ · WebDAV + Web Manager (upload, API,
zip routes) ✅ · repo/source management (AltStore-compatible, obfuscated
codes, premium keys) ✅ · source health + offline snapshot cache + discovery
✅ · categories/collections/favorites (Ecosystem/Discovery) ✅ ·
app/version resolution (AppUpdateChecker) + per-app update rules ✅ ·
repository creation/import/export (RepositoryBuilder + server repo_creator) ✅ ·
OTA manifest generation (ManifestService + OTAExporter + server web_tools) ✅ ·
automatic signing/update workflows (AutoSignManager, BackgroundAutomation) ✅ ·
encrypted backups (AES-GCM `.vexbackup`) ✅ · diagnostics
(DiagnosticBundleExporter, FileLogger, SigningLog) ✅ · Keychain storage ✅ ·
app locking (AppLockManager) ✅ · integrity verification (FileIntegrity
SHA-256 UI + auto hash-on-download) ✅ · Live Activities (download + signing) ✅ ·
widgets (iOS 26 widget ext, watch widgets) ✅ · App Intents/Shortcuts ✅ ·
Watch companion ✅ · cloud signing client + TS cloud service ✅ ·
Python backend tools (repo store, signer console, cert inspector, UDID
grabber) ✅ · self-update (SelfUpdateManager) ✅ · automation cleanup
(CleanupManager) ✅ · app cloning (AppCloner/CloneWizard) ✅ · IPSW browsing
(IPSWBrowser) ✅ · anti-revoke utilities ✅.

No feature removal is proposed anywhere in this plan.

## 16–19. File dispositions

### 16. KEEP (correct, hardened, or load-bearing — protect with tests)

`ArchiveSafetyValidator.swift`, `FileIntegrity.swift`, `ZsignHandler.swift`
(already the only Zsign-sign adapter), `BackupCrypto.swift`,
`SecureSecretStore.swift`/`CertificateSecrets.swift`, `SourceURLPolicy.swift`,
`EcosystemDatabase.swift`, `UnifiedTaskCenter.swift` (extend, don't replace),
`Storage*.swift` (Core Data incl. Feather migration), `EntitlementBuilder.swift`,
`InfoPlistPlan.swift`, `PerAppUpdateRules.swift`, `SourcePreferences.swift`,
`AltSourceKit/` (whole package), `Decompression.swift`/`AR.swift` (hardened),
`cloud-signing/src/*` (improve, don't replace), `server/*` (tests green),
`Zsign/` + `IDeviceKitten/` submodules (never rewrite).

### 17. REFACTOR (isolate behind boundaries, same behavior)

* `FR.swift` → thin facade over real services (SigningService etc.); keep
  entry-point signatures during transition.
* `SigningHandler.swift` → explicit stage machine + workspace + verifier;
  keep every modification behavior (characterization tests first).
* `DownloadManager.swift` → coordinator/registry/persistence/live-activity
  extraction (Phase 3), keep public API stable meanwhile.
* `AppInstaller.swift` + `InstallQueue.swift` → `InstallService` boundary
  preserving OTA↔idevice fallback logic (Phase 4).
* `VexSignApp.swift` → extract `AppURLRouter`, startup sequence, BG task
  coordinator (Phase 7).
* `TweakHandler.swift` → plan/execute split around existing code (Phase 2).
* `WebManagerServer*.swift` → explicit exposure policy + path-validation tests
  (Phase 10).

### 18. SPLIT

* `AppStoreView.swift` (1,567 L) → header/search/categories/collections/rows
  (Phase 11, visual parity first).
* `DownloadManager+LiveActivity.swift` (395 L) is already a split — further
  split notifications vs activity state.
* `LibraryView.swift` (747 L), `HomeView.swift` (685 L), `TweaksView.swift`
  (551 L), `SourcesView.swift` (561 L) — later, only with parity tests.

### 19. Might eventually be REPLACED (only with evidence, never speculatively)

* `Zip` (marmelroy) usage where `ZIPFoundation` alone would reduce one
  dependency — only after extractor unification proves it safe.
* `Thread.sleep` BG-polling loops → async waits (behavior-neutral).
* Nothing else. Zsign, IDeviceKit, Vapor server, Core Data, SQLite cache,
  Keychain store, backup format: **not replaceable without a documented
  defect or security reason.**

---

## 20. Exact Phase 1 implementation plan (test foundation — no major refactors)

**Goal:** make the existing suite executable in CI, then add the missing
characterization/security tests around the most fragile boundaries. Zero
production behavior change except bug fixes a test proves.

**P1-A. CI test execution (unblocks everything)**
1. Add a `swift-tests.yml` (or extend `build-check.yml`) job on `macos-15`:
   `xcodebuild test -project VexSign.xcodeproj -scheme VexSignTests
   -destination 'platform=iOS Simulator,name=iPhone 16'` with submodules
   initialized; fail on test failure; upload xcresult.
2. Run it once on the current tree to record the true pass/fail baseline of
   the 78 Swift tests (several hit the network by design — `testRepoParsing`,
   deobfuscation fixtures are local). Quarantine (do not delete) any
   network-only test if flaky, behind an env flag.

**P1-B. Fixture corpus (`VexSignTests/Fixtures/` + generator script)**
3. `tools/make_test_ipas.py` (or Swift fixture builder) producing: simple
   IPA, framework-heavy IPA, appex IPA, multi-arch (fake Mach-O headers),
   watch-app IPA, malformed Info.plist IPA, wrong-bundle-id IPA, IPA with
   existing dylib injection, two-tweak IPA, oversized-entry zip,
   many-entries zip. Small synthetic Mach-Os are sufficient for parser tests.
4. Fixture load helper + `ArchiveSafetyValidator` adversarial tests:
   `../escape`, `../../escape`, absolute path, `~` path, NUL byte, symlink
   entry, oversized entry, entry-count bomb, duplicate entries, nested
   malicious path — asserting each is rejected with the right `ValidationError`.
5. tar/deb entry-name tests extended from the same corpus
   (`Decompression` boundary).

**P1-C. Signing characterization (golden-property tests, no hard-coded sigs)**
6. `SigningHandlerTests` with a stubbed `ZsignHandler` seam (inject a
   protocol or closure *test double only* — production class untouched):
   verify stage order copy→modify→sign→move→register on success, cleanup on
   failure, original input untouched, `Signed/<uuid>` not left behind when
   `addToDatabase` fails.
7. `InfoPlistPlan` + `EntitlementBuilder` property tests (bundle id/version/
   name changes, JIT gating on PPQ certs, keychain-group isolation rules).
8. `TweakAnalyzer` tests on fixture dylibs/debs (injectable detection,
   substrate-hook detection) — characterization of current output.

**P1-D. Download & workspace characterization**
9. `DownloadManager` tests with a protocol-extracted session factory
   (smallest possible seam): dedupe by URL, pause→resume-data round trip,
   cancel removes resume file, `pendingFileURL` retry point survives.
10. `IPAWorkspace` round-trip test on fixture IPA: open→edit marker→rebuild→
    reopen finds app; journal undo restores bytes; traversal entries never
    escape workspace root.

**P1-E. Install & task-center characterization**
11. `InstallQueue` tests: ordering, per-entry outcomes, failure keeps rest,
    export entries never get "Open".
12. `UnifiedTaskCenter` tests: phase transitions, terminal lock, history cap
    200, download mirror mapping (already partially covered — extend).

**P1-F. Backend regression lock-in**
13. Cloud: add SSRF/private-IP rejection tests for any fetch-side endpoint,
    webhook retry test, artifact-expiry test (extend existing 12).
14. Server: keep 84+1 green; add repo-store corruption-recovery test if cheap.

**Exit criteria for Phase 1:** Swift tests run in CI with recorded baseline;
archive security corpus green; signing stage-order characterization green;
no production behavior change in the diff (reviewed file-by-file); docs
updated with the recorded numbers.

---

## Appendix A — Commands (verified)

```bash
git submodule update --init --recursive          # both submodules fetch OK

# Python backend
cd server && python3 -m venv .venv
.venv/bin/pip install -r requirements.txt pytest
.venv/bin/python -m pytest tests/                # → 84 passed, 1 skipped

# Cloud signing
cd cloud-signing && npm ci && npm test           # → 12/12 pass
npm run check                                    # tsc --noEmit clean

# Static/local gates (Linux-safe)
python3 .github/scripts/quick_check.py --root .  # resources/dupes/pbxproj
python3 tools/check-pbxproj.py                   # pbxproj structure OK
python3 tools/check-swift-syntax.py              # tree-sitter proxy (advisory)
tools/health-check.sh                            # combined report (added in Phase 0)

# Real builds (macOS/Xcode 26 only — CI is the oracle)
make deps && make                                # unsigned Release IPA
xcodebuild -project VexSign.xcodeproj -scheme VexSign -configuration Debug build
```

## Appendix B — Health indicators at baseline (indicators, not scores)

| Indicator | Value |
|---|---|
| Swift files / LOC (first-party) | 455 / ~71.7k |
| Force unwraps (approx., all first-party targets) | ~19 (app-only ≈15) |
| `try!` | 0 everywhere |
| `as!` | 2 — both in `NimbleKit/NBVariableBlurView.swift` (private-API blur bridge), 0 in app code |
| `fatalError` | 2 — both required `init(coder:)` boilerplate, 0 recoverable-logic uses |
| `try?` total | 393 (mostly cleanup paths) |
| `Task.detached` | 27 |
| `DispatchQueue.main` / `.global` | 108 / 19 |
| `actor` declarations | 5 |
| TODO/FIXME in app code | 0 |
| Largest files | AppStoreView 1567 · DownloadManager 934 · VexSignApp 803 · LibraryView 747 · HomeView 685 · SigningHandler 637 |
| Python tests | 85 (84 ✅ / 1 ⏭ network) |
| Cloud tests | 12 ✅ |
| Swift tests | 78 written, 0 executed by CI (gap) |
