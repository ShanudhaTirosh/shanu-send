# Task Checklist: ShanuSend Reference Repository Integration & Full Audit Realization

- [x] **Phase 0: Security & Vulnerability Hardening**
  - [x] Restrict `kdeconnect_run_remote_command` in `app/src-tauri/src/commands.rs` to safe allow-list (`lock`, `LockWorkStation`, `ping`)
  - [x] Block unauthenticated arbitrary shell execution
  - [x] Verify `cargo check` in `core/` (0 errors)

- [x] **Phase 0: Real WebDrop Server Binding**
  - [x] Register `/webdrop` and `/api/webdrop/upload` in `build_router()` inside `core/src/server/mod.rs`
  - [x] Remove `dead_code` attributes from `webdrop_page_handler` and `webdrop_upload_handler`
  - [x] Verify browser portal route registration and drop upload logic

- [x] **Phase 1: Scrcpy Pro Suite & ADB Reference Integration (`scrcpy-gui-main`)**
  - [x] Implement real Tauri IPC commands: `scrcpy_check_installed`, `scrcpy_list_adb_devices`, `scrcpy_adb_connect`, `scrcpy_adb_pair`, `scrcpy_start_mirror`
  - [x] Wire real ADB device listing, wireless pairing, and scrcpy process launching into `ScreenMirrorModal.tsx`
  - [x] Verify `cargo check` in `app/src-tauri` (0 errors)

- [x] **Phase 1: Quick Share UKEY2 Handshake Integration (`open-quickshare-main` / `nearby-main`)**
  - [x] Implement real UKEY2 verification PIN derivation (`quickshare_generate_ukey2_pin`) in Rust core and IPC wrapper
  - [x] Wire real UKEY2 crypto PIN generation into `QuickShareModal.tsx`
  - [x] Map BLE `0xFE2C` service UUID and mDNS `_FC92._tcp` service tag in `core/src/quickshare.rs`

- [x] **Phase 1: Complete Documentation & Reference Mapping (`STATUS.md`)**
  - [x] Document reference repos (`localsend-main`, `kdeconnect-kde-master`, `opendrop-master`, `open-quickshare-main`, `scrcpy-gui-main`)
  - [x] Update full technical feature matrix and security audit ledger in `STATUS.md`
  - [x] Verify `npm run build` in `app/` (0 errors, 2.51s)
  - [x] Verify `flutter analyze` in `flutter_app/` (0 errors, 9.3s)
