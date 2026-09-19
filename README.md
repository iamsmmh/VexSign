<div align="center">

<img src="icon.png" width="180" alt="VexSign logo" />

# VexSign

### sign · tweak · install — entirely on device 📲

[![Release](https://img.shields.io/github/v/release/iamsmmh/VexSign?style=for-the-badge&color=C96FAD&label=RELEASE)](https://github.com/iamsmmh/VexSign/releases)
[![Downloads](https://img.shields.io/github/downloads/iamsmmh/VexSign/total?style=for-the-badge&color=181717&label=DOWNLOADS)](https://github.com/iamsmmh/VexSign/releases)
[![Stars](https://img.shields.io/github/stars/iamsmmh/VexSign?style=for-the-badge&color=FFD700&label=STARS)](https://github.com/iamsmmh/VexSign/stargazers)
![iOS 15+](https://img.shields.io/badge/iOS-15%2B-000000?style=for-the-badge&logo=apple&logoColor=white)
[![License](https://img.shields.io/badge/LICENSE-GPL--3.0-2f6feb?style=for-the-badge)](LICENSE)

**On-device iOS signer** built on [Feather](https://github.com/claration/Feather) by [claration](https://github.com/claration) (GPL-3.0) —
sign, tweak and install IPAs without a computer.

[Features](#-features) • [Install](#-install) • [Build](#️-build-from-source) • [Credits](#-credits) • [License](#-license)

</div>

---

## ✨ Features

Native SwiftUI with **Liquid Glass** support 💎 — signs and installs with `.p12` / `.mobileprovision` via Zsign, AltStore sources and certificate health monitoring included from the Feather base. On top of it, VexSign adds:

| | |
|---|---|
| 🧹 **Auto Cleanup** | import → sign → install → sweep, zero leftovers |
| 📂 **IPA Explorer** | edit `Info.plist`, files & images inside any IPA |
| 🧩 **Tweak Injection** | `.dylib` `.deb` `.framework` `.bundle` `.appex` via ElleKit |
| 📡 **File Transfer** | HTTP + WebDAV server, no cable needed |
| ⬇️ **Live Downloads** | background DLs with Live Activities & Dynamic Island |
| 🔄 **Update All** | one-tap re-sign of every source update |
| 📦 **Batch Signing** | queue many apps with per-app settings |
| 💾 **Backup & Restore** | encrypted `.vexbackup` archives |
| 🛡️ **Anti-Revoke** | DoH profile pinning Apple's verification hosts |
| 🤖 **Automation** | scheduled updates, cleanup & summaries |
| 🗂️ **Logs + File Manager** | full console & document browser |
| 🎮 **Game Mode** | pauses downloads & background work |

---

## 📦 Install

Grab the latest `.ipa` from **[Releases](https://github.com/iamsmmh/VexSign/releases)** 🚀, or add this source to any AltStore-compatible signer:

```
https://raw.githubusercontent.com/iamsmmh/VexSign/main/app-repo.json
```

Installs run over a local HTTPS server (`itms-services://`) or directly via AFC pairing 🔐

---

## 🛠️ Build from Source

Requires **Xcode 16+**, iOS 15+ SDK, Swift 6.0.

```bash
git clone --recursive https://github.com/iamsmmh/VexSign.git
cd VexSign
make deps                    # fetch SSL certificates for the local server
open VexSign.xcworkspace     # set your team, or build unsigned with `make`
```

<sub>👑 Premium unlocks a private curated source with a single-use, device-bound key — get one from <a href="https://t.me/iamSMMH"><b>@iamSMMH</b></a> on Telegram.</sub>

---

## 🙏 Credits

VexSign stands on the shoulders of giants — huge thanks 💜

| Project | Author | Role | License |
|---|---|---|---|
| 🪽 [Feather](https://github.com/claration/Feather) | [claration](https://github.com/claration) | base: signing engine, storage layer, UI architecture, AltSourceKit & NimbleKit | GPL-3.0 |
| ✍️ [Zsign](https://github.com/zhlynn/zsign) | [zhlynn](https://github.com/zhlynn) | on-device IPA signing | MIT |
| 🔌 [idevice](https://github.com/jkcoxson/idevice) | [jkcoxson](https://github.com/jkcoxson) | AFC / `installd` backend for pairing installs | MIT |
| 🧩 [ElleKit](https://github.com/everythingappletech/ElleKit) | [tealbathingsuit](https://github.com/everythingappletech/ElleKit) | tweak injection | BSD-3 |
| 💨 [Vapor](https://github.com/vapor/vapor) | Vapor Team | local HTTPS install server | MIT |
| 🖼️ [Nuke](https://github.com/kean/Nuke) · [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) · [SWCompression](https://github.com/tsolomko/SWCompression) | kean · weichsel · tsolomko | image loading & archive handling | MIT |
| 🔐 [backloop.dev](https://backloop.dev/) | — | public-CA-signed SSL for localhost | — |

---

## 📜 License

**GPL-3.0**, matching the Feather base ⚖️ — © 2026 iamsmmh (VexSign additions) · © 2024 Samara / claration (Feather).

<div align="center">

🚀 Releases are published only on **[GitHub](https://github.com/iamsmmh/VexSign/releases)**.

<sub>Sideloading may conflict with Apple Developer Program terms; use at your own risk. Not affiliated with Apple Inc.</sub>

<sub>Maintained with 💜 by [@iamsmmh](https://github.com/iamsmmh)</sub>

⭐ **If VexSign helped you, consider leaving a star — it helps a lot!** ⭐

</div>
