# FlareStore changelog parity

This document records the independent implementation audit for FlareStore's public changelog. It is a feature reference for VexSign, not copied FlareStore source.

Source checked: <https://flarestore.app/changelog/>

The complete public history was read from **v0.0.1 through v1.3.0**. The changelog page currently identifies v1.3.0 as the latest release (Build 22, 31 August 2026).

## Version audit

| FlareStore release | VexSign treatment |
| --- | --- |
| v0.0.1 | iOS foundation: tab shell, settings, certificates, AltStore sources, background refresh, downloads, IPA import, Live Activities. Existing VexSign foundations reviewed. |
| v0.0.2 | IPA signing, HTTPS server, app search/news, icon customization, certificate import/password/export, IPA extraction and app details. Existing signing, Web Manager, search, icon and IPA workflows reviewed. |
| v0.0.3 | Apple-platform detection, home data, app import, editing history and onboarding. iOS-compatible portions are present in VexSign. |
| v0.0.4 | Peel gestures, certificate defaults, IPA/app-icon extraction, app detail and extension views, URL-scheme editing. iOS workflows are represented by swipe/context actions, certificate defaults, IPA Explorer and signing editors. |
| v0.0.5 | IPA signing, HTTPS server updates, install flow, search, news, theming and icon editing. Existing signer, Web Manager, repository UI, Theme and customization workflows reviewed. |
| v0.0.6 | Bulk iOS signing, visionOS UI, certificate badges and previews. iOS bulk signing and certificate dashboard are present; visionOS-only previews are excluded. |
| v0.0.7 | Watch/visionOS/Mac previews, widgets, Dynamic Island signing status, Debian support and home improvements. iOS widgets, Dynamic Island controls, `.deb` handling and Home improvements are present; other-platform previews are excluded. |
| v0.0.8 | Apple TV signing and platform parity. Apple TV-only work is excluded from this iOS/iPadOS scope. |
| v0.0.9 | Remote signing/installing, certificate revocation checks, multi-select and Apple TV support. iOS cloud signing, local install diagnostics, OCSP inspector and multi-select are present; Apple TV work is excluded. |
| v0.0.10 | Remote signing, Apple TV, bulk signing and auto-install fixes. Existing cloud signing, batch jobs and install queue reviewed. |
| v0.0.11 | Certificate/AppID inspection, enterprise and No-PPQ tags, Watch/visionOS/Mac previews and IPA opening. iOS certificate inspection and AppID/entitlement inspection are present; other-platform previews are excluded. |
| v0.0.12 | Device and pairing improvements, storage warnings, iMessage sharing, bulk importing and tweak groups. iOS pairing, storage, sharing, bulk importing and tweak folders are present. |
| v0.0.13 | Repository-specific app browsing fix. Repository loading and source-specific browsing are present. |
| v0.0.14 | Apple TV signing completion and visionOS fixes. Excluded as platform-specific. |
| v0.0.15 | Repository swipe delete, ElleKit, AppID copy, search/count fixes, device updates, storage, iMessage and bulk import. Applicable VexSign equivalents are present, including ElleKit injection, AppID copy, source actions, storage and import. |
| v0.0.16 | Remote installing/signing, revoke checking, fast signing, multi-delete and Apple TV install UI. iOS remote/local installation, certificate checks, bulk jobs and multi-delete are present; Apple TV UI is excluded. |
| v0.0.17 | Apple TV signing/installing and Mac parity. Excluded from this iOS/iPadOS scope. |
| v0.0.18 | Repository model/refactor, markdown content, date sorting, WebDAV/HTTP server, Luna theme, hex/string browser, IPA file browser, batch/re-sign progress, custom entitlements, tweak options, repository sorting, `.deb`/Asset.car-era IPA editing and auto-sign flows. VexSign now includes Markdown rendering, Luna visual theme, binary hex/string browsing, IPA Explorer, custom entitlements, tweak options, WebDAV/HTTP, `.deb`, repository sorting and automatic signing foundations. Asset.car editing remains represented as safe file replacement/browser editing rather than a proprietary asset compiler. |
| v1.0.0 | Apple TV/visionOS updates and iOS library fixes. Applicable iOS library work is present; platform-only work is excluded. |
| v1.1.0 | Self-update, installed-app updates, automatic updates, re-sign/reinstall, favorites, update matching, install notifications, bulk install, App Store tracking, IPSW browser, startup tab selection, forced signing and download/install UX. These are present in VexSign's update, automation, certificate, firmware, tab, install and notification foundations. |
| v1.2.0 | Additional cross-platform feature parity. iOS/iPadOS-compatible portions were reviewed and are represented in VexSign; Mac/TV/Watch/visionOS-only portions are excluded. |
| v1.3.0 | Full File Manager, archive/IPA browser, backup/transfer, SDK spoofing, Quick Sign as Duplicate, Tweak Library, Dylib Browser, verified/trusted repositories, source priority, tweak-repository links, JIT/pairing, location simulation, guides, diagnostics, certificate inspection, performance and reliability fixes. Applicable gaps are implemented in VexSign independently; see the feature status below. |

