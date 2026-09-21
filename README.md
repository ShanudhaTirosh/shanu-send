# ShanuSend

<div align="center">

![ShanuSend Banner](app/src-tauri/icons/icon.png)

**Universal Cross-Platform File Sharing & Mobile Management Ecosystem**
*Native Support for LocalSend v2.1, Apple AirDrop, Google Quick Share, ShanuConnect P2P & ScrcpyGUI v4*

[![Build Windows & Desktop](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/ci.yml/badge.svg)](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/ci.yml)
[![Build Android APK](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/build_android.yml/badge.svg)](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/build_android.yml)
[![Flutter Build Matrix](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/flutter_build.yml/badge.svg)](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/flutter_build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[Features](#features) • [Architecture](#project-structure) • [Multi-Protocol Suite](#multi-protocol-suite) • [ScrcpyGUI v4](#scrcpygui-v4-integration) • [Quick Start](#quick-start) • [Downloads](#downloads) • [License](#license)

</div>

---

## ✨ Features

- **🌐 Universal Protocol Compatibility**:
  - **LocalSend v2.1**: Full wire compatibility with standard [LocalSend](https://localsend.org) clients across UDP multicast (`224.0.0.167:53317`) and HTTP endpoints.
  - **Apple AirDrop**: Native mDNS (`_airdrop._tcp.local.`), HTTPS (`/Ask`, `/Upload`), and BLE advertisement payload handling.
  - **Google Quick Share / Nearby Share**: mDNS (`_FC92._tcp.local.`), BLE GATT (`0xFE2C`), UKEY2 4-digit PIN verification, and streaming upload.
  - **ShanuConnect (App-to-App P2P)**: Dual-compatible with ShanuConnect & KDE Connect protocol v7 on port 1716.
  - **WebPortal / WebDrop**: Instant zero-install browser portal at `http://<IP>:53317/web` for file transfer & text snippets.
- **📱 ScrcpyGUI v4 Screen Mirroring Suite**:
  - **3 Capture Modes**: Screen Mirror, Camera Webcam Mode, and Desktop Virtual Display (`--new-display`).
  - **Advanced Controls**: Bitrate (1-100 Mbps), Resolution scaling, FPS caps (30/60/120), Video/Audio Codecs (Opus, AAC, FLAC, RAW), VSync toggle, and DPI UI scaling.
  - **Pro Input Modes**: OTG Keyboard/Mouse, HID Keyboard/Mouse simulation, and Pure HID (No Mirror) mode.
  - **Win32 Borderless Drag & Hotkeys**: Move borderless mirror window with `Ctrl+Alt+Shift+W` and recenter with `Ctrl+Alt+Shift+C`.
- **📱 Native Flutter Mobile Application (`flutter_app/`)**:
  - Subnet discovery scanner, zero-copy chunked transfer engine, live MB/s speed meter & ETA, ShanuConnect remote touchpad & media controller, and mobile WebDrop server.
- **🔒 End-to-End Security**:
  - Self-signed TLS certificates, fingerprint pinning, optional PIN verification, and blameless error handling.

---

## 📁 Project Structure

| Directory / File | Description |
| :--- | :--- |
| [`core/`](file:///c:/Users/tiros/OneDrive/Documents/coding/shanu-send/core) | **Rust Engine**: Multi-protocol server (LocalSend, AirDrop, Quick Share, ShanuConnect, WebDrop), mDNS responders, TLS crypto, and history store. |
| [`app/`](file:///c:/Users/tiros/OneDrive/Documents/coding/shanu-send/app) | **Desktop Client (Tauri 2 + React 19)**: Native desktop application with Scrcpy v4 integration, glassmorphism UI, 5 color themes, and English localization. |
| [`flutter_app/`](file:///c:/Users/tiros/OneDrive/Documents/coding/shanu-send/flutter_app) | **Mobile Client (Flutter)**: Native Android & iOS application with remote touchpad, media clicker, transfer manager, and WebDrop server. |
| [`.github/workflows/`](file:///c:/Users/tiros/.github/workflows) | **CI/CD Pipelines**: Automated multi-platform build matrix for Windows, Android APK, macOS, and Linux. |

---

## ⚡ Multi-Protocol Suite

All protocol services run simultaneously on app startup with zero manual configuration required:

```
                  ┌─────────────────────────────────────────┐
                  │          ShanuSend Unified Core         │
                  └────┬───────────┬───────────┬───────────┬┘
                       │           │           │           │
                       ▼           ▼           ▼           ▼
                 ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
                 │ LocalSend│ │ Apple    │ │ Google   │ │ Shanu    │
                 │   v2.1   │ │ AirDrop  │ │ QuickShare│ │ Connect  │
                 │ (:53317) │ │ (:8770)  │ │ (:5238)  │ │ (:1716)  │
                 └──────────┘ └──────────┘ └──────────┘ └──────────┘
```

---

## 🎥 ScrcpyGUI v4 Integration

Includes full parity with ScrcpyGUI v4 / v4.1:
- **Wireless ADB Pairing**: mDNS auto-discovery & native 6-digit PIN pairing modal for Android 11+.
- **Camera Torch & Zoom**: Remote camera torch toggle and zoom control (1.0x - 10.0x).
- **Flex Display**: Dynamically resizes virtual display to fit scrcpy window bounds.
- **Drag & Drop APK Pusher**: Drop `.apk` or any file directly onto the sidebar to push or install.

---

## 🚀 Quick Start

### 1. Tauri 2 Desktop Client (`app/`)

```bash
cd app
npm install
npm run dev      # Launch Web Dev Server (http://localhost:1420)
npx tauri dev    # Launch Native Tauri Desktop Window
npx tauri build  # Build Production MSI & Executable
```

### 2. Flutter Native Mobile Application (`flutter_app/`)

```bash
cd flutter_app
flutter pub get
flutter run
flutter build apk --release
```

### 3. Rust Engine Verification (`core/`)

```bash
cd app/src-tauri
cargo check
```

---

## 📦 Downloads & Releases

Pre-compiled production binaries and installers are generated automatically:
- **Windows**: `ShanuSend_2.5.3_x64-setup.exe` & `ShanuSend_2.5.3_x64_en-US.msi`
- **Android**: `app-release.apk`
- **macOS / Linux**: Built via CI matrix

Check the latest builds on the [GitHub Releases](https://github.com/ShanudhaTirosh/shanu-send/releases) page.

---

## 📄 License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for more information.
