# ShanuSend → Production-Grade Implementation Plan

This plan is based on a direct read of the code in `shanu-send-main.zip` you uploaded (not the README's claims), compared against `localsend-main.zip` as the UI/UX and architecture reference. Every finding below is tied to a real file so nothing here is guesswork.

**Bottom line up front:** the project's biggest problem isn't missing features — it's that you have *two* engines. A real, capable Rust core (`core/`) with TLS, LocalSend, AirDrop, Quick Share, and even working mouse/keyboard simulation (via the `enigo` crate) sits completely unused. The Flutter app talks to none of it and instead reimplements a thinner, less secure version of the same things in pure Dart. That split is why things *look* like real features (protocol names, PIN dialogs, device pickers) but don't fully work underneath. Fixing that split is the single highest-leverage thing you can do — everything else (scrcpy binaries, real pairing, UI polish) gets easier once it's fixed.

---

## 1. What's actually true right now (code-verified audit)

| Area | README/STATUS claims | What the code actually does |
|---|---|---|
| Desktop app | "Tauri 2 + React 19, glassmorphism UI, 5 color themes" | There is **no `app/` directory** in the zip at all. The desktop experience is the same Flutter binary as mobile (`flutter build windows`). `app_theme.dart` defines exactly **2** themes (light/dark), no glassmorphism, no theme picker in the UI. |
| Rust core | "Multi-protocol server... mDNS... TLS crypto" used by the apps | `core/` is real and non-trivial (3,458 lines: LocalSend server/client, AirDrop, Quick Share, ShanuConnect, TLS via `rustls`, mouse/keyboard control via `enigo`) — but `flutter_app/pubspec.yaml` has **zero** dependency on it (no `flutter_rust_bridge`, no FFI plugin). It never gets compiled into the app. It's dead weight today. |
| LocalSend transfer | "Wire-level compatibility" | Real HTTP server exists on both mobile (`receiver_service.dart`) and desktop (`unified_http_server.dart`) implementing `info/register/prepare-upload/upload/cancel`. **But**: incoming transfers are written to disk immediately with no Accept/Decline prompt to the user, and there's no PIN-protected receive mode — anyone on the LAN can push files onto the device silently. |
| ShanuConnect / KDE Connect suite | "6-digit SAS Security PIN pairing", "Zero Mock / Pure Live Event Stream" | `shanu_connect_service.dart` broadcasts/receives raw JSON UDP packets. There is **no pairing verification anywhere** — `sendPairing()` just fires a `{pair: true, deviceId: "mobile-remote-id"}` packet (a hardcoded string, not even the real device ID) with nothing checking a PIN before capability packets are trusted. The "SAS PIN" only appears as **static text in a dialog widget** — no code computes, transmits, or verifies a SAS value. |
| Remote mouse/keyboard control | Full trackpad, presenter clicker, etc. | `remote_trackpad_view.dart` **sends** `shanuconnect.mousepad` UDP packets. Nothing in the entire Flutter app **receives** that packet type and moves an actual cursor. The real capability to do this already exists in Rust (`core/src/shanuconnect.rs` calls `enigo.move_mouse(...)`) but that code is never invoked from the Flutter side, so today remote control is a no-op on the receiving end. |
| Scrcpy GUI suite | "ADB Device Picker... wireless and USB discovery" | `scrcpy_gui_view.dart` has a device dropdown populated with a **single static string** (`'Android Device (USB / Wireless ADB)'`) — there is no `adb devices` call anywhere in the codebase (only 3 total mentions of "adb" in the whole `lib/`, all UI labels). Launching mirroring calls `Process.start('scrcpy', args)` assuming `scrcpy` is already on the system `PATH`; if it isn't (the normal case for an end user who just installed your app), it fails with a toast telling *them* to go install it. **This is exactly the "need download bin for scrapy tool to work" problem you flagged** — nothing in the app ever fetches/bundles the `scrcpy` or `adb` binaries. |
| Build/test status | "PASSED, 0 errors, 0 issues, all tests passed" (STATUS.md) | Not independently verifiable from a zip, but given the gaps above (dead Rust core, no-op remote control, single-string device list), these are best read as aspirational/marketing text, not verified QA results. |
| Android manifest | (Earlier audit had flagged this as broken) | **Now fixed** — permissions are present (`INTERNET`, `POST_NOTIFICATIONS`, `FOREGROUND_SERVICE`, media/storage, multicast). Good. |
| iOS Info.plist | (Earlier audit had flagged this as a blank template) | **Now fixed** — `NSLocalNetworkUsageDescription` and `NSBonjourServices` are present, which iOS 14+ requires for local network / mDNS discovery to work at all. |
| Android cleartext HTTP | — | **New bug found**: the `<application>` tag has no `android:usesCleartextTraffic="true"` and no network security config. Android 9+ (API 28+, which is effectively every real device) blocks plaintext `http://` by default. Since LocalSend/WebDrop currently run over plain HTTP on port 53317, **transfers will silently fail to connect from newer Android devices** until this is set or TLS is turned on. |
| Two-way LocalSend | — | Both HTTP servers implement upload-receive routes only; there's no `GET /api/localsend/v2/download/...` route. This means ShanuSend can *receive* pushes fine but can't serve files to a peer that requests "download mode" (minor — most LocalSend traffic is push-based — but worth closing for full protocol parity). |

None of this means the project is in bad shape — the transfer core (the actual file-sending path) is real and functional. The remote-control suite and the scrcpy suite are the parts that are currently UI shells around missing backends, and that's exactly what you called out.

---

## 2. Target architecture (fixes the root cause)

**Recommendation: stop maintaining two engines. Bridge Flutter to the existing Rust `core/` via [`flutter_rust_bridge`](https://cjycode.com/flutter_rust_bridge/) and delete the parallel Dart reimplementations once parity is reached.**

Why this instead of "just build the missing pieces in Dart":
- The hard, security-sensitive, and platform-native pieces (TLS/certs, mDNS, real mouse/keyboard injection via `enigo`, LocalSend/AirDrop/Quick Share protocol logic) are **already written and compiling** in Rust. Pure Dart has no cross-platform way to synthesize OS-level input events at all — you'd end up writing four platform channels (Win32 `SendInput`, macOS `CGEvent`, X11/Wayland, Android `AccessibilityService`) to match what `enigo` already gives you for free.
- It removes the "two sources of truth" problem that caused the current drift between what the README claims and what the Dart code does.
- `core/Cargo.toml` already declares `crate-type = ["lib", "cdylib", "staticlib"]`, which is exactly what's needed for FFI — this wasn't wired up, but it was clearly planned for.

**What moves where:**

| Stays in Flutter/Dart | Moves to Rust core (via FFI bridge) |
|---|---|
| All UI/widgets/navigation/theming | LocalSend server + client (already there) |
| `file_picker`, platform file dialogs | AirDrop, Quick Share (already there) |
| Local notifications trigger (UI-level) | ShanuConnect/KDE Connect protocol + **real SAS pairing crypto** (already scaffolded in `core/src/crypto`) |
| WebDrop's embedded HTML page serving (fine to keep in Dart via `shelf` — it's just static content + simple file I/O) | Remote input execution (`enigo`) — this is the piece that turns a received `mousepad`/keyboard packet into an actual OS action |
| ADB/scrcpy process orchestration (see §4 — this can stay Dart, it's just `Process` calls) | TLS/cert generation & fingerprint pinning (`core/src/crypto`) — currently built but disabled |

**Migration approach (incremental, not a rewrite):**
1. Add `flutter_rust_bridge_codegen` to the Rust core and generate bindings for one module first — `core::crypto` (cert gen + fingerprint) — since it's small, self-contained, and immediately fixes a real security gap (see §5).
2. Once the FFI plumbing is proven end-to-end (build pipeline for Windows/macOS/Linux/Android/iOS all linking the Rust `cdylib`/`staticlib`), migrate `core::shanuconnect` next, since that's what unblocks real remote-control (§3 below).
3. Migrate LocalSend server/client last, since the Dart version is functionally the most complete already — lowest priority, but do it eventually so there's one implementation instead of two that can drift apart again.
4. Only after a module is confirmed working end-to-end in the Flutter app, delete the parallel Dart implementation for that module. Don't delete early — that's how you end up back at "app that doesn't do what it says."

---

## 3. Making ShanuConnect / KDE Connect remote control actually work

This is currently the largest gap between "what the UI implies" and "what happens." Fix order:

1. **Real pairing.** Replace `sendPairing()`'s hardcoded `deviceId: 'mobile-remote-id'` with the device's real persisted ID. Implement an actual SAS (Short Authentication String) exchange:
   - On pair request, both sides derive a shared secret (ECDH — `core/src/crypto` is the right home for this once bridged), hash it down to a 6-digit code, and display it on **both** screens.
   - The user must confirm the *same* code is showing on both devices before the pairing is marked trusted (this is what "SAS" means — it's mutual, not one device typing a code the other made up).
   - Persist trusted device IDs + their public keys (`flutter_secure_storage` on the Dart side, or in Rust via the bridge) so re-pairing isn't required every session.
2. **Reject unauthenticated packets.** Every `shanuconnect.*` handler (mousepad, keyboard, runcommand, systemvolume, lockdevice especially) must check the sender is in the trusted-device list *before* acting. Right now nothing gates this — add that check as step one of the receive path, not step two.
3. **Wire the receive side to `enigo`.** Add a listener (on desktop) that, for trusted senders only, decodes `shanuconnect.mousepad`/keyboard packets and calls the Rust `enigo` functions that already exist in `core/src/shanuconnect.rs` lines ~645–681. This is the change that makes the trackpad view actually move your cursor instead of broadcasting into the void.
4. **`runcommand` needs an explicit allow-list.** Don't let a paired phone execute arbitrary shell commands on the desktop — mirror KDE Connect's model where the desktop user pre-configures a fixed list of named commands (e.g., "Lock Screen", "Sleep") and the phone can only trigger those by name.

---

## 4. Scrcpy + ADB: making the "download bin" problem go away

This directly answers "need download bin for scrapy tool to work." The fix is: **the app should never assume `scrcpy`/`adb` are already installed** — it should manage its own copies.

**Step 1 — Bundle or fetch platform binaries on first use:**
- `adb`: ship as part of the official [Android Platform-Tools](https://developer.android.com/tools/releases/platform-tools) ZIP (Google publishes per-OS builds). On first run of the Scrcpy panel, check an app-support subfolder (e.g. `~/Library/Application Support/ShanuSend/tools/` on macOS, `%APPDATA%\ShanuSend\tools\` on Windows); if `adb`/`adb.exe` isn't there, download the platform-tools ZIP for the current OS, unzip it there, and always invoke it by **absolute path**, never assume it's on `PATH`.
- `scrcpy`: same pattern using the official [Genymobile/scrcpy GitHub Releases](https://github.com/Genymobile/scrcpy/releases) — Windows releases bundle `scrcpy.exe` + a matching `adb.exe` together, macOS/Linux users more commonly have it via Homebrew/apt but you should still fetch a portable copy so the app doesn't silently fail for users who don't.
- Verify the download against the published SHA-256 (both projects publish checksums/release artifacts over HTTPS) before marking the tool "ready" — don't execute an unverified downloaded binary.
- Show a real progress UI for this download (it's tens of MB) instead of a spinner — first-run "Setting up screen mirroring tools…" with a progress bar is standard UX for this (KDE Connect's `scrcpy-gui` cousins and most scrcpy wrapper apps do exactly this).
- **License note:** Android Platform-Tools redistribution is bound to Google's SDK terms — show a one-time "Accept SDK license" step before the first download, same pattern Android Studio uses, don't silently bundle it in a way that skips consent. `scrcpy` itself is Apache-2.0, redistribution is fine with attribution in your about/licenses screen.
- Add these Dart deps to `pubspec.yaml` to support this: `archive` (unzip), `crypto` (checksum verification) — `dio` is already present for the download itself.

**Step 2 — Real device discovery.** Replace the static `_devices` list in `scrcpy_gui_view.dart` with:
- A periodic `Process.run(adbPath, ['devices', '-l'])` (every 2–3s while the panel is open), parsed into a real list of `{serial, model, connectionType}`.
- A "Pair over Wi-Fi" flow using `adb pair <ip>:<port> <code>` for Android 11+ wireless debugging, matching what real scrcpy-gui tools expose — this is the actual feature "wireless ADB pairing" implies, not just a resolution dropdown.
- Pass the selected device's real `serial` to `scrcpy` via `-s <serial>`, which `_startScrcpy()` doesn't currently do (it launches without targeting a device, so with more than one connected device it will fail or pick arbitrarily).

**Step 3 — Process lifecycle polish.** Surface `stderr` from the `scrcpy` process into the UI (right now failures only log to `debugPrint`, invisible to the user) so device-side error messages (e.g. "device unauthorized," "more than one device") are actually shown, not swallowed.

---

## 5. Security fixes (do these before calling anything "production")

1. **Enable TLS.** `core/` already implements self-signed cert generation + fingerprint pinning (`rustls`), and it's marked as a default feature in `Cargo.toml` — but since the Rust core isn't linked into the app at all, the Flutter HTTP servers run plain HTTP. Once bridged (§2), turn TLS on by default for the LocalSend/WebDrop listener and show the peer's certificate fingerprint in the pairing UI, same as LocalSend upstream does.
2. **Accept/Decline gate for incoming transfers.** `_handlePrepareUpload` on both mobile and desktop currently accepts and starts writing any incoming file set with no user confirmation. Add the same UX real LocalSend uses: an incoming-request event should pop a dialog ("`<sender>` wants to send you 3 files — Accept / Decline") *before* `_handleUpload` is allowed to write anything, and support the optional PIN-gated receive mode from the LocalSend spec for users who want it.
3. **Fix Android cleartext blocking** (see §1 table) — either turn on TLS (preferred, see #1) or, as a stop-gap, add a network security config scoped to local/private IP ranges only (don't blanket-enable cleartext for all domains).
4. **Trusted-device allow-list for ShanuConnect**, covered in §3 — this is the same fix as "accept/decline for file transfer" but for remote-control commands, which are more dangerous to get wrong (arbitrary mouse/keyboard/command execution vs. just receiving a file).

---

## 6. UI/UX: making it feel like LocalSend (and like a real desktop/mobile app, not a web page)

Comparing your `flutter_app/lib/` structure to LocalSend's `app/lib/`:

```
ShanuSend today:                 LocalSend (reference):
lib/
  models/                        lib/
  services/                        model/            (data + persistence)
  theme/                           provider/          (state — network, params, selection)
  views/                           pages/              (screens, incl. tabs/, settings/)
  widgets/                         widget/            (dialogs/, list_tile/, animations/, sliver/)
                                    util/native/        (platform-specific: tray, notifications)
```

Your structure mixes "screen" and "business logic" inside each `*_view.dart` file (e.g. `shanu_connect_view.dart` is 755 lines doing UI *and* pairing state *and* packet handling). LocalSend separates **state** (`provider/`) from **presentation** (`pages/`, `widget/`), which is what lets it scale to desktop+mobile from one codebase cleanly. Concrete restructure:

1. **Adopt a provider/state layer.** Move connection state, device lists, and transfer progress out of `StatefulWidget` fields and into dedicated state classes (Riverpod, which LocalSend uses, or Provider/Bloc — pick one and be consistent). This alone will make the "5 themes" and future feature work much easier to add without touching view files.
2. **Adaptive navigation, not two hardcoded layouts.** Right now desktop/mobile branching happens via scattered `Platform.isWindows` checks inside `home_view.dart`. Replace with a single responsive shell: `LayoutBuilder`/breakpoint-based nav — bottom nav bar under ~600dp width, a persistent nav rail above it (this is the standard Material 3 adaptive pattern and matches how LocalSend's `pages/tabs/` behaves across window sizes).
3. **Real theming.** Since the README already promises "5 color themes" and a distinctive glassmorphism look, actually build `ThemeExtension`-based accent-color variants (LocalSend does something similar with its theme picker) instead of the two static `ThemeData` objects in `app_theme.dart` today. Either deliver the 5 themes or update the README to stop claiming them — don't leave the mismatch.
4. **Native desktop chrome.** For a KDE-Connect/LocalSend-grade desktop feel you want:
   - A system tray icon with quick actions (Send, Receive toggle, Quit) — `tray_manager` or `system_tray` package — so the app can run minimized like LocalSend does.
   - Custom title bar / window controls via `bitsdojo_window` or `window_manager`, matching LocalSend's frameless-window desktop look instead of the default OS chrome.
   - OS drag-and-drop of files directly onto the app window (`desktop_drop` package) — this is one of the most-used LocalSend interactions and isn't in your `pubspec.yaml` today.
5. **Real native notifications.** `flutter_local_notifications` is already a dependency — confirm it's actually initialized and firing for transfer-complete/incoming-request events on both desktop and mobile (this was flagged as unwired in the earlier audit; re-verify once the Accept/Decline dialog from §5.2 is built, since that's the natural place to also fire a notification).
6. **Device grid + progress UI matching LocalSend's visual language**: circular device avatars with signal/type icons, a central "drop zone" card, and a bottom sheet transfer queue with per-file progress bars — these are the recognizable LocalSend UI beats worth mirroring directly since that's the comparison you asked for.

---

## 7. Suggested phase order

Do these roughly in order — later phases depend on earlier ones being real, not just "looking done":

| Phase | Goal | Key deliverables |
|---|---|---|
| **0 — Truth pass** | Stop the doc/code drift | Rewrite `README.md`/`STATUS.md` to describe what's actually implemented today (delete the `app/` Tauri section entirely, remove "0 errors/0 issues" claims unless you can show a green CI run). This costs nothing and prevents you (or anyone else) from being misled by your own docs mid-project. |
| **1 — Security baseline** | Close the open holes | Accept/Decline dialog for incoming transfers (§5.2), Android cleartext fix (§5.3), trusted-device gate for ShanuConnect commands (§3.2) — these are small, self-contained, and remove the worst risk before you build more on top. |
| **2 — Rust bridge, module 1** | Prove the architecture | `flutter_rust_bridge` wired for `core::crypto` only; TLS enabled end-to-end with fingerprint UI (§5.1). |
| **3 — ShanuConnect real pairing + real input** | Make remote control actually work | SAS pairing (§3.1), `enigo`-backed receive handler (§3.3), command allow-list (§3.4). |
| **4 — Scrcpy/ADB production suite** | Kill the "install scrcpy yourself" problem | Binary bootstrap + license consent (§4 step 1), real `adb devices` polling + wireless pairing (§4 step 2), per-device `-s <serial>` targeting, stderr surfaced in UI (§4 step 3). |
| **5 — UI/UX overhaul** | Match LocalSend's feel | Provider/state layer, adaptive nav shell, real theme system, tray icon + custom window chrome + drag-and-drop on desktop (§6). |
| **6 — Protocol completeness + polish** | Round out parity | `download` route for two-way LocalSend (§1), migrate remaining Rust modules (LocalSend/AirDrop/Quick Share) off the Dart duplicates (§2 step 3), delete now-redundant Dart code. |
| **7 — Verified CI** | Make "PASSED" mean something | Real CI matrix that actually builds+tests Windows/macOS/Linux/Android/iOS and fails loudly, replacing the current STATUS.md's unverifiable claims with a live badge that's actually checked on every commit. |

---

## 8. Quick-reference bug/task checklist

- [ ] Fix Android `usesCleartextTraffic`/network-security-config (or ship TLS first and skip this)
- [ ] Add Accept/Decline dialog before writing any incoming LocalSend file (mobile + desktop)
- [ ] Fix `shanu_connect_service.dart` `sendPairing()` to use the real device ID, not `'mobile-remote-id'`
- [ ] Implement SAS pairing crypto + trusted-device persistence
- [ ] Gate all `shanuconnect.*` receive handlers behind the trusted-device check
- [ ] Wire a receive-side handler that calls Rust `enigo` for mousepad/keyboard packets
- [ ] Add binary bootstrap (download+verify+cache) for `adb` and `scrcpy`
- [ ] Replace the static scrcpy device dropdown with real `adb devices -l` polling
- [ ] Pass `-s <serial>` to `scrcpy` launch args
- [ ] Surface scrcpy `stderr` in the UI instead of only `debugPrint`
- [ ] Wire `flutter_rust_bridge` for at least the crypto module; enable TLS by default
- [ ] Rebuild `app_theme.dart` into a real multi-theme system, or stop claiming 5 themes in the README
- [ ] Add adaptive nav shell (replace scattered `Platform.is*` branching in `home_view.dart`)
- [ ] Add system tray + custom window chrome + drag-and-drop for desktop
- [ ] Confirm `flutter_local_notifications` actually fires on real events
- [ ] Rewrite `README.md` / `STATUS.md` to match verified reality
- [ ] Stand up a real CI matrix that builds and tests all five targets

---

*This plan was produced by directly reading `core/` (Rust, 3,458 lines) and `flutter_app/lib/` (Dart, ~4,933 lines) from your upload, cross-referenced against `localsend-main`'s architecture as the UI/UX target. Every claim above is traceable to a specific file — ask if you want line-level detail on any item before starting work on it.*