## Current iOS/iPadOS implementation status

### Ported or independently represented

- Self-update and installed-app update matching.
- Per-app automatic updates, favorites and certificate selection.
- Re-sign/reinstall, bulk signing/installing and install progress.
- App Store version tracking and IPSW browsing.
- File Manager, IPA Explorer, archive browsing, compression and safe replacement.
- Backup/restore and transfer foundations.
- Build SDK/Mach-O patching, compatibility opt-out clearing, file sharing, minimum OS removal and architecture thinning wired into the real `Options` signing pipeline.
- Quick Sign/Clone as Duplicate with a separate bundle ID.
- Searchable Tweak Library, tweak folders, multi-component tweaks, injection options and tweak repository JSON import.
- Dylib Browser and binary hex/string browser.
- Source priority ordering with deterministic duplicate selection.
- User-controlled trusted repository badges; the badge is intentionally honest and does not claim cryptographic publisher verification.
- Tweak repository URL/deep-link import via `vexsign://tweak-repository/...`.
- HTTPS Web Manager and WebDAV.
- JIT/pairing, location simulator and Live Activity foundations.
- In-app iOS/iPadOS guides for signing, sources, tweaks, JIT/location and troubleshooting.
- Exportable signing/install logs and certificate inspection, including certificate-vs-profile expiry.
- Dynamic Island download controls, strict app hiding/privacy behavior, widgets and Live Activities.
- Original VexSign Luna visual theme and Flare-inspired touch treatment.
- Optional Flare visual theme with dark glass surfaces, violet/cyan web accents, native font sizing, animated highlight motion and spring press feedback. Base/Ksign-style surfaces and Luna remain selectable.
- Screenshot-matched Home dashboard presentation: dark magenta grid, repository/certificate/app metrics, update card, IPA/TIPA drag-and-drop import, direct URL downloads, Quick Sign, certificate management, repository creation and IPSW Browser actions.

### Companion platforms (mirrors, not signers)

`VexSignTV` (tvOS 17), `VexSignVision` (visionOS 2) and `VexSignWatch` (watchOS 10, plus a
complication widget) exist as **companion mirrors**: they show certificate state, library and
update counts, and the watch can trigger four passes on the phone. They do not sideload, sign or
pair devices — no certificate store, no IPA storage and no `installd` exists on those platforms,
so FlareStore's Apple TV on-device sideloading remains out of scope. See
[PLATFORMS.md](PLATFORMS.md).

### Web tools parity

FlareStore's browser suite is covered by the self-hosted backend under `/tools`:

| FlareStore web tool | VexSign |
| --- | --- |
| Web signer | **Signer Console** (`/tools/signer`) — relays uploads to the phone's Web Manager and streams the signed IPA back, with a queue. Signing still happens on-device. |
| Repository creator | **Repository Creator** (`/tools/repo-creator`) |
| Repository decoder | **Repository Decoder** (`/tools/repo-decoder`) — normalises AltStore/SideStore/flat/apps.json/appdata-XML and re-exports |
| App installer | **App Installer** (`/tools/app-installer`) — OTA manifest, install link and a reachability probe |
| Certificate status checker | **Certificate Status Checker** (`/tools/cert-check`) |
| UDID grabber | **UDID Grabber** (`/tools/udid`) |

See [WEBTOOLS.md](WEBTOOLS.md). What is *not* covered, and cannot be: browser-side signing without
the app (there is no Zsign in the Python backend — the signer console drives the phone), 365-day
certificates and unlimited App IDs (Apple's limits, not a code gap).

### Deliberately excluded

Mac-only device manager, Mac remote signing, Discord presence, Apple TV on-device
sideloading/pairing UI, visionOS immersive-only previews, and platform-specific build tooling
without an iOS/iPadOS foundation.

No FlareStore code was copied. VexSign uses its own models, persistence, signing hooks and SwiftUI views.

## VexSign release tags

The requested FlareStore-style compatibility tag range has been added to the VexSign repository:

- `v0.0.1` through `v0.0.18`
- `v1.0.0`
- The repository's pre-existing `v1.0` tag was left untouched.

These tags are explicitly annotated as **synthetic parity milestones** and point to the parity implementation commit. They are not claims that VexSign historically shipped those exact builds. The actual VexSign development history remains in the commit graph.

For future real releases, VexSign's workflow still uses:

```text
v<MARKETING_VERSION>
```

For example, a VexSign `MARKETING_VERSION` of `1.3.0` should be released as `v1.3.0`. The compatibility tags are for the requested versioned parity presentation; real releases should use a version bump and a tag on the corresponding development commit.
