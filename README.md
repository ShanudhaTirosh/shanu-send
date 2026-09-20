# ShanuSend

<div align="center">

![ShanuSend Banner](app/src-tauri/icons/icon.png)

**A high-performance, cross-platform file sharing ecosystem compatible with LocalSend v2.1.**

[![CI](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/ci.yml/badge.svg)](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/ci.yml)
[![Build Android APK](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/build_android.yml/badge.svg)](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/build_android.yml)
[![Flutter Build Matrix](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/flutter_build.yml/badge.svg)](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/flutter_build.yml)
[![Release](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/release.yml/badge.svg)](https://github.com/ShanudhaTirosh/shanu-send/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[Features](#features) • [Architecture](#project-structure) • [Quick Start](#quick-start) • [Downloads](#downloads) • [License](#license)

</div>

---

## ✨ Features

- **🌐 Cross-Platform Compatibility**: Full support for Android (APK), Windows (EXE/MSI), macOS (DMG - Apple Silicon & Intel), and Linux (.deb/.AppImage/.rpm).
- **⚡ Zero-Copy Chunked Streaming**: Ultra-fast peer-to-peer file transfer engine built with Rust and Dart.
- **🔄 LocalSend v2.1 Protocol Integration**: Full wire compatibility with standard [LocalSend](https://localsend.org) clients across UDP multicast (`224.0.0.167:53317`) and HTTP transfer endpoints.
- **📱 Native Flutter Application (`flutter_app/`)**: Responsive UI with dark glassmorphism styling, clean SVG vector graphics (no emojis), and zero-dependency native file picking.
- **🖥️ Desktop Tauri 2 App (`app/`)**: Ultra-lightweight desktop client powered by React, TypeScript, and Rust.
- **💧 Embedded WebDrop AirDrop Portal**: Allows any device with a web browser on the local network to send and receive files without installing any app.
- **🔒 End-to-End Security**: Self-signed TLS certificates, fingerprint pinning, and optional PIN verification for secure pairing.

---

## 📁 Project Structure

| Directory / File | Description |
| :--- | :--- |
| [`core/`](file:///c:/Users/tiros/OneDrive/Documents/coding/shanu-send/core) | **Rust Engine**: LocalSend v2.1 UDP multicast discovery, HTTP/HTTPS transfer server, TLS fingerprint verification, and history management. |
| [`flutter_app/`](file:///c:/Users/tiros/OneDrive/Documents/coding/shanu-send/flutter_app) | **Flutter Client**: Cross-platform Dart application targeting Android, Windows, macOS, and Linux. |
| [`app/`](file:///c:/Users/tiros/OneDrive/Documents/coding/shanu-send/app) | **Tauri 2 + React Desktop App**: Web UI frontend and desktop wrapper. |
| [`.github/workflows/`](file:///c:/Users/tiros/OneDrive/Documents/coding/shanu-send/.github/workflows) | **CI/CD Pipelines**: Automated multi-platform build matrix, Android APK compilation, and automated releases. |

---

## 🚀 Quick Start

### 1. Rust Protocol Core (`core/`)

```bash
cd core
cargo test
cargo clippy --all-targets --all-features
```

### 2. Flutter Native Application (`flutter_app/`)

```bash
cd flutter_app
flutter pub get
flutter run
```

To build a release Android APK:

```bash
flutter build apk --release
```

### 3. Tauri 2 Desktop Client (`app/`)

```bash
cd app
npm install
npm run tauri dev
```

---

## 📦 Downloads & Releases

Pre-compiled binary releases and installers are automatically generated on every tag push (`v*`) and available on GitHub Actions:

- **Android**: `app-release.apk`
- **Windows**: `.msi` / `.exe`
- **macOS**: `.dmg` (Apple Silicon `aarch64` & Intel `x64`)
- **Linux**: `.deb`, `.AppImage`, `.rpm`

Check the latest builds on the [GitHub Releases](https://github.com/ShanudhaTirosh/shanu-send/releases) page.

---

## 📄 License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for more information.
