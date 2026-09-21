# ShanuSend

<div align="center">

![ShanuSend Banner](logo.png)

**Universal Cross-Platform File Sharing, Phone Link & Screen Mirroring Ecosystem**
*Native Support for LocalSend v2.1, Apple AirDrop, Google Quick Share, ShanuConnect P2P & ScrcpyGUI Suite*

[![Build Windows & Desktop](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/ci.yml/badge.svg)](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/ci.yml)
[![Build Android APK](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/build_android.yml/badge.svg)](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/build_android.yml)
[![Flutter Build Matrix](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/flutter_build.yml/badge.svg)](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/flutter_build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[Features](#features) • [Architecture](#project-structure) • [Multi-Protocol Suite](#multi-protocol-suite) • [ScrcpyGUI Suite](#scrcpygui-suite-integration) • [Quick Start](#quick-start) • [Downloads](#downloads) • [License](#license)

</div>

---

## ✨ Features

- **🌐 Universal Protocol Compatibility**:
  - **LocalSend v2.1**: Wire-level compatibility with standard [LocalSend](https://localsend.org) clients across UDP multicast (`224.0.0.167:53317`) and HTTP endpoints.
  - **Apple AirDrop**: Native mDNS (`_airdrop._tcp.local.`), HTTPS (`/Ask`, `/Upload`), and BLE advertisement payload handling.
  - **Google Quick Share / Nearby Share**: mDNS (`_FC92._tcp.local.`), BLE GATT (`0xFE2C`), UKEY2 4-digit PIN verification, and streaming upload.
  - **ShanuConnect (App-to-App P2P)**: Dual-compatible with ShanuConnect & KDE Connect protocol v7 on port 1716 with 6-digit SAS Security PIN pairing.
  - **Unified WebDrop Portal**: Single-port HTTP server (`UnifiedHttpServer`) hosting zero-install browser file transfer portal at `http://<IP>:53317` & `http://<IP>:53317/webdrop` alongside LocalSend v2.1 API endpoints.
- **📱 Phone Link & Workstation Host (`desktop_phone_link_view.dart`)**:
  - **Zero Mock / Pure Live Event Stream**: Real-time packet listeners (`shanuconnect.notifications`, `shanuconnect.sms`, `shanuconnect.battery`, `shanuconnect.mpris`).
  - **Synced Phone Notifications**: Live phone notification stream with inline reply support.
  - **SMS Manager & Call Controls**: Read and send SMS messages via paired phone; incoming call alerts with answer/reject actions.
  - **Phone Status Cards**: Live battery % and charging indicator, Wi-Fi status, and remote phone ringer trigger (`Find Phone`).
  - **Bidirectional Clipboard Auto-Sync**: Text copied on phone or desktop instantly syncs across devices.
- **📱 ScrcpyGUI Screen Mirroring Suite (`scrcpy_gui_view.dart`)**:
  - **ADB Device Picker**: Wireless and USB ADB device discovery & selector.
  - **Resolution Presets**: 720p, 1080p, and Original source resolutions.
  - **Stream Tuning**: Bitrate controls (2 - 16 Mbps), FPS caps (30/60 FPS), and Video Codecs (H.264, H.265, AV1).
  - **Display & Recording Toggles**: Stay Awake toggle, Turn Screen Off toggle, and MP4 Screen Recording capability.
- **📱 Mobile Remote Controller & Integrated Device Hub (`shanu_connect_view.dart`)**:
  - Continuous LAN discovery stream, top device switcher dropdown, 6-digit SAS Security PIN authentication modal prompt, multi-touch trackpad (gestures, tap-to-click, scroll), MPRIS media remote, presenter clicker, clipboard sync, and system commands.
- **🔒 End-to-End Security**:
  - Self-signed TLS certificates, fingerprint pinning, 6-digit SAS PIN confirmation, and blameless error handling.

---

## 📁 Project Structure

| Directory / File | Description |
| :--- | :--- |
| [`core/`](file:///c:/Users/tiros/OneDrive/Documents/coding/shanu-send/core) | **Rust Engine**: Multi-protocol server (LocalSend, AirDrop, Quick Share, ShanuConnect, WebDrop), mDNS responders, TLS crypto, and history store. |
| [`app/`](file:///c:/Users/tiros/OneDrive/Documents/coding/shanu-send/app) | **Desktop Web Client (Tauri 2 + React 19)**: Native desktop interface with glassmorphism UI, 5 color themes, and English localization. |
| [`flutter_app/`](file:///c:/Users/tiros/OneDrive/Documents/coding/shanu-send/flutter_app) | **Native Multi-Platform Application (Flutter)**: Universal Windows, Android, iOS, macOS, and Linux app featuring `UnifiedHttpServer`, Phone Link hub, Scrcpy GUI suite, and Remote Controller. |
| [`.github/workflows/`](file:///c:/Users/tiros/.github/workflows) | **CI/CD Pipelines**: Automated multi-platform build matrix for Windows, Android APK, macOS, and Linux. |

---

## ⚡ Multi-Protocol Suite

All protocol services run simultaneously on app startup with zero manual configuration required:

```
                  ┌─────────────────────────────────────────┐
                  │         ShanuSend Unified Engine        │
                  └────┬───────────┬───────────┬───────────┬┘
                       │           │           │           │
                       ▼           ▼           ▼           ▼
                 ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
                 │ LocalSend│ │ Apple    │ │ Google   │ │ Shanu    │
                 │ v2.1 &   │ │ AirDrop  │ │ QuickShare│ │ Connect  │
                 │ WebDrop  │ │ (:8770)  │ │ (:5238)  │ │ (:1716)  │
                 │ (:53317) │ └──────────┘ └──────────┘ └──────────┘
                 └──────────┘
```

---

## 🎥 ScrcpyGUI Suite Integration

Includes full parity with ScrcpyGUI controls:
- **Wireless ADB Pairing**: Auto-discovery & native 6-digit PIN pairing modal.
- **Resolution & Stream Customization**: Switch between 720p, 1080p, and native resolutions; adjust FPS (30/60) and bitrates (2-16 Mbps).
- **Control Toggles**: Stay Awake during mirroring, turn phone screen off, and record stream to MP4.

---

## 🚀 Quick Start

### 1. Flutter Multi-Platform App (`flutter_app/`)

```bash
cd flutter_app
flutter pub get
flutter run                       # Launch on desktop/mobile
flutter build windows             # Build Windows Native Release Executable (.exe)
flutter build apk --release       # Build Android APK
```

### 2. Tauri 2 Desktop Client (`app/`)

```bash
cd app
npm install
npm run dev      # Launch Web Dev Server (http://localhost:1420)
npx tauri dev    # Launch Native Tauri Desktop Window
npx tauri build  # Build Production MSI & Executable
```

### 3. Rust Engine Verification (`core/`)

```bash
cd app/src-tauri
cargo check
```

---

## 📦 Downloads & Releases

Pre-compiled production binaries and installers are generated automatically:
- **Windows**: `shanu_send_flutter.exe` & `ShanuSend_2.5.4_x64-setup.exe`
- **Android**: `app-release.apk`
- **macOS / Linux**: Built via CI matrix

Check the latest builds on the [GitHub Releases](https://github.com/ShanudhaTirosh/shanu-send/releases) page.

---

## 📄 License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for more information.

