<p align="center">
  <img src="repo-icon.png" width="112" alt="VexSign icon" />
</p>

<h1 align="center">VexSign</h1>

<p align="center">
  <a href="https://github.com/iamsmmh/VexSign/releases"><img src="https://img.shields.io/github/v/release/iamsmmh/VexSign?color=C96FAD&label=Release" alt="Release" /></a>
  <a href="https://github.com/iamsmmh/VexSign/releases"><img src="https://img.shields.io/github/downloads/iamsmmh/VexSign/total?color=black&label=Downloads" alt="Downloads" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-GPLv3-blue.svg" alt="License" /></a>
  <img src="https://img.shields.io/badge/Platform-iOS%2015%2B-black" alt="Platform" />
</p>

<p align="center">
  <b>Sign, tweak and install iOS apps entirely on-device — no computer required.</b><br>
  Based on <a href="https://github.com/claration/Feather">Feather</a> by <a href="https://github.com/claration">claration</a> (GPL-3.0).
</p>

<p align="center">
  <img src="Images/Image-light.png#gh-light-mode-only" width="760" alt="VexSign screenshot (light)" />
  <img src="Images/Image-dark.png#gh-dark-mode-only" width="760" alt="VexSign screenshot (dark)" />
</p>

## Features

Native SwiftUI interface with Liquid Glass support. Signs and installs IPAs with `.p12` / `.mobileprovision` via Zsign, with AltStore source support and certificate health monitoring.

On top of the Feather base:

| | |
| :--- | :--- |
| **Auto Cleanup** — import, sign, install and sweep in one pass | **IPA Explorer** — edit `Info.plist`, files and images inside any IPA |
| **Tweak injection** — `.dylib`, `.deb`, `.framework`, `.bundle`, `.appex` via ElleKit | **File transfer** — HTTP and WebDAV server, no cable |
| **Background downloads** — Live Activities and Dynamic Island progress | **Update All** — one-tap re-sign of every source update |
| **Batch signing** — queue multiple apps with per-app settings | **Backup & restore** — encrypted `.vexbackup` archives |
| **Anti-revoke** — DoH profile pinning Apple's verification hosts | **Automation** — scheduled update checks, cleanup and summaries |
| **Logs and file manager** — full console and document browser | **Game Mode** — pauses downloads and background work |

## Install

Download the latest `.ipa` from [Releases](https://github.com/iamsmmh/VexSign/releases), or add this repository to any AltStore-compatible signer:

```
https://raw.githubusercontent.com/iamsmmh/VexSign/main/app-repo.json
```

Installation runs over a local HTTPS server (`itms-services://`) or directly via AFC pairing.

## Build from Source

Requires Xcode 16+, iOS 15+ SDK, Swift 6.0.

```bash
git clone --recursive https://github.com/iamsmmh/VexSign.git
cd VexSign
make deps                    # fetch SSL certificates for the local server
open VexSign.xcworkspace     # set your team, or build unsigned with `make`
```

An optional self-hosted premium server (key validation, gated sources) is available in [`server/`](server/README.md), deployable via [`render.yaml`](render.yaml).

## Credits

| Project | Author | Role |
| ------- | ------ | ---- |
| [Feather](https://github.com/claration/Feather) | claration | Base — signing engine, storage layer, UI architecture, AltSourceKit, NimbleKit (GPL-3.0) |
| [Zsign](https://github.com/zhlynn/zsign) | zhlynn | On-device IPA signing (MIT) |
| [idevice](https://github.com/jkcoxson/idevice) | jkcoxson | AFC / `installd` backend for pairing installs (MIT) |
| [ElleKit](https://github.com/everythingappletech/ElleKit) | tealbathingsuit | Tweak injection (BSD-3) |
| [Vapor](https://github.com/vapor/vapor) | Vapor Team | Local HTTPS install server (MIT) |
| [Nuke](https://github.com/kean/Nuke) · [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) · [SWCompression](https://github.com/tsolomko/SWCompression) | kean · weichsel · tsolomko | Image loading and archive handling (MIT) |
| [backloop.dev](https://backloop.dev/) | — | Public-CA-signed SSL for localhost |

Maintained by [@iamsmmh](https://github.com/iamsmmh). See [LICENSE](LICENSE) and `license_plist.yml` for full attribution.

## License

GPL-3.0, matching the Feather base. © 2026 iamsmmh (VexSign additions) · © 2024 Samara / claration (Feather).

Releases are published only on [GitHub](https://github.com/iamsmmh/VexSign/releases). Sideloading may conflict with Apple Developer Program terms; use at your own risk. Not affiliated with Apple Inc.
