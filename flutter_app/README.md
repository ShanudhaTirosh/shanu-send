# ShanuSend Mobile Client (`flutter_app`)

Cross-platform mobile application built with **Flutter** and **Dart** for Android and iOS devices, designed to seamlessly interoperate with ShanuSend Desktop, LocalSend v2.1, Apple AirDrop, Google Quick Share, and ShanuConnect P2P networks.

---

## ✨ Features

- **⚡ Zero-Copy Stream Transfers**: Stream files with real-time speed meter (MB/s), percentage progress, and ETA calculation.
- **🔄 LocalSend v2.1 Compatibility**: Auto-discovers and transfers files to LocalSend devices on port 53317.
- **📱 ShanuConnect Remote Controller**:
  - **Remote Trackpad**: Smooth gesture tracking, tap-to-click, two-finger scroll, left/right buttons.
  - **Media Remote & MPRIS Clicker**: Play/pause, next/prev track, volume scrubber.
  - **Presentation Clicker**: Forward/backward slide trigger.
  - **Workstation Commands**: Ring phone, lock remote desktop screen, send SMS.
- **🍏 Apple AirDrop & WebDrop Portal**: Embedded Shelf HTTP server on port 53317 hosting the mobile WebPortal and generating QR codes for browser sharing.
- **⚡ Quick Share / Nearby Share Client**: Outbound Quick Share sender targeting `:5238/api/quickshare/v1/*`.
- **🎨 Glassmorphism Dark Theme**: `#0B0F19` background, `#38BDF8` cyan accent, and `#6366F1` indigo accent.

---

## 📁 Architecture

| Directory / File | Description |
| :--- | :--- |
| `lib/main.dart` | Application entry point and dark theme configuration. |
| `lib/models/` | Data Transfer Objects (`DeviceDto`, `FileDto`). |
| `lib/services/` | Network services (`discovery_service.dart`, `transfer_service.dart`, `shanu_connect_service.dart`, `quickshare_service.dart`, `webdrop_server.dart`). |
| `lib/views/` | Screen views (`home_view.dart`, `shanu_connect_view.dart`, `remote_trackpad_view.dart`). |
| `lib/widgets/` | Custom UI components (`speed_badge.dart`, `webdrop_modal.dart`). |

---

## 🚀 Building & Running

### 1. Run on Connected Device / Emulator

```bash
flutter pub get
flutter run
```

### 2. Build Android Release APK

```bash
flutter build apk --release
```

### 3. Run Static Analysis

```bash
flutter analyze
```

---

## 📄 License

Distributed under the **MIT License**. See [`LICENSE`](../LICENSE) for details.
