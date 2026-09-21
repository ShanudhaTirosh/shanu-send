# ShanuSend v2.5.4 Release Notes 🚀

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

