# ShanuSend

<div align="center">

![ShanuSend Banner](logo.png)

**Cross-platform file sharing, phone link, and screen mirroring — one Flutter app for desktop and mobile.**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

[Features](#features) • [Project Structure](#project-structure) • [Quick Start](#quick-start) • [Known Limitations](#known-limitations--in-progress) • [License](#license)

</div>

---

## Status

This README describes what's actually implemented in `flutter_app/`, verified by reading the source — not aspirational copy. See
[`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md) for the full audit and the phased plan to close the remaining gaps, and
[`STATUS.md`](STATUS.md) for a per-feature real/partial/planned breakdown.

## ✨ Features

- **LocalSend v2.1 file transfer**: real HTTP server (`UnifiedHttpServer`) implementing `info` / `register` / `prepare-upload` / `upload` / `cancel`, with an Accept/Decline prompt gating every incoming transfer. Two-way "download mode" (serving files *to* a peer that requests them) isn't implemented yet — this app can receive pushed transfers and send its own, but doesn't yet expose the pull-style download endpoint.
- **WebDrop**: zero-install browser transfer portal served from the same port (`http://<IP>:53317` / `/webdrop`) — works from Safari/Chrome without installing the app.
- **ShanuConnect (KDE Connect-style remote control)**: real mutual pairing (both sides generate/compare a code and must explicitly confirm — no longer "type any 6 digits"), a persisted trusted-device allow-list, and real cursor control on the receiving desktop (Windows via direct Win32 calls; macOS/Linux via `cliclick`/`xdotool` when installed). Notifications/SMS/battery/MPRIS packet types are defined in the protocol but not all have a UI surface yet — check `IMPLEMENTATION_PLAN.md` for what's wired end-to-end today.
- **Scrcpy screen mirroring**: the app manages its own copies of `adb`/`scrcpy` instead of assuming they're preinstalled — one-time setup downloads and caches Android Platform-Tools (all OSes) and scrcpy (Windows; macOS/Linux currently prompt for a package-manager install, since prebuilt binaries there depend on system libraries that vary by distro). Real `adb devices -l` polling drives the device picker, with wireless ADB pairing support.
- **Rust core (`core/`)**: a substantial second implementation (LocalSend, AirDrop, Quick Share, ShanuConnect, TLS via `rustls`, real input simulation via `enigo`) lives in this repo but **is not currently linked into the Flutter app** — see Known Limitations.

---

## 📁 Project Structure

| Directory / File | Description |
| :--- | :--- |
| [`core/`](core/) | Rust engine: LocalSend/AirDrop/Quick Share/ShanuConnect protocol logic, TLS, and `enigo`-based input simulation. **Not yet linked into `flutter_app/`** — see Known Limitations. |
| [`flutter_app/`](flutter_app/) | The actual application — Windows, Android, iOS, macOS, and Linux from one Flutter codebase. Everything under Features above lives here. |
| [`.github/workflows/`](.github/workflows/) | CI pipelines. Treat badge/status claims as accurate only as far as the workflow file itself verifies (see `STATUS.md`). |

There is no `app/` (Tauri) directory in this repo — an earlier iteration of this project used Tauri for desktop, but the project has since consolidated onto Flutter for both desktop and mobile. References to a Tauri desktop client elsewhere (old docs, old issues) are stale.

---

## 🚀 Quick Start

```bash
cd flutter_app
flutter pub get
flutter run                       # desktop or mobile, depending on target
flutter build windows             # Windows release build
flutter build apk --release       # Android APK
```

### Rust core (currently a standalone check only — not yet part of the app build)

```bash
cd core
cargo check
```

---

## Known Limitations / In Progress

- **Two engines, one used.** `core/` (Rust) has real TLS and real cross-platform input simulation (`enigo`) that `flutter_app/` doesn't use yet — the Flutter app has its own, less complete Dart implementations instead. Bridging via `flutter_rust_bridge` is the top item in `IMPLEMENTATION_PLAN.md`.
- **Transport is plain HTTP today**, not TLS — `core/`'s TLS support isn't wired in yet. A network security config permits cleartext LAN traffic in the meantime (see `flutter_app/android/app/src/main/res/xml/network_security_config.xml` for why).
- **ShanuConnect pairing is mutual-comparison, not cryptographic.** Both sides must confirm a shown code before trust is granted (a real fix over the previous free-text entry), but it isn't bound to a key exchange yet, so it doesn't protect against a spoofed sender on the same LAN. Real ECDH-backed pairing is planned once the Rust bridge lands.
- **scrcpy auto-setup is Windows-only**; macOS/Linux users get install instructions (Homebrew/apt/dnf/pacman/Flatpak) instead of a silent download, since prebuilt binaries there depend on system libraries that vary by distro.
- **Remote input on macOS/Linux depends on `cliclick`/`xdotool` being installed** — there's no bundled fallback yet.

See `IMPLEMENTATION_PLAN.md` for the full audit this list is based on, and the phased plan to close each gap.

---

## 📄 License

Distributed under the **MIT License**. See [`LICENSE`](LICENSE) for more information.
