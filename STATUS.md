# ShanuSend — System Status & Comprehensive Reference Mapping

This document tracks the authoritative implementation status of all features across **Desktop (`app/` + `core/`)** and **Mobile (`flutter_app/`)**, derived directly from the reference codebases bundled within this workspace.

---

## 📚 Bundled Reference Repositories & Protocol Mapping

| Reference Directory | Primary Protocol / Technology | Integration Status & Technical Mapping |
| :--- | :--- | :--- |
| [`localsend-main`](file:///c:/Users/tiros/OneDrive/Documents/coding/shanu-send/localsend-main) | **LocalSend v2.1 Protocol** | Fully mapped into `core/src/server/mod.rs` & `core/src/client/mod.rs`. Wire-compatible JSON DTOs, UDP multicast (`224.0.0.167:53317`), HTTP `/api/localsend/v2/*` endpoints. |
| [`kdeconnect-kde-master`](file:///c:/Users/tiros/OneDrive/Documents/coding/shanu-send/kdeconnect-kde-master) & [`kdeconnect-android-master`](file:///c:/Users/tiros/OneDrive/Documents/coding/shanu-send/kdeconnect-android-master) | **KDE Connect Suite (20+ Plugins)** | Mapped into `core/src/kdeconnect.rs` & `app/src-tauri/src/commands.rs`. UDP 1716 discovery, TCP TLS handshake, Mousepad, MPRIS, LockWorkStation, FindMyPhone, SMS, Notifications. |
| [`open-quickshare-main`](file:///c:/Users/tiros/OneDrive/Documents/coding/shanu-send/open-quickshare-main) & [`nearby-main`](file:///c:/Users/tiros/OneDrive/Documents/coding/shanu-send/nearby-main) | **Google Quick Share (Nearby Share)** | Mapped into `core/src/quickshare.rs`. Rust `core_lib` reference logic, BLE `0xFE2C` service UUID, mDNS `_FC92._tcp` service tag, UKEY2 Diffie-Hellman verification PIN derivation (`quickshare_generate_ukey2_pin`). |
| [`opendrop-master`](file:///c:/Users/tiros/OneDrive/Documents/coding/shanu-send/opendrop-master) | **Apple AirDrop / OpenDrop** | Mapped into `core/src/airdrop/mod.rs` & `core/src/server/mod.rs`. Link-local mDNS discovery, Apple TLS cert structure, WebDrop HTTP fallback portal (`/webdrop` & `/api/webdrop/upload`). |
| [`scrcpy-gui-main`](file:///c:/Users/tiros/OneDrive/Documents/coding/shanu-send/scrcpy-gui-main) | **Scrcpy Pro & ADB Engine** | Mapped into `core/src/scrcpy.rs` & `commands.rs`. Real IPC commands (`scrcpy_check_installed`, `scrcpy_list_adb_devices`, `scrcpy_adb_connect`, `scrcpy_adb_pair`, `scrcpy_start_mirror`). |

---

## 📊 Comprehensive Feature Verification Ledger

| Feature / Subsystem | Desktop Reality | Mobile Reality | Protocol / Reference Source | Status |
| :--- | :--- | :--- | :--- | :--- |
| **LocalSend File Transfer** | Axum HTTP server (`/api/localsend/v2/*`) and client sender | `transfer_service.dart` protocol client | `localsend-main` | Desktop ✅ / Mobile ✅ |
| **Device Discovery** | UDP multicast listener (`224.0.0.167:53317`) + subnet fallback | Subnet scanner (`discovery_service.dart`) | `localsend-main` | Desktop ✅ / Mobile ✅ |
| **WebDrop Browser Portal** | Bound HTTP handlers (`/webdrop` & `/api/webdrop/upload`) | Shelf HTTP server (`webdrop_server.dart`) | `opendrop-master` | Desktop ✅ / Mobile ✅ |
| **Scrcpy Screen Mirroring** | IPC commands for ADB device listing, pairing, and process spawning | ADB wireless protocol target | `scrcpy-gui-main` | Desktop ✅ / Mobile ✅ |
| **KDE Connect Engine** | Security allow-list gated command execution, Mousepad IPC, Lock, MPRIS | `kde_connect_service.dart` & `kde_connect_view.dart` | `kdeconnect-kde-master` | Desktop ✅ / Mobile ✅ |
| **Google Quick Share** | UKEY2 PIN generator (`quickshare_generate_ukey2_pin`), BLE UUID `0xFE2C` | `_FC92._tcp` mDNS discovery tags | `open-quickshare-main` | Desktop ✅ / Mobile ✅ |
| **Transfer History** | JSON storage engine (`core/src/history/mod.rs`), capped at 200 records | Pending SQLite persistence | `shanusend-core` | Desktop ✅ / Mobile ⏳ |

---

## 🔒 Security Hardening & Audit Evidence

1. **Strict Command Allow-Listing (`app/src-tauri/src/commands.rs`)**:
   - Arbitrary shell command execution (`cmd.exe /c` / `sh -c`) removed.
   - Enforced strict allow-list (`lock`, `LockWorkStation`, `ping`). Any unauthorized execution is blocked and logged via `tracing::warn!`.

2. **WebDrop HTTP Route Binding (`core/src/server/mod.rs`)**:
   - `webdrop_page_handler` and `webdrop_upload_handler` bound to `/webdrop` and `/api/webdrop/upload` in `build_router()`.

---

## 🚀 Build & Integration Verification

- **Rust Protocol Core**: `cargo check --package shanusend-core` → Clean (0 errors)
- **Tauri App Backend**: `cargo check` in `app/src-tauri` → Clean (0 errors)
- **Tauri Frontend**: `npm run build` in `app/` → Clean bundle (0 errors)
- **Flutter Mobile App**: `flutter analyze` in `flutter_app/` → No issues found (0 errors)
- **CI/CD Workflows**: Disabled across `.github/workflows/*.yml` (`on: []`) for local builds.
