# Phase 1 — Concurrency & crash-risk audit

**Scope.** Production targets compiled by the `VexSign` CI scheme (app +
embedded widget), i.e. `VexSign/**` and `VexSignWidgetExtension/**`.
`server/`, `cloud-signing/` and the Zsign/IDeviceKitten submodules are out of
scope (separate runtimes / dependency boundary — see
`STABILIZATION_BASELINE.md` §8.4).

**Method.** The project builds with `SWIFT_VERSION = 5.0` (Swift 5 language
mode), so the compiler does **not** enforce Sendable/actor isolation — data
races and wrong-queue UI updates compile silently. This audit is therefore a
static census + triage; every fix that follows must be validated by CI
(build-check Debug+Release), which is the only available build oracle in this
environment.

Counts below are from the tree at the time of writing (post main-merge);
they are stable to ±1 across fix commits.

| Class | Count | Compiler-enforced? |
|---|---|---|
| `try!` | 4 (2 prod + 2 test) | no |
| `as!` | 3 (all prod) | no |
| Force-unwraps (`x!`) | ~16 prod | no |
| `fatalError` | 2 prod | n/a (intentional) |
| `Task.detached` | 27 | no |
| `DispatchQueue.main` | 108 | no |
| `DispatchQueue.global` | 19 | no |
| `@MainActor` annotations | 149 | yes (when isolated) |
| `actor` declarations | 5 | yes |
| Continuation bridges (`withChecked(Continuation)`) | 10 | partial |
| `NotificationCenter` observers | 43 | no |

---

## 1. P0 — crash on plausible runtime paths

### 1.1 Core Data unrecoverable error → `fatalError`
`VexSign/Backend/Storage/Storage.swift:110`

```swift
fatalError("Core Data unrecoverable: \(error)")
```

Any corrupt store (bad shutdown, disk full during save, migration error)
crashes the app with zero recovery. Baseline §8.3. **Fix (Phase 2):**
replace with the existing backup-and-reset path: log, export the corrupted
store for diagnostics, rebuild an empty store, surface a user-facing alert.
The lightweight-migration policy already established for the schema
(optional relaxation, §Phase-1 fix v1) is the same data-preserving
philosophy applied at runtime.

### 1.2 `DispatchQueue.main.async` state updates from untrusted threads
Census: 108 `DispatchQueue.main` calls. The pattern is widespread and mostly
correct, but the audit must verify each site **touches UI state**, not just
"moves work to main". High-value check: every completion handler of
`Task.detached` / `URLSession` / Core Data save must hop to main before
mutating `@Published`/`@State`. The `startArchive`-style completion-on-main
contract (`DownloadManager.swift:613`) is an example of a handler whose
threading contract is documented — replicate that discipline as fixes land.

### 1.3 Force-unwraps that can fail at runtime
Highest risk first:

| Site | Expression | Risk |
|---|---|---|
| `DownloadManager.swift:571` | `_backgroundSession!` / `_foregroundSession!` | Session created lazily; if the getter runs before init completes (app relaunch race) → crash. Guard with `guard let`. |
| `DownloadManager.swift:666,675` | `session!.downloadTask(...)` | `URLSession` API called off-main on a mutable property; nil-able under teardown. Capture locally + guard. |
| `LibraryInfoView.swift:42`, `CertificatesInfoView.swift:40` | `Storage.shared.getUuidDirectory(for:)!.toSharedDocumentsURL()!` | Double force-unwrap on user-data paths; a missing directory (user deleted via Files) crashes the settings screen. `if let` + disable the button. |
| `SourceAppsView.swift:289`, `SourcesAddView.swift:189` | `$0.sourceURL!` | Model invariant (URL always present); acceptable short-term, convert to `sourceURL ?? .localized` fallback. |
| `WebManagerServer+HTTP.swift:201` | `upload.nickname!` | Already guarded by the ternary — safe, but the `as? String)!` in `TweakManager.swift:228` is the same anti-pattern repeated; collapse to one `let name = entry["name"] as? String`. |
| `ServerInstaller+Compute.swift:61` | `components.url!` | `URLComponents` built in-process; safe by construction — convert to `?? current` for hygiene. |
| `ServerInstaller+TLS.swift:160,181` | `ptr!.pointee` | `getifaddrs` C pointer walk; nil only on malformed system data. Keep, add `guard` for the loop sentinel. |

