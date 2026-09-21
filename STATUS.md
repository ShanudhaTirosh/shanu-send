# ShanuSend — System Status & Platform Matrix

Authoritative system feature matrix and verification status across **Desktop Host (`app/` + `core/`)** and **Mobile Client (`flutter_app/`)**.

---

## 🖥️ Desktop App (`app/`) — Host & Management Engine

The desktop app operates as the central workstation hub for file transfers, display rendering, and multi-protocol discovery:

- **Primary Interface Panels**:
  1. **ScrcpyGUI v4 Screen Mirroring**:
     - 3 Capture Modes: Screen Mirror, Camera Webcam Mode, Desktop Virtual Display (`--new-display`).
     - Camera Torch toggle, Camera Zoom slider, Flex Display mode, VSync toggle, background color customization.
     - Pro Input: OTG Keyboard/Mouse, HID Keyboard/Mouse simulation, Pure HID (No Mirror) mode.
     - Win32 Borderless Drag (`Ctrl+Alt+Shift+W`) and Recenter (`Ctrl+Alt+Shift+C`).
     - Wireless mDNS auto-discovery & native 6-digit PIN pairing modal for Android 11+.
  2. **Universal File Transfer**:
     - LocalSend v2.1 multicast listener (`224.0.0.167:53317`).
     - Apple AirDrop mDNS & HTTPS endpoints (`:8770`).
     - Google Quick Share mDNS & HTTP endpoints (`:5238`).
     - ShanuConnect / KDE Connect protocol engine (`:1716`).
  3. **WebDrop / WebPortal**:
     - Browser file transfer portal at `http://<IP>:53317/web`.
     - Direct file publishing, download streaming, and text note receiver.
- **Customization**:
  - Default English (`en`) dictionary and localization.
  - 5 Glassmorphism Themes: Ultraviolet, Astro, Carbon, Emerald, Bloodmoon.

---

## 📱 Mobile App (`flutter_app/`) — Client & Remote Controller

The mobile app is built with Flutter and Dart, optimized for mobile devices:

- **Primary Views & Services**:
  1. **Universal Transfer Manager (`home_view.dart`)**:
     - File picker, subnet scanner, live MB/s speed meter badge, and transfer progress bar.
  2. **ShanuConnect Remote Controller (`shanu_connect_view.dart` & `remote_trackpad_view.dart`)**:
     - Remote trackpad (gestures, tap-to-click, scroll), system volume scrubber, media player clicker (play/pause/skip), presentation slide controller, phone ringer trigger, and remote workstation lock.
  3. **Mobile WebDrop Server (`webdrop_server.dart`)**:
     - Embedded Shelf HTTP server hosting the mobile WebPortal and generating QR codes for browser sharing.
  4. **Quick Share Outbound Service (`quickshare_service.dart`)**:
     - Direct file sender targeting Quick Share endpoints.

---

## 🚀 Build & Integration Verification Matrix

| Component | Target Platform | Verification Command | Result |
| :--- | :--- | :--- | :--- |
| **Rust Core** (`core/`) | Multi-Platform Engine | `cargo check` | **PASSED** (0 errors) |
| **Desktop App** (`app/src-tauri`) | Windows / macOS / Linux | `cargo check` | **PASSED** (0 errors) |
| **Desktop Web UI** (`app/`) | React 19 + TypeScript | `npx tsc --noEmit` | **PASSED** (0 errors) |
| **Desktop Executable & Bundle** (`app/`) | Windows x64 | `npx tauri build` | **PASSED** (EXE + MSI + NSIS) |
| **Flutter Mobile App** (`flutter_app/`) | Android / iOS | `flutter analyze` | **PASSED** (0 issues found!) |

---

*Last Updated: September 2026*
