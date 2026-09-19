<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="icon.png">
  <img alt="VexSign" src="icon.png" width="180">
</picture>

# VexSign

### sign · tweak · install — entirely on device 📲

[![Release](https://img.shields.io/github/v/release/iamsmmh/VexSign?style=for-the-badge&color=C96FAD&label=Release)](https://github.com/iamsmmh/VexSign/releases)
[![Downloads](https://img.shields.io/github/downloads/iamsmmh/VexSign/total?style=for-the-badge&color=181717&label=Downloads)](https://github.com/iamsmmh/VexSign/releases)
[![Stars](https://img.shields.io/github/stars/iamsmmh/VexSign?style=for-the-badge&color=FFD700&label=Stars)](https://github.com/iamsmmh/VexSign/stargazers)
![iOS](https://img.shields.io/badge/iOS-16%2B-000000?style=for-the-badge&logo=apple&logoColor=white)
[![License](https://img.shields.io/badge/License-GPL--3.0-2f6feb?style=for-the-badge)](LICENSE)

**On-device iOS signer** built on [Feather](https://github.com/claration/Feather) (GPL-3.0).
Sign, tweak and install IPAs entirely on your iPhone or iPad — no Mac, no PC, no jailbreak.

[Features](#-features) ·
[Install](#-install) ·
[Build](#️-build-from-source) ·
[Premium](#-premium) ·
[Credits](#-credits) ·
[License](#-license)

</div>

---

## ✨ Features

Native SwiftUI app with **Liquid Glass** design on iOS 26. Signs and installs IPAs with `.p12` certificates and `.mobileprovision` profiles via Zsign, with full AltStore-source support and certificate health monitoring from the Feather base. On top of that VexSign adds:

|  |  |
| --- | --- |
| 🧹 **Auto Cleanup** | import → sign → install → sweep, zero leftovers |
| 📂 **IPA Explorer** | edit `Info.plist`, files and images inside any IPA |
| 🧩 **Tweak Injection** | `.dylib` `.deb` `.framework` `.bundle` `.appex` via ElleKit |
| 📡 **File Transfer** | HTTP + WebDAV server, no cable needed |
| ⬇️ **Live Downloads** | background transfers with Live Activities & Dynamic Island |
| 🔐 **App Lock** | Face ID / passcode lock when the app leaves the foreground |
| #️⃣ **SHA-256 Verify** | every download hashed to the log; verify any file against a published hash |
| 🔔 **Expiry Reminders** | notifications before your certificates expire |
| 🔋 **Download Conditions** | Wi-Fi-only and charge-only gates |
| 🔄 **Update All** | one-tap re-sign of every source update |
| 📦 **Batch Signing** | queue many apps with per-app settings |
| 💾 **Backup & Restore** | encrypted `.vexbackup` archives |
| 🛡️ **Anti-Revoke** | DoH profile pinning Apple's verification hosts |
| 🤖 **Automation** | scheduled updates, cleanup and summaries |
| 🗂️ **Logs & File Manager** | full console, built-in document browser, QuickLook preview |
| 🎮 **Game Mode** | pauses downloads and background work |

---

## 📦 Install

Grab the latest `.ipa` from [**Releases**](https://github.com/iamsmmh/VexSign/releases) 🚀, or add this source to any AltStore-compatible signer (SideStore, ESign, Scarlet, Feather, …):

```
https://raw.githubusercontent.com/iamsmmh/VexSign/main/app-repo.json
```

Installs use either the built-in local HTTPS server (`itms-services://`) or direct AFC pairing over USB 🔐

---

## 🛠️ Build from source

Requires **Xcode 16+** and the iOS 16+ SDK (Swift 6.0).

```bash
git clone --recursive https://github.com/iamsmmh/VexSign.git
cd VexSign
make deps                    # fetch SSL certificates for the local HTTPS server
open VexSign.xcworkspace     # set your team in Xcode, or build unsigned with `make`
```

> **Note:** `--recursive` is required — Zsign and IDeviceKitten are pulled in as Git submodules.

---

## 👑 Premium

Premium unlocks a private curated source with single-use, device-bound keys. Keys are issued through the official distribution channel; unknown, reused or disabled keys are rejected by design.

The premium backend lives in [`server/`](server/) and is committed here for transparency — anyone can audit exactly what the app talks to, what data is stored, and how keys are enforced.

---

## 🙏 Credits

VexSign stands on the shoulders of giants — thank you 💜

| Project | By | Role | License |
| --- | --- | --- | --- |
| 🪽 [Feather](https://github.com/claration/Feather) | [claration](https://github.com/claration) | Base signing engine, storage, UI architecture, AltSourceKit & NimbleKit | GPL-3.0 |
| ✍️ [Zsign](https://github.com/zhlynn/zsign) | [zhlynn](https://github.com/zhlynn) | On-device IPA signing | MIT |
| 🔌 [idevice](https://github.com/jkcoxson/idevice) | [jkcoxson](https://github.com/jkcoxson) | AFC / `installd` backend for pairing installs | MIT |
| 🧩 [ElleKit](https://github.com/everythingappletech/ElleKit) | [tealbathingsuit](https://github.com/everythingappletech/ElleKit) | Tweak injection | BSD-3 |
| 💨 [Vapor](https://github.com/vapor/vapor) | Vapor team | Local HTTPS install server | MIT |
| 🖼️ [Nuke](https://github.com/kean/Nuke) · [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) · [SWCompression](https://github.com/tsolomko/SWCompression) | kean · weichsel · tsolomko | Image loading and archive handling | MIT |
| 🔐 [backloop.dev](https://backloop.dev/) | — | Public-CA-signed SSL for the on-device localhost server | — |

---

## 📜 License

**GPL-3.0**, matching the Feather base ⚖️ — VexSign additions © 2026; Feather © 2024 Samara / claration. See [`LICENSE`](LICENSE) for the full text and [`LICENSE_ELLEKIT`](LICENSE_ELLEKIT) for ElleKit's BSD-3 notice.

<div align="center">

<sub>Sideloading may conflict with the Apple Developer Program terms; use at your own risk. VexSign is not affiliated with Apple Inc.</sub>

<br>

<sub>If VexSign helps you, a ⭐ on GitHub goes a long way.</sub>

</div>
