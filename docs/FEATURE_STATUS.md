# End-to-end feature status

Every claim below is tracked as a full pipeline — **setting → persisted value
→ real consumer** — instead of a blanket "supported". The same registry is
visible in-app under *Settings → About → Feature Status* and enforced by
`StabilityAndArchitectureTests.testFeatureStatusRegistryCoversCriticalPipeline`.

Legend:

- **Implemented** — the chain is wired in code and covered by unit tests
  where the host allows it (settings → persistence → consumer).
- **Needs device** — wired end-to-end, but the last mile (actually
  signing/installing on real hardware) requires a physical-device pass that
  CI cannot provide.

| Feature | Setting | Persisted as | Consumer | Status |
| --- | --- | --- | --- | --- |
| Forced signing | Advanced Signing → Force Sign All | `Options` (OptionsManager) | `SigningHandler` → Zsign | Implemented |
| SDK spoofing / Mach-O changes | Signing Options → SDK & Mach-O | `Options` (OptionsManager) | `SigningHandler.modify()` | Implemented |
| Auto-sign on download | Automation → Sign after download | `VexSign.autoSign…` keys | `DownloadManager` → `AutoSignManager.sign()` | Implemented |
| Compatibility opt-out clearing | Signing Options → Compatibility | `Options` (OptionsManager) | `SigningHandler.modify()` on update | Implemented |
| Per-app certificate selection | App context → Signing certificate | per-app options / `PerAppUpdateRules.pinnedCertificateUUID` | `FR.signPackageFile(certificate:)` | Implemented |
| Quick Sign | Home → Quick Sign | — (immediate action) | `FR.handlePackageFile` → `SigningView` | Implemented |
| Re-sign / re-install | Library → app → Re-sign | — (library action) | `FR.signPackageFile` → `InstallQueue` | Needs device |
| Asset / file modifications | Signing customization, IPA Explorer | per-app options + IPA Explorer edits | `SigningHandler` / file replacement | Implemented |
| Dynamic Island download controls | Downloads settings | Live Activity state | `DownloadProgressAttributes` + app-group commands | Needs device |
| Strict app hiding | Settings → Security → Hidden Apps Vault | `AppLockManager` sets | Library/Home filters | Implemented |
| Six-tab navigation structure | Settings → Tab Bar (launch tab only) | `TabBarPreferences` (primary tabs immutable) | `TabbarView` | Implemented |
| Appearance (theme/font/animations) | Settings → Appearance | `AppearanceStore` (4 keys) | App root environment, `Theme`, button styles | Implemented |
| Offline repository catalog | automatic (last-known-good) | `SourceSnapshots/` | `SourcesViewModel` prefill + stale marking | Implemented |
| Unified task pipeline | Downloads → Task Center | `UnifiedTaskHistory.json` (outcomes only) | DownloadManager mirror, `FR.signPackageFile`, `InstallQueue` | Implemented |
| Per-app update rules | Updates → context menu → Update Rules | `VexSign.perAppUpdateRules` | `AppUpdateChecker.precomputeAllUpdates` | Implemented |
| Source health monitoring | App Store → Repositories → Source Health | `SourcePreferences` health records | `SourcesViewModel` refresh outcomes | Implemented |
| HTTPS-only repository transport | Settings → Security (HTTP opt-in) | `VexSign.sources.allowInsecureHTTP` | `SourceURLPolicy` (add + refresh) | Implemented |
| Encrypted backup & restore | Settings → Backup | `.vexbackup` (AES-GCM, PBKDF2 200k) | `BackupManager` + `BackupCrypto` | Implemented |
| First-run setup wizard | automatic on first launch | `VexSign.onboardingCompleted` | Certificate/source/IPA/import-method pages | Implemented |

## What "Needs device" means in practice

`Re-sign/reinstall` and the `Dynamic Island` controls depend on hardware and
OS behavior that a simulator cannot fully exercise (pairing, Live Activities
on notch hardware, installd timing). Both flows are wired through the same
`UnifiedTaskCenter` pipeline as the tested flows, so a device pass only needs
to confirm the last hop.

## Release-side status

- The six primary tabs (Files → Library → Home → App Store → Downloads →
  Settings) are **immutable by construction** — enforced by
  `TabBarPreferences` and covered by
  `MissingFeatureTests.testPrimaryTabsAreImmutableAndAlwaysVisible`.
- Synthetic compatibility tags (`v0.0.1` … `v0.0.18`, `v1.0.0`) run
  **validation-only** in the Release workflow and never publish; real
  releases still require `tag == MARKETING_VERSION` before and after the
  build. See `docs/RELEASING.md`.
