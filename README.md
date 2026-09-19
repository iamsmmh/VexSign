# VexSign

[![Release](https://img.shields.io/github/v/release/iamsmmh/VexSign?color=C96FAD&label=Release)](https://github.com/iamsmmh/VexSign/releases)
[![Downloads](https://img.shields.io/github/downloads/iamsmmh/VexSign/total?color=black&label=Downloads)](https://github.com/iamsmmh/VexSign/releases)
[![License](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-iOS%2015%2B-black)]()

**The most powerful on-device iOS signer. No PC. No revoke fear. Just sign and install.**

Built and maintained by **[@iamsmmh](https://github.com/iamsmmh)** · Based on **[Feather](https://github.com/claration/Feather) by [@claration](https://github.com/claration)** (GPL-3.0) — without Feather, VexSign wouldn't exist.

<p align="center">
  <img src="repo-icon.png" width="140" alt="VexSign Icon" />
  <br><br>
  <img src="Images/Image-light.png" width="780" alt="VexSign Screenshot" />
</p>

---

### ✨ Features

Everything Feather does — native SwiftUI + Liquid Glass UI, sign & install with `.p12`/`.mobileprovision` via Zsign, AltStore sources, certificate health checks — plus:

| | | |
| :--- | :--- | :--- |
| 🧹 **Auto Cleanup** — import → sign → install → clean, zero leftovers | 📂 **IPA Explorer** — edit `Info.plist`, files and images inside any IPA | 🔧 **Tweak Manager** — `.dylib`/`.deb`/`.framework`/`.bundle`/`.appex` injection (ElleKit) |
| 📡 **File Transfer** — HTTP + WebDAV server, no cable | ⬇️ **Smart Downloads** — Live Activities & Dynamic Island progress | 🔄 **Update All** — one-tap re-sign of every source update |
| 📦 **Batch Signing** — queue many apps at once | 💾 **Backup & Restore** — encrypted `.vexbackup` archives | 🛡️ **Anti-Revoke** — DoH profile pinning Apple's hosts |
| 📝 **Logs & File Manager** — full console + document browser | 🎮 **Game Mode** — pause everything while you play | 🤖 **Automation** — scheduled updates, cleanup, summaries |

---

### 📲 Install

Grab the latest `.ipa` from **[Releases](https://github.com/iamsmmh/VexSign/releases)**, or add the repo to your current signer:

```
https://raw.githubusercontent.com/iamsmmh/VexSign/main/app-repo.json
```

Installs work two ways: **Server** (local HTTPS + `itms-services://`, recommended) or **Pairing** (direct `installd` install via AFC, like ideviceinstaller but on-device).

---

### 🔨 Build from Source

Requirements: Xcode 16+, iOS 15+ SDK, Swift 6.0

```bash
git clone --recursive https://github.com/iamsmmh/VexSign.git
cd VexSign
make deps                    # fetches SSL certs for the local server
open VexSign.xcworkspace     # set your team, or build unsigned via `make`
```

The optional self-hosted **Premium server** (key validation, gated repos) lives in [`server/`](server/README.md) — deployable with one click via [`render.yaml`](render.yaml).

---

### 🙏 Credits

| Project | By | Role |
| ------- | -- | ---- |
| [Feather](https://github.com/claration/Feather) | @claration (Samara) | **Base** — signing engine, CoreData, UI architecture, AltSourceKit, NimbleKit (GPL-3.0) |
| [Zsign](https://github.com/zhlynn/zsign) | zhlynn | On-device IPA signing (MIT) |
| [idevice](https://github.com/jkcoxson/idevice) | jkcoxson | AFC/`installd` backend for Pairing install (MIT) |
| [ElleKit](https://github.com/everythingappletech/ElleKit) | tealbathingsuit | Tweak injection (BSD-3) |
| [Vapor](https://github.com/vapor/vapor) | Vapor Team | Local HTTPS install server (MIT) |
| [Nuke](https://github.com/kean/Nuke) · [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) · [SWCompression](https://github.com/tsolomko/SWCompression) · [LiveContainer](https://github.com/LiveContainer/LiveContainer) | kean · Weichsel · Tsolomko · LCTeam | Images, archives, sideload fixes |
| [backloop.dev](https://backloop.dev/) | — | Public-CA-signed SSL for localhost |

Full details in [LICENSE](LICENSE) and `license_plist.yml`. Thanks to every contributor, translator and tester — and to **you** for starring both repos. ⭐

---

### 📄 License & Disclaimer

**GPL-3.0** — same as Feather. © 2026 [@iamsmmh](https://github.com/iamsmmh) & VexSign Team (exclusive features) · © 2024 Samara / @claration (base). By contributing you agree to GPL-3.0.

Releases are published **only** on [GitHub](https://github.com/iamsmmh/VexSign/releases) — other sites may be malicious. Sideloading may violate Apple Developer Program terms; use at your own risk. Not affiliated with Apple Inc.

<p align="center"><b>Made with ❤️ by <a href="https://github.com/iamsmmh">@iamsmmh</a> · Based on <a href="https://github.com/claration/Feather">Feather by @claration</a></b></p>
