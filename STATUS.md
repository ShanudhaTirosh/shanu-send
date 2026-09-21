# ShanuSend — System Status & Platform Matrix

Authoritative system feature matrix and verification status across **Desktop Host (`app/` + `flutter_app/`)** and **Mobile Client (`flutter_app/`)**.

---

## 🖥️ Desktop App (`flutter_app/` & `app/`) — Host & Workstation Engine

The desktop app operates as the central workstation hub for file transfers, display rendering, and multi-protocol discovery:

- **Primary Interface Panels**:
  1. **ScrcpyGUI Suite (`scrcpy_gui_view.dart`)**:
     - ADB device discovery picker (USB & Wireless ADB).
     - Resolution presets: 720p, 1080p, and Original source resolution.
     - Bitrate tuning (2 - 16 Mbps), FPS caps (30/60 FPS), Video Codecs (H.264, H.265, AV1).
     - Stay Awake during mirroring toggle, Turn Screen Off toggle, and MP4 Screen Recording engine.
  2. **Phone Link Host Hub (`desktop_phone_link_view.dart`)**:
     - Active device selector dropdown with 6-digit SAS Security PIN pairing modal.
     - **Pure Live Event Stream**: Real-time packet listeners (`shanuconnect.notifications`, `shanuconnect.sms`, `shanuconnect.battery`, `shanuconnect.mpris`) with zero mock/hardcoded demo arrays.
     - Mirrored phone notifications with inline reply action.
     - Phone Battery status & charging indicator, Wi-Fi status, and remote phone ringer trigger (`Find Phone`).
     - SMS reader and manager; call control alerts.
     - Bidirectional clipboard auto-sync.
  3. **Universal File Transfer (`home_view.dart`)**:
     - **UnifiedHttpServer**: Consolidated port `53317` server eliminating `Route not found` errors and uniting LocalSend v2.1 API with WebDrop HTML5 browser portal.
     - Continuous LAN scanning loop for LocalSend v2.1, Apple AirDrop, Google Quick Share, and ShanuSend P2P.
  4. **WebDrop Browser Portal**:
     - Zero-install browser file transfer portal served on port 53317 (`http://<IP>:53317` & `http://<IP>:53317/webdrop`).

---

## 📱 Mobile App (`flutter_app/`) — Client & Remote Controller

The mobile app is built with Flutter and Dart, optimized for phone/tablet interaction:

- **Primary Views & Services**:
  1. **Universal Transfer Manager (`home_view.dart`)**:
     - Multi-file selection, subnet scanner, live MB/s speed meter badge, and transfer progress indicator.
  2. **Mobile Remote Controller & Device Hub (`shanu_connect_view.dart`)**:
     - Integrated Device Hub selector bar with 6-digit SAS PIN pairing modal.
     - Multi-touch trackpad surface (gestures, tap-to-click, scroll), MPRIS media player remote, presenter slide clicker, shared clipboard sync, and remote workstation commands.
  3. **Unified WebDrop Server (`unified_http_server.dart`)**:
     - Embedded HTTP server serving the WebDrop portal and generating QR codes for browser sharing.

---

## 🚀 Build & Integration Verification Matrix

| Component | Target Platform | Verification Command | Result |
| :--- | :--- | :--- | :--- |
| **Rust Core** (`core/`) | Multi-Platform Engine | `cargo check` | **PASSED** (0 errors) |
| **Desktop App** (`app/src-tauri`) | Windows / macOS / Linux | `cargo check` | **PASSED** (0 errors) |
| **Flutter Analysis** (`flutter_app/`) | Android / iOS / Desktop | `flutter analyze` | **PASSED** (0 issues found!) |
| **Flutter Test Suite** (`flutter_app/`) | Unit & Widget Tests | `flutter test` | **PASSED** (All tests passed!) |
| **Windows Native Executable** (`flutter_app/`) | Windows x64 Release | `flutter build windows` | **PASSED** (`shanu_send_flutter.exe`) |

---

*Last Updated: September 2026*

