# ShanuSend — Status

This replaces the previous version of this file, which claimed "0 errors / 0 issues / all tests passed" without
a linked, reproducible CI run to back that up, and described desktop features (`app/` Tauri client) that don't
exist in this repo. This version is a plain real / partial / planned breakdown, verified by reading
`flutter_app/lib/` and `core/src/` directly. See `IMPLEMENTATION_PLAN.md` for the detailed audit and fix plan.

Legend: ✅ implemented and wired into the app · 🟡 partially implemented (see note) · ⬜ not implemented yet

## Core transfer

| Feature | Status | Note |
| :--- | :--- | :--- |
| LocalSend v2.1 receive (push) | ✅ | `UnifiedHttpServer` — `prepare-upload`/`upload`, now gated behind a real Accept/Decline prompt |
| LocalSend v2.1 send | ✅ | via `TransferService` |
| LocalSend "download mode" (pull) | ⬜ | no `GET /api/localsend/v2/download` route yet |
| WebDrop browser portal | ✅ | served from the same port, no app install required |
| TLS transport | ⬜ | plain HTTP today; `core/`'s `rustls` support isn't linked into the app yet |
| Apple AirDrop / Google Quick Share | 🟡 | implemented in `core/` (Rust); not linked into `flutter_app/`, so not active in the shipped app |

## ShanuConnect (remote control / phone link)

| Feature | Status | Note |
| :--- | :--- | :--- |
| Device pairing | ✅ | mutual code confirmation on both sides + persisted trust list (`trusted_device_store.dart`) — previously any typed 6-digit number was accepted with no check |
| Per-install device identity | ✅ | persisted UUID (`device_identity_service.dart`) — previously every install shared the same hardcoded ID |
| Trackpad → real cursor movement | 🟡 | Windows: direct Win32 calls. macOS/Linux: via `cliclick`/`xdotool` if installed, otherwise no-op |
| Trackpad UI buttons (click, slides, play/pause) | ✅ | now send real packets — previously most buttons only updated local UI text |
| Command execution allow-list (`runcommand`) | ⬜ | not implemented — do not enable arbitrary remote command execution without this |
| Notifications / SMS / battery / MPRIS sync | 🟡 | packet types and some UI exist; not all paths verified end-to-end |
| Cryptographic pairing (vs. mutual on-screen comparison) | ⬜ | planned once the Rust core's crypto module is bridged in |

## Scrcpy screen mirroring

| Feature | Status | Note |
| :--- | :--- | :--- |
| ADB device discovery | ✅ | real `adb devices -l` polling — previously a single hardcoded placeholder entry |
| Wireless ADB pairing | ✅ | `adb pair` / `adb connect` flow in the UI |
| adb binary bootstrap | ✅ | auto-downloads Google's platform-tools for the current OS if not already present |
| scrcpy binary bootstrap | 🟡 | automated on Windows only; macOS/Linux show package-manager install instructions |
| Per-device targeting (`-s <serial>`) | ✅ | |
| Session error visibility | ✅ | stderr/stdout now surfaced in-app instead of only `debugPrint` |

## Platform configuration

| Item | Status | Note |
| :--- | :--- | :--- |
| Android permissions | ✅ | |
| Android cleartext HTTP | ✅ | `network_security_config.xml` added — previously broke LAN transfer on Android 9+/API 28+ |
| iOS local network / Bonjour usage keys | ✅ | |

## Architecture

| Item | Status | Note |
| :--- | :--- | :--- |
| Rust core (`core/`) linked into the Flutter app | ⬜ | not linked today (no `flutter_rust_bridge` dependency); see `IMPLEMENTATION_PLAN.md` §2 |
| Single source of truth for protocol logic | ⬜ | currently duplicated between `core/` (Rust) and `flutter_app/lib/services/` (Dart) |

## Build verification

No claim is made here about `flutter analyze` / `flutter test` / release build results, because this file is generated
from a source read, not a CI run. Wire this table to your actual CI job output (see `IMPLEMENTATION_PLAN.md` §7 —
"Verified CI") rather than filling it in by hand.

*Last updated from a direct source read alongside `IMPLEMENTATION_PLAN.md`.*
