# ShanuSend Release Notes 🚀

---

### v2.5.5 — Bug-fix pass (pairing, remote control, scrcpy setup)

This release fixes gaps found in a direct source audit — see `IMPLEMENTATION_PLAN.md` for the full findings. Previous
release notes below describe the UI/feature surface as it existed at the time; some of what they call "zero mock"
had gaps this pass closes:

- **Pairing**: `shanu_connect_view.dart` and `desktop_phone_link_view.dart` previously accepted *any* typed 6-digit
  number as a valid pairing PIN, with no verification. Replaced with a real generate-and-mutually-confirm flow, plus
  a persisted trusted-device allow-list (`trusted_device_store.dart`).
- **Device identity**: every install previously broadcast one of three different hardcoded literal device IDs
  (`'mobile-remote-id'`, `'desktop-host-id'`, `'trackpad-remote-id'`) — meaning every phone looked identical to every
  other phone for trust purposes. Replaced with a real persisted per-install UUID (`device_identity_service.dart`).
- **Remote cursor control**: the desktop host never had a handler for incoming `shanuconnect.mousepad` packets at
  all — the trackpad view sent them, but nothing on the receiving end acted on them. Added real cursor control
  (`native_input_service.dart`: direct Win32 calls on Windows, `cliclick`/`xdotool` on macOS/Linux), gated behind the
  new trusted-device check.
- **Trackpad buttons**: Left/Right Click, Next/Prev Slide, and Play/Pause previously only updated local UI text and
  sent nothing. They now send real packets.
- **Scrcpy/ADB**: the device picker was a single hardcoded placeholder string, and launching scrcpy assumed it was
  already on the system PATH. Added real `adb devices -l` polling, wireless ADB pairing, and a one-time setup flow
  that downloads and caches `adb`/`scrcpy` (Windows) instead of failing silently when they're not preinstalled.
- **Incoming transfers**: `prepare-upload` previously wrote incoming files to disk immediately with no user
  confirmation. Added a real Accept/Decline prompt that the transfer now blocks on.
- **Android cleartext HTTP**: added a network security config — LAN transfers were likely failing silently on
  Android 9+ (API 28+) without it.

---

### v2.5.4

Universal High-Speed File Sharing, Unified WebDrop Single-Port Engine, Phone Link Host Hub (Zero Mock Data), Native ScrcpyGUI Suite, 6-Digit SAS PIN Device Hub, and Cross-Platform Flutter Release.

---

### ✨ Highlights of v2.5.4

#### 🌐 1. Unified WebDrop Single-Port Architecture (`UnifiedHttpServer`)
- **Port Collision Resolution**: Unified LocalSend v2.1 routes (`/api/localsend/v2/*`) and WebDrop HTML5 browser sharing portal onto a single HTTP listener on port `53317`.
- **Zero-Install Web Portal**: Serving browser upload/download portal at `http://<IP>:53317` and `http://<IP>:53317/webdrop` directly without external tools.
- **Eliminated `Route not found`**: Standard browser requests (`GET /`, `GET /webdrop`) render the interactive WebDrop portal cleanly.

#### 📱 2. Desktop Phone Link Host Hub (`desktop_phone_link_view.dart`)
- **Zero Mock Data Architecture**: Removed all hardcoded dummy arrays and replaced them with live reactive stream listeners for `shanuconnect` UDP/TCP packets.
- **Synced Notifications**: Live mirrored phone notification stream with inline quick reply action.
- **SMS & Call Management**: View phone SMS messages and send SMS replies directly from desktop workstation; incoming call alert cards.
- **Phone Status Cards**: Live battery % and charging indicator, Wi-Fi connectivity status, and remote phone ringer trigger (`Find Phone`).
- **Bidirectional Clipboard Auto-Sync**: Text copied on mobile or desktop syncs automatically across devices.

#### 🎥 3. Native ScrcpyGUI Suite (`scrcpy_gui_view.dart`)
- **ADB Device Discovery**: Auto-detects USB and Wireless ADB devices.
- **Resolution & Stream Customization**: Switch between 720p, 1080p, and native source resolutions; tune FPS caps (30/60) and bitrates (2-16 Mbps).
- **Display & Recording Toggles**: Stay Awake during display mirror, turn off phone screen during mirror, and record stream to MP4.

#### 🔒 4. Integrated Device Hub & SAS PIN Authentication
- **Top Device Switcher**: Continuous LAN discovery stream populates a top device selector dropdown on both mobile and desktop controllers.
- **6-Digit SAS PIN Confirmation Prompt**: Trigger 6-digit Short Authentication String (SAS) security PIN dialog to authorize paired remote control sessions.

---

### 📦 Build & Installer Artifacts

- **Windows Native Release Executable**: `shanu_send_flutter.exe` (`build\windows\x64\runner\Release\shanu_send_flutter.exe`)
- **Windows Installer (NSIS)**: `ShanuSend_2.5.4_x64-setup.exe`
- **Android App**: `app-release.apk`

