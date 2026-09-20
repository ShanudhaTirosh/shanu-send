# Task Checklist: ShanuSend Platform-Aware Feature Separation

- [x] **Desktop App (`app/`) Feature Tailoring**
  - [x] Restructure main Desktop tabs to **File Transfer**, **Screen Mirroring (Scrcpy Host)**, and **KDE Device Hub**
  - [x] Remove upside-down Remote Touchpad Surface from Desktop UI (touchpad input is sent from phone to desktop)
  - [x] Verify `npm run build` in `app/` (0 errors, 2.46s)
  - [x] Verify `cargo check` in `app/src-tauri` (0 errors, 0.52s)

- [x] **Mobile App (`flutter_app/`) Feature Tailoring**
  - [x] Add dedicated **Mobile Remote Touchpad** button in AppBar next to WebDrop
  - [x] Enable 1-tap trackpad controller access for any discovered Desktop PC
  - [x] Verify `flutter analyze` in `flutter_app/` (0 errors, 6.8s)

- [x] **Documentation & System Verification**
  - [x] Update `STATUS.md` with explicit Desktop Host vs Mobile Client feature breakdown
  - [x] Keep all GitHub Actions workflows in `.github/workflows/` disabled with `on: []`
