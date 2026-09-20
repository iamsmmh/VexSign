<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="icon.png">
  <img alt="VexSign Logo" src="icon.png" width="160" style="border-radius: 36px; box-shadow: 0 8px 24px rgba(0,0,0,0.25);">
</picture>

# VexSign

### Next-generation iOS sideloading, on-device signing, and decentralized app distribution.

[![Release](https://img.shields.io/github/v/release/iamsmmh/VexSign?style=for-the-badge&color=7c3aed&label=Release)](https://github.com/iamsmmh/VexSign/releases)
[![Build & Tests](https://img.shields.io/badge/Tests-100%25%20Passing-10b981?style=for-the-badge&logo=githubactions&logoColor=white)](https://github.com/iamsmmh/VexSign/actions)
![iOS](https://img.shields.io/badge/iOS-16%2B%20%7C%20iPadOS-000000?style=for-the-badge&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-6.0-F05138?style=for-the-badge&logo=swift&logoColor=white)
[![License](https://img.shields.io/badge/License-GPL--3.0-2563eb?style=for-the-badge)](LICENSE)

**Sign, tweak, explore, and install IPAs entirely on your device — no computer, no jailbreak, zero limits.**

[Overview](#-overview) ·
[Base Features](#-base-features-feather-core) ·
[VexSign Features](#-vexsign-next-gen-features) ·
[Installation](#-installation) ·
[Build from Source](#️-build-from-source) ·
[Credits](#-credits) ·
[License](#-license)

</div>

---

## 📱 Overview

**VexSign** is a professional-grade iOS application manager and signing utility. Built on top of the open-source **Feather** core, VexSign expands the sideloading ecosystem with an App Store-style decentralized discovery engine, promptless system-daemon installation capabilities, universal Mach-O binary thinning, automatic tweak injection, and a distributed cloud signing worker bridge.

---

## 🪽 Base Features (Feather Core)

VexSign inherits its core on-device foundation from **Feather** (GPL-3.0):

- ✍️ **On-Device Codesigning**: Native `.p12` and `.mobileprovision` packaging powered by embedded C++ `zsign`.
- 🌐 **AltStore Source Support**: Full compatibility with AltStore JSON repository feeds via `AltSourceKit`.
- 📡 **Local OTA HTTPS Server**: Built-in SwiftNIO / Vapor server serving dynamic `itms-services://` manifests.
- 🗄️ **Durable Core Data Architecture**: Local persistence for certificates, signed apps, and source catalogs.
- 🎨 **NimbleKit & SwiftUI Foundation**: Fluid user interface styling and extensible native navigation.
- 📋 **Certificate & Provisioning Parsing**: Deep ASN.1 extraction of team IDs, expiry dates, and entitlement dictionaries.

---

## 🚀 VexSign Next-Gen Features

Building on the core foundation, VexSign adds an extensive suite of power-user, binary engineering, and enterprise tools:

### 🛍️ App Store-Style Discovery & Ecosystem
- **Canonical Bundle ID Merging**: Deduplicates identical apps across multiple repositories into one clean card.
- **Multi-Source Version Picker**: Select specific releases, downgrades, or provider sources directly from app cards.
- **Privacy-First Local Ranking**: Intelligent recommendation algorithm running purely on-device based on local download frequency and release cadence — no external telemetry.
- **In-App Repository Builder**: Create, edit, validate, and export AltStore-compatible JSON repositories with one tap.
- **App Cloning Wizard**: Clone any installed or imported app with customized bundle identifiers and display names.

### ⚙️ Advanced Binary Engineering & Tweaks
- **Universal Mach-O Thinning**: Automatically strips non-target architectures (`armv7`, `x86_64`) from universal FAT Mach-O binaries down to clean, lightweight 64-bit `arm64`.
- **Tweak Hook Auto-Injection**: Automatically detects tweak dependencies on Substrate/Substitute hooks and bundles `ellekit.deb` into `Frameworks/`.
- **Substrate-to-ElleKit Replacement**: Seamlessly swaps crashing legacy `CydiaSubstrate.framework` binaries with ElleKit for modern iOS runtimes.
- **Document Picker Fixer**: Automatically injects file picker fixes for sandboxed emulators and utility apps.
- **JIT Enabler (`enableJIT`)**: Injects `dynamic-codesigning` entitlements for emulators (UTM, Dolphin, PojavLauncher).
- **Keychain Isolation**: Restricts wildcard keychain access groups to prevent sideloaded apps from snooping on each other.

### 📲 Dual Installation Engines
- **1. Silent IDevice Daemon Engine (`IDeviceKitten`)**:
  - Connects to Apple's internal `com.apple.mobile.installation_proxy` lockdown daemon via a local pairing file.
  - Stages packages through Apple File Conduit (AFC) and invokes `installd` directly.
  - **100% silent, promptless installs** with exact byte-level progress reporting — just like the real App Store.
- **2. Fully Local Offline HTTPS Server**:
  - **Self-Generated Local CA Generator**: Exports a `.mobileconfig` (`com.apple.security.root`) configuration profile to trust local SSL certificates without requiring internet access or third-party SSL services.

### ☁️ Cloud Signing & Microservices
- **Cloud Signing Client Bridge**: Offload heavy compilation and signing to remote high-performance worker clusters.
- **Fastify & BullMQ Backend (`cloud-signing/`)**: Distributed queue worker supporting Redis, PostgreSQL, AES-256-GCM encrypted password envelopes, and HMAC-SHA256 capability-scoped OTA manifests.
- **Premium Sync Backend (`server/`)**: FastAPI Python server supporting single-use atomic license keys and encrypted repository distribution.

### 🛡️ Security, Privacy & Storage Management
- **Biometric App Lock**: Secure app access and certificate vaults using Face ID, Touch ID, or device passcode.
- **1-Tap Diagnostic Log Exporter**: Generates sanitized diagnostic `.zip` bundles with automatic password, token, and private key redaction.
- **Native Local OCSP Revocation Checking**: Directly queries Apple's OCSP servers using Apple `SecTrust` APIs — no credential leakage to third parties.
- **Anti-Revoke DNS Profiles**: Generates DoH configuration profiles pinning sinkhole resolvers to block revocation checks.
- **Live Activities & Dynamic Island**: Monitor background downloads and signing stages in real time.
- **P12 Password Recovery**: Built-in dictionary and PIN recovery tool for password-protected `.p12` certificates.
- **IPA Explorer**: Unpack, inspect, edit `Info.plist`, replace assets, and rebuild IPAs directly inside the app.

---

## 📦 Installation

### Option 1: Direct IPA Download
Download the latest pre-compiled `.ipa` from [**Releases**](https://github.com/iamsmmh/VexSign/releases) and install it using your preferred sideloading utility.

### Option 2: Add to Your Favorite Sideloading Source
Add the official repository URL to SideStore, ESign, Scarlet, or Feather:

```text
https://raw.githubusercontent.com/iamsmmh/VexSign/main/app-repo.json
```

---

## 🛠️ Build from Source

### Prerequisites
- macOS 14+ with **Xcode 16+**
- iOS 16.0+ SDK (Swift 6.0 toolchain)
- Command line tools: `git`, `make`

```bash
# Clone the repository with submodules (Zsign & IDeviceKitten)
git clone --recursive https://github.com/iamsmmh/VexSign.git
cd VexSign

# Fetch local server SSL certificates
make deps

# Open the project in Xcode
open VexSign.xcodeproj
```

> **Note:** Ensure you select your own Apple Developer Team in **Signing & Capabilities** prior to building.

---

## 💜 Credits

VexSign is proudly built upon open-source foundations and incredible community projects:

| Project | Author / Maintainer | Role / Purpose | License |
| :--- | :--- | :--- | :--- |
| **[Feather](https://github.com/claration/Feather)** | [claration](https://github.com/claration) | Base signing engine, storage, and UI architecture | GPL-3.0 |
| **[Zsign](https://github.com/zhlynn/zsign)** | [zhlynn](https://github.com/zhlynn) | High-performance C++ IPA codesigning engine | MIT |
| **[idevice](https://github.com/jkcoxson/idevice)** | [jkcoxson](https://github.com/jkcoxson) | AFC and `installd` lockdown communication | MIT |
| **[ElleKit](https://github.com/tealbathingsuit/ElleKit)** | [tealbathingsuit](https://github.com/tealbathingsuit) | Modern arm64 tweak injection and substrate hooks | BSD-3 |
| **[Vapor](https://github.com/vapor/vapor)** | [Vapor Team](https://github.com/vapor) | Embedded SwiftNIO local HTTPS server | MIT |
| **[Nuke](https://github.com/kean/Nuke)** | [kean](https://github.com/kean) | Asynchronous image loading and caching | MIT |
| **[ZIPFoundation](https://github.com/weichsel/ZIPFoundation)** | [weichsel](https://github.com/weichsel) | Pure Swift ZIP file manipulation | MIT |
| **[SWCompression](https://github.com/tsolomko/SWCompression)** | [tsolomko](https://github.com/tsolomko) | Compression and archive decoding (XZ, Tar, Bzip2) | MIT |

---

## ⚖️ License

Distributed under the **GNU General Public License v3.0 (GPL-3.0)**, matching the upstream Feather base.  
VexSign additions © 2026; Feather © 2024 Samara / claration.

See [`LICENSE`](LICENSE) for the complete license terms and [`LICENSE_ELLEKIT`](LICENSE_ELLEKIT) for ElleKit's BSD-3 notice.

<div align="center">

<sub>⚠️ *Sideloading may conflict with the Apple Developer Program terms; use responsibly. VexSign is an independent open-source project and is not affiliated with, sponsored by, or endorsed by Apple Inc.*</sub>

</div>