`as!` (3×) — `VexSignApp.swift:588,595,604`: `task as! BGProcessingTask` /
`as! BGAppRefreshTask` inside `BGTaskScheduler.register` callbacks. The
identifier string selects the class, so the cast is safe **by construction**,
but a registration/id collision would crash in the background (app is
suspended — a crash here is unrecoverable and reported only by the system).
**Fix:** `as?` + `task.setTaskCompleted(false)` fallback + log.

## 2. P1 — background-task lifetime & cancellation

### 2.1 `Task.detached` (27 sites)
Detached tasks escape cancellation and actor context by design. The
census shows two shapes:

* **`await Task.detached { ... }.value`** (majority — FR, AppCloner,
  ArchiveHandler, StorageManager, P12Cracker, CertificateInspector,
  BackupManager, IPAWorkspace, TweakInfoView, FRAppIconView, …): used to
  run blocking/legacy work off the main actor. Functionally fine today;
  the cost is losing cancellation propagation and (in Swift 6) Sendable
  friction. **Plan:** leave as-is in Phase 1; migrate per-site to
  `nonisolated` async functions when each file is touched, and add
  `Task.checkCancellation()` to long loops (zip unpacking, certificate
  walks).
* **Fire-and-forget `Task.detached { … }`** (FR.swift:24,52,119;
  CertificateAutoImporter.swift:228; FileBrowserViewModel.swift:38;
  AppInstaller.swift:345 `_progressTask`): retain in a property or
  `withTaskCancellationHandler` if the work outlives the triggering
  function. `AppInstaller._progressTask` is stored — correct. The FR.swift
  trio is one-shot file work — acceptable, but the closures capture
  `self`/managers strongly; verify no retain cycles through completions.

### 2.2 Continuations (10 sites)
`withCheckedContinuation` bridges completion handlers (ZIP, p12, network).
Audit rule: **exactly one** `resume` per continuation, on every path
including early `guard` returns. A double-resume is a runtime trap
("continuation already resumed"); a missed resume hangs the UI forever.
These 10 sites get a line-by-line review in Phase 2; none were flagged in
the Phase 0 pass, but the rule must be re-checked after the import sweep
because several bridged functions changed call sites.

### 2.3 `DispatchQueue.global` (19 sites)
Legacy GCD offloading. Same migration policy as §2.1: fine now, convert
when the enclosing file is otherwise touched. Do **not** refactor in a
build-stabilization commit — each conversion changes cancellation/queue
semantics and needs CI + manual verification.

## 3. P2 — hygiene / coupling

* **`NotificationCenter` (43 observers).** Global string-coupling; several
  posts (download finished, cert added) are visible from both the app and
  widget extension. Migration target: the existing `UnifiedTaskCenter`
  `ObservableObject` (already the single source of truth for task state).
  Not a build risk; schedule in Phase 3+.
* **`@MainActor` coverage (149).** Good baseline. Gaps to close when the
  Swift 6 mode flag is trialed (Phase 16 gate): the 5 `actor` types,
  `DownloadManager` (currently a non-isolated `ObservableObject` with
  manual main hops — the largest single isolation project), `InstallQueue`,
  `UnifiedTaskCenter`.
* **`try!` (2 prod):** `ServerInstaller+TLS.swift:20-21` (Vapor
  `Environment.detect()` / `LoggingSystem.bootstrap`) — bootstrap of an
  in-process HTTP server; failure = misconfigured developer environment,
  but the `try!` turns that into an app crash. Wrap in `do/catch` →
  server-disabled state + log. The 2 in `VexSignTests` are test-only.

## 4. Execution order (ties to phases)

1. **Build green first** (current effort) — no concurrency fixes mix into
   the error-drain commits; CI is the oracle and diff noise must stay
   reviewable.
2. **P0 items** — `Storage.swift:110` recovery, `DownloadManager` session
   guards, the two double-`!` settings-screen sites, BGTask `as?` casts.
   One commit per subsystem, CI-verified.
3. **P1 items** — per-file, only when that file is touched for another
   reason (keeps churn low); continuation one-resume review of the 10
   bridges.
4. **P2 + Swift 6 trial** — Phase 16: add an `xcodebuild test` CI job
   (suite exists, currently never run), then a *separate* experimental
   branch with `SWIFT_STRICT_CONCURRENCY = target` to enumerate compiler
   findings without failing main.

**Stop conditions** (per phase rules): any fix that requires changing a
public API of a submodule (Zsign, IDeviceKitten) or that changes
`sourceURL!`/model invariants in `AltSourceKit` stops and escalates —
those are dependency boundaries, not app defects.
