# ShanuSend — System Status & Strict Platform-Aware Matrix

This document details the authoritative feature distribution between **Desktop Host (`app/` + `core/`)** and **Mobile Client (`flutter_app/`)**.

---

## 🖥️ Desktop App (`app/`) — Host & Management Engine
The desktop app runs as the central workstation hub for file transfers, display rendering, and device management:

- **Primary Desktop Interface Tabs**:
  1. `File Transfer`: Drag-and-drop file sender, incoming file transfer prompt, LocalSend progress bars.
  2. `Screen Mirroring (Scrcpy Host)`: Scrcpy Pro controller to launch, view, and control phone screens over USB/Wireless ADB.
  3. `KDE Device Hub`: Central management for paired phone status, battery reporting, remote workstation locking, and phone ringing.
- **Hosted Desktop Portals**:
  - `WebDrop Web Server Portal`: Axum web server hosting `/webdrop` and `/api/webdrop/upload` for mobile browser drag-and-drop uploads.
- **Excluded from Desktop UI**:
  - `Remote Touchpad Surface` has been removed from Desktop (touchpad sending is an input mechanism for smartphones).

---

## 📱 Mobile App (`flutter_app/`) — Client & Remote Controller
The mobile app is optimized for single-hand touch interaction:

- **Primary Mobile Views & Controllers**:
  1. `File Sharing`: Send files to PC or mobile peers; receive files via `shelf` LocalSend receiver.
  2. `Mobile Remote Touchpad (`KdeConnectView`)`: Use phone screen as a wireless trackpad (gesture movement, tap-to-click, left/right buttons, scroll).
  3. `Media Remote & Clicker`: Remote volume scrubber, play/pause controls, and presentation slide clicker.
  4. `WebDrop Portal`: Embedded shelf webdrop server.
- **Excluded from Mobile UI**:
  - `Scrcpy Host Window Launcher` (scrcpy runs as a host process on PC, capturing phone displays).

---

## 🚀 Build & Integration Verification

- **Rust Protocol Core**: `cargo check --package shanusend-core` → Clean (0 errors)
- **Tauri App Backend**: `cargo check` in `app/src-tauri` → Clean (0 errors)
- **Tauri Frontend**: `npm run build` in `app/` → Clean bundle (0 errors)
- **Flutter Mobile App**: `flutter analyze` in `flutter_app/` → No issues found! (0 errors)
- **CI/CD Workflows**: Disabled across `.github/workflows/*.yml` (`on: []`) for local builds.
