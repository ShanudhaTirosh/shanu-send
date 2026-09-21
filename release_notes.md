# ShanuSend v2.5.3 Release Notes 🚀

Universal High-Speed File Sharing, 2-Way AirDrop & Quick Share Bridge, ScrcpyGUI v4 Screen Mirroring Suite, ShanuConnect P2P Protocol Engine, and Cross-Platform Flutter Mobile App.

---

### ✨ Highlights of v2.5.3

#### 📱 1. Complete ScrcpyGUI v4 Feature Parity
- **3 Capture Modes**: Screen Mirror, Camera Webcam Mode, and Desktop Virtual Display (`--new-display`).
- **Camera Enhancements**: Camera Torch flashlight toggle, Camera Zoom slider (1.0x - 10.0x), and lens selection.
- **Pro Display & Performance Controls**: Flex Display dynamic sizing, VSync anti-tearing toggle, hex background color setting, bitrate control (1-100 Mbps), FPS caps (30/60/120), resolution options, Opus audio fallback chain, and ignore video encoder constraints option.
- **Pro Input Modes**: OTG Keyboard/Mouse, HID Keyboard/Mouse simulation, and Pure HID (No Mirror) mode.
- **Win32 Window Navigation**: Drag borderless mirror windows with `Ctrl+Alt+Shift+W` and recenter with `Ctrl+Alt+Shift+C`.
- **Wireless ADB Pairing**: mDNS auto-discovery & native 6-digit PIN pairing modal for Android 11+.

#### 🌐 2. Universal Multi-Protocol Transfer Engine
- **Apple AirDrop (iOS / macOS Interoperability)**:
  - Answers `_airdrop._tcp.local.` mDNS queries on UDP port 5353.
  - Axum endpoints for `/Ask`, `/Upload`, `/Discover` on port 8770.
  - Outbound `send_file_airdrop` command to send files directly to Apple devices.
- **Google Quick Share / Nearby Share (Android / Windows / Linux Interoperability)**:
  - Answers `_FC92._tcp.local.` mDNS queries on UDP port 5353 and BLE service `0xFE2C`.
  - Axum endpoints `/api/quickshare/v1/prepare-upload` and `/api/quickshare/v1/upload` on port 5238.
  - UKEY2 4-digit PIN verification generator & outbound `send_file_quickshare` command.
- **LocalSend v2.1 Protocol**:
  - Multicast mDNS discovery on `224.0.0.167:53317` and `/api/localsend/v2/*` endpoints.
- **ShanuConnect (Native App-to-App P2P)**:
  - Port 1716 TCP & UDP listeners compatible with ShanuConnect and KDE Connect protocol v7.
  - Remote trackpad/mousepad, clipboard sync, battery monitoring, phone ringer, remote command execution, SMS, MPRIS media control, and call notifications.
- **WebPortal / WebDrop**:
  - Served live at `http://<IP>:53317/web` for zero-install browser file transfer.

#### 📱 3. Flutter Mobile Client (`flutter_app/`)
- Subnet scanner (`DiscoveryService`), zero-copy stream transfer service (`TransferService`), ShanuConnect remote touchpad & media controller (`ShanuConnectService`), Quick Share sender (`QuickShareService`), and mobile WebDrop server (`WebDropServer`).
- Dark glassmorphism UI system matching the desktop application.
- English (`en`) UI default.

---

### 📦 Build & Installer Artifacts

- **Windows Installer (NSIS)**: `ShanuSend_2.5.3_x64-setup.exe`
- **Windows MSI Package**: `ShanuSend_2.5.3_x64_en-US.msi`
- **Standalone Desktop Executable**: `shanusend.exe`
- **Android App**: `app-release.apk`
