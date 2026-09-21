use crate::state::AppState;
use serde::{Deserialize, Serialize};
use serde_json::json;
use shanusend_core::discovery;
use shanusend_core::models::{Device, RegisterDto};
use shanusend_core::scrcpy::ScrcpyConfig;
use shanusend_core::transfer::{self, LocalFile, SendEvent};
use std::collections::HashMap;
use std::path::Path;
use std::process::{Command as StdCommand, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tauri::{AppHandle, Emitter, Manager, State, Window};
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command as TokioCommand;
use tokio::time::{timeout, Duration};
use flate2::read::GzDecoder;
use tar::Archive;

#[cfg(target_os = "windows")]
use std::os::windows::process::CommandExt;

pub struct ScrcpyState {
    pub processes: std::sync::Mutex<HashMap<String, tokio::process::Child>>,
    pub active_device: std::sync::Mutex<Option<String>>,
    pub final_capture_hint: std::sync::Mutex<HashMap<String, (i32, i32)>>,
}

const AUDIO_FALLBACK_CHAIN: &[&str] = &["aac", "flac", "raw"];

fn is_audio_codec_error(text: &str) -> bool {
    let lower = text.to_lowercase();
    if lower.contains("could not create default audio encoder")
        || lower.contains("failed to initialize audio")
    {
        return true;
    }
    let mentions_codec = lower.contains("audio encoder") || lower.contains("audio codec");
    let mentions_failure = lower.contains("fail")
        || lower.contains("error")
        || lower.contains("could not")
        || lower.contains("not available")
        || lower.contains("not supported");
    mentions_codec && mentions_failure
}

fn get_binary_path(binary_name: &str, custom_folder: Option<String>) -> String {
    let exe_ext = std::env::consts::EXE_EXTENSION;
    let binary_filename = if exe_ext.is_empty() {
        binary_name.to_string()
    } else {
        format!("{}.{}", binary_name, exe_ext)
    };

    if let Some(folder) = custom_folder {
        if !folder.trim().is_empty() {
            let full_path = Path::new(&folder).join(&binary_filename);
            if full_path.exists() && full_path.is_file() {
                return full_path.to_string_lossy().to_string();
            }
        }
    }

    if let Ok(exe_path) = std::env::current_exe() {
        if let Some(exe_dir) = exe_path.parent() {
            let local_bin = exe_dir.join("scrcpy-bin").join(&binary_filename);
            if local_bin.exists() && local_bin.is_file() {
                return local_bin.to_string_lossy().to_string();
            }
        }
    }

    if let Ok(current_dir) = std::env::current_dir() {
        let local_bin = current_dir.join("scrcpy-bin").join(&binary_filename);
        if local_bin.exists() && local_bin.is_file() {
            return local_bin.to_string_lossy().to_string();
        }
    }

    binary_name.to_string()
}

fn copy_dir_all(src: impl AsRef<Path>, dst: impl AsRef<Path>) -> std::io::Result<()> {
    let src_ref = src.as_ref();
    let dst_ref = dst.as_ref();

    let canonical_dst = if dst_ref.exists() {
        dst_ref.canonicalize()?
    } else {
        std::fs::create_dir_all(dst_ref)?;
        dst_ref.canonicalize()?
    };

    for entry in std::fs::read_dir(src_ref)? {
        let entry = entry?;
        let entry_path = entry.path();
        let file_name = entry.file_name();

        let file_name_str = file_name.to_string_lossy();
        if file_name_str.contains("..") || file_name_str.contains('/') || file_name_str.contains('\\') {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "Directory entry contains directory traversal components",
            ));
        }

        let target_path = dst_ref.join(&file_name);
        if let Some(parent_dir) = target_path.parent() {
            if parent_dir.exists() {
                let canonical_parent = parent_dir.canonicalize()?;
                if !canonical_parent.starts_with(&canonical_dst) && canonical_parent != canonical_dst {
                    return Err(std::io::Error::new(
                        std::io::ErrorKind::PermissionDenied,
                        "Path traversal attempt detected during directory copy",
                    ));
                }
            }
        }

        let ty = entry.file_type()?;
        if ty.is_dir() {
            copy_dir_all(&entry_path, &target_path)?;
        } else {
            std::fs::copy(&entry_path, &target_path)?;
        }
    }
    Ok(())
}

#[cfg(target_os = "windows")]
const CREATE_NO_WINDOW: u32 = 0x08000000;

fn create_command<S: AsRef<std::ffi::OsStr>>(program: S) -> TokioCommand {
    let cmd = TokioCommand::new(program);
    #[cfg(target_os = "windows")]
    {
        let mut cmd = cmd;
        cmd.creation_flags(CREATE_NO_WINDOW);
        cmd
    }
    #[cfg(not(target_os = "windows"))]
    cmd
}

/// Mirrors `lib/tauri.ts`'s `LocalFileInput` shape on the frontend.
#[derive(Debug, Deserialize)]
pub struct LocalFileInput {
    pub id: String,
    pub path: String,
    pub file_name: String,
    pub size: u64,
    pub mime: String,
}

#[derive(Debug, Serialize)]
pub struct SelfInfo {
    pub alias: String,
    pub fingerprint: String,
    pub port: u16,
    pub local_ip: String,
}

pub fn get_system_local_ip() -> String {
    if let Ok(ip) = local_ip_address::local_ip() {
        return ip.to_string();
    }
    if let Ok(socket) = std::net::UdpSocket::bind("0.0.0.0:0") {
        if socket.connect("8.8.8.8:80").is_ok() {
            if let Ok(addr) = socket.local_addr() {
                return addr.ip().to_string();
            }
        }
    }
    "127.0.0.1".to_string()
}

#[tauri::command]
pub fn get_self_info(state: State<AppState>) -> SelfInfo {
    SelfInfo {
        alias: state.server.device.alias.clone(),
        fingerprint: state.server.device.fingerprint.clone(),
        port: state.port,
        local_ip: get_system_local_ip(),
    }
}

#[tauri::command]
pub async fn refresh_discovery(state: State<'_, AppState>) -> Result<(), String> {
    let dto = discovery::build_self_announcement(
        &state.server.device.alias,
        &state.server.device.fingerprint,
        state.port,
        false,
        state.server.device.device_model.clone(),
        state.server.device.device_type,
        true,
    );
    discovery::announce(&dto).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn send_files(
    app: AppHandle,
    state: State<'_, AppState>,
    target: Device,
    files: Vec<LocalFileInput>,
) -> Result<(), String> {
    let self_info = RegisterDto {
        alias: state.server.device.alias.clone(),
        version: Some("2.1".to_string()),
        device_model: state.server.device.device_model.clone(),
        device_type: Some(state.server.device.device_type),
        fingerprint: state.server.device.fingerprint.clone(),
        port: Some(state.port),
        protocol: Some(shanusend_core::models::ProtocolType::Http),
        download: Some(false),
    };

    let mut local_files: Vec<LocalFile> = Vec::new();
    let mut file_meta: HashMap<String, (String, u64, String)> = HashMap::new();

    for f in files {
        let path_buf = std::path::PathBuf::from(&f.path);
        let mut actual_size = f.size;

        if let Ok(meta) = std::fs::metadata(&path_buf) {
            actual_size = meta.len();
        }

        file_meta.insert(f.id.clone(), (f.file_name.clone(), actual_size, f.path.clone()));
        local_files.push(LocalFile {
            id: f.id,
            path: path_buf,
            file_name: f.file_name,
            size: actual_size,
            mime: f.mime,
        });
    }

    let (tx, mut rx) = tokio::sync::mpsc::channel::<SendEvent>(64);
    let app_for_forward = app.clone();
    let target_alias = target.alias.clone();
    let history_path = state.history_path.clone();

    let forward_task = tokio::spawn(async move {
        while let Some(event) = rx.recv().await {
            match &event {
                SendEvent::FileDone { file_id } => {
                    if let Some((file_name, size, path)) = file_meta.get(file_id) {
                        let record = shanusend_core::history::TransferRecord::new(
                            shanusend_core::history::Direction::Sent,
                            target_alias.clone(),
                            file_name.clone(),
                            *size,
                            shanusend_core::history::RecordStatus::Done,
                            Some(path.clone()),
                        );
                        let _ = shanusend_core::history::append(&history_path, record).await;
                    }
                }
                SendEvent::FileFailed { file_id, .. } => {
                    if let Some((file_name, size, path)) = file_meta.get(file_id) {
                        let record = shanusend_core::history::TransferRecord::new(
                            shanusend_core::history::Direction::Sent,
                            target_alias.clone(),
                            file_name.clone(),
                            *size,
                            shanusend_core::history::RecordStatus::Failed,
                            Some(path.clone()),
                        );
                        let _ = shanusend_core::history::append(&history_path, record).await;
                    }
                }
                _ => {}
            }
            let _ = app_for_forward.emit("send-progress", &event);
        }
    });

    transfer::send_files(target, self_info, local_files, None, tx).await;
    let _ = forward_task.await;

    Ok(())
}

#[tauri::command]
pub async fn respond_prepare_upload(
    state: State<'_, AppState>,
    session_id: String,
    accepted_file_ids: Option<Vec<String>>,
) -> Result<(), String> {
    state
        .server
        .respond_prepare_upload(&session_id, accepted_file_ids)
        .await;
    Ok(())
}

#[derive(Debug, Serialize)]
pub struct Settings {
    pub alias: String,
    pub save_dir: String,
    pub pin_enabled: bool,
    pub trusted_fingerprints: Vec<String>,
}

#[tauri::command]
pub async fn get_settings(state: State<'_, AppState>) -> Result<Settings, String> {
    Ok(Settings {
        alias: state.server.device.alias.clone(),
        save_dir: state
            .server
            .get_save_dir()
            .await
            .to_string_lossy()
            .to_string(),
        pin_enabled: state.server.pin_enabled().await,
        trusted_fingerprints: state.server.list_trusted().await,
    })
}

#[tauri::command]
pub async fn set_pin(state: State<'_, AppState>, pin: Option<String>) -> Result<(), String> {
    let normalized = pin.filter(|p| !p.trim().is_empty());
    state.server.set_pin(normalized).await;
    Ok(())
}

#[tauri::command]
pub async fn set_save_dir(state: State<'_, AppState>, path: String) -> Result<(), String> {
    state
        .server
        .set_save_dir(std::path::PathBuf::from(path))
        .await;
    Ok(())
}

#[tauri::command]
pub async fn set_device_trusted(
    state: State<'_, AppState>,
    fingerprint: String,
    trusted: bool,
) -> Result<(), String> {
    if trusted {
        state.server.trust_device(fingerprint).await;
    } else {
        state.server.untrust_device(&fingerprint).await;
    }
    Ok(())
}

#[tauri::command]
pub fn rename_device(app: AppHandle, new_alias: String) -> Result<(), String> {
    let dir = app.path().app_data_dir().map_err(|e| e.to_string())?;
    std::fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    std::fs::write(dir.join("alias.txt"), new_alias.trim()).map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn list_history(
    state: State<'_, AppState>,
) -> Result<Vec<shanusend_core::history::TransferRecord>, String> {
    Ok(shanusend_core::history::list(&state.history_path).await)
}

#[tauri::command]
pub async fn clear_history(state: State<'_, AppState>) -> Result<(), String> {
    shanusend_core::history::clear(&state.history_path)
        .await
        .map_err(|e| e.to_string())
}

// --- KDEConnect & ShanuConnect Commands ---

#[tauri::command]
pub async fn kdeconnect_send_mousepad(
    state: State<'_, AppState>,
    dx: Option<f32>,
    dy: Option<f32>,
    click: Option<String>,
) -> Result<(), String> {
    let packet = shanusend_core::kdeconnect::KdePacket::new(
        "kdeconnect.mousepad",
        serde_json::json!({ "dx": dx, "dy": dy, "click": click }),
    );
    let _ = state.kde_engine.process_incoming_packet(packet).await;
    Ok(())
}

#[tauri::command]
pub async fn kdeconnect_trigger_find_phone(
    state: State<'_, AppState>,
    ring: bool,
) -> Result<(), String> {
    let packet = shanusend_core::kdeconnect::KdePacket::new(
        "kdeconnect.findmyphone",
        serde_json::json!({ "ring": ring }),
    );
    let _ = state.kde_engine.process_incoming_packet(packet).await;
    Ok(())
}

#[tauri::command]
pub async fn kdeconnect_lock_device(
    state: State<'_, AppState>,
    locked: bool,
) -> Result<(), String> {
    let packet = shanusend_core::kdeconnect::KdePacket::new(
        "kdeconnect.lockdevice",
        serde_json::json!({ "isLocked": locked }),
    );
    let _ = state.kde_engine.process_incoming_packet(packet).await;
    if locked {
        #[cfg(target_os = "windows")]
        {
            let _ = StdCommand::new("rundll32.exe")
                .args(["user32.dll,LockWorkStation"])
                .spawn();
        }
    }
    Ok(())
}

#[tauri::command]
pub async fn kdeconnect_run_remote_command(
    state: State<'_, AppState>,
    command: String,
) -> Result<String, String> {
    let packet = shanusend_core::kdeconnect::KdePacket::new(
        "kdeconnect.runcommand",
        serde_json::json!({ "key": command }),
    );
    let _ = state.kde_engine.process_incoming_packet(packet).await;
    match command.trim() {
        "lock" | "LockWorkStation" => {
            #[cfg(target_os = "windows")]
            {
                let _ = StdCommand::new("rundll32.exe")
                    .args(["user32.dll,LockWorkStation"])
                    .spawn();
            }
            Ok("Screen locked successfully".to_string())
        }
        "ping" => Ok("pong".to_string()),
        _ => Err("Command execution restricted to pre-approved allow-list for security.".to_string()),
    }
}

#[tauri::command]
pub async fn kdeconnect_send_sms(
    state: State<'_, AppState>,
    recipient: String,
    body: String,
) -> Result<(), String> {
    let packet = shanusend_core::kdeconnect::KdePacket::new(
        "kdeconnect.sms",
        serde_json::json!({ "sendTo": recipient, "sendBody": body }),
    );
    let _ = state.kde_engine.process_incoming_packet(packet).await;
    Ok(())
}

#[tauri::command]
pub async fn kdeconnect_mpris_control(
    state: State<'_, AppState>,
    action: String,
    volume: Option<i32>,
) -> Result<(), String> {
    let packet = shanusend_core::shanuconnect::ShanuPacket::new(
        "shanuconnect.mpris",
        serde_json::json!({ "player": "ShanuSendPlayer", "action": action, "volume": volume }),
    );
    let _ = state.kde_engine.process_incoming_packet(packet).await;
    Ok(())
}

#[tauri::command]
pub async fn shanuconnect_send_mousepad(
    state: State<'_, AppState>,
    dx: Option<f32>,
    dy: Option<f32>,
    click: Option<String>,
) -> Result<(), String> {
    kdeconnect_send_mousepad(state, dx, dy, click).await
}

#[tauri::command]
pub async fn shanuconnect_trigger_find_phone(
    state: State<'_, AppState>,
    ring: bool,
) -> Result<(), String> {
    kdeconnect_trigger_find_phone(state, ring).await
}

#[tauri::command]
pub async fn shanuconnect_lock_device(
    state: State<'_, AppState>,
    locked: bool,
) -> Result<(), String> {
    kdeconnect_lock_device(state, locked).await
}

#[tauri::command]
pub async fn shanuconnect_run_remote_command(
    state: State<'_, AppState>,
    command: String,
) -> Result<String, String> {
    kdeconnect_run_remote_command(state, command).await
}

#[tauri::command]
pub async fn shanuconnect_send_sms(
    state: State<'_, AppState>,
    recipient: String,
    body: String,
) -> Result<(), String> {
    kdeconnect_send_sms(state, recipient, body).await
}

#[tauri::command]
pub async fn shanuconnect_mpris_control(
    state: State<'_, AppState>,
    action: String,
    volume: Option<i32>,
) -> Result<(), String> {
    kdeconnect_mpris_control(state, action, volume).await
}

#[tauri::command]
pub async fn shanuconnect_send_system_volume(
    state: State<'_, AppState>,
    volume: i32,
) -> Result<(), String> {
    let packet = shanusend_core::shanuconnect::ShanuPacket::new(
        "shanuconnect.systemvolume",
        serde_json::json!({ "volume": volume }),
    );
    let _ = state.kde_engine.process_incoming_packet(packet).await;
    Ok(())
}

#[tauri::command]
pub async fn shanuconnect_send_clipboard(
    state: State<'_, AppState>,
    content: String,
) -> Result<(), String> {
    let packet = shanusend_core::shanuconnect::ShanuPacket::new(
        "shanuconnect.clipboard",
        serde_json::json!({ "content": content }),
    );
    let _ = state.kde_engine.process_incoming_packet(packet).await;
    Ok(())
}

#[tauri::command]
pub async fn shanuconnect_send_pair(
    state: State<'_, AppState>,
    pair: bool,
) -> Result<(), String> {
    let packet = shanusend_core::shanuconnect::ShanuPacket::new(
        "shanuconnect.pair",
        serde_json::json!({ "pair": pair }),
    );
    let _ = state.kde_engine.process_incoming_packet(packet).await;
    Ok(())
}

#[tauri::command]
pub async fn shanuconnect_reply_notification(
    state: State<'_, AppState>,
    notification_id: String,
    reply_message: String,
) -> Result<(), String> {
    let packet = shanusend_core::shanuconnect::ShanuPacket::new(
        "shanusend.notifications.reply",
        serde_json::json!({
            "notificationId": notification_id,
            "replyMessage": reply_message
        }),
    );
    let _ = state.kde_engine.process_incoming_packet(packet).await;
    Ok(())
}

#[tauri::command]
pub async fn shanuconnect_telephony_action(
    state: State<'_, AppState>,
    action: String,
    phone_number: Option<String>,
    message: Option<String>,
) -> Result<(), String> {
    let packet = shanusend_core::shanuconnect::ShanuPacket::new(
        "shanuconnect.telephony.action",
        serde_json::json!({
            "action": action,
            "phoneNumber": phone_number,
            "message": message
        }),
    );
    let _ = state.kde_engine.process_incoming_packet(packet).await;
    Ok(())
}

#[tauri::command]
pub async fn shanuconnect_request_sftp(
    state: State<'_, AppState>,
    path: Option<String>,
) -> Result<(), String> {
    let packet = shanusend_core::shanuconnect::ShanuPacket::new(
        "shanuconnect.sftp",
        serde_json::json!({ "startBrowsing": true, "path": path.unwrap_or_else(|| "/storage/emulated/0".to_string()) }),
    );
    let _ = state.kde_engine.process_incoming_packet(packet).await;
    Ok(())
}

// --- QuickShare & WebDrop Commands ---

#[tauri::command]
pub async fn quickshare_generate_ukey2_pin(state: State<'_, AppState>) -> Result<String, String> {
    let fingerprint = &state.server.device.fingerprint;
    let pin = shanusend_core::quickshare::Ukey2HandshakeFrame::generate_verification_pin(fingerprint.as_bytes());
    Ok(pin)
}

#[tauri::command]
pub async fn webdrop_share_files(
    state: State<'_, AppState>,
    paths: Vec<String>,
) -> Result<usize, String> {
    let mut added = 0;
    for path_str in paths {
        let path = std::path::PathBuf::from(&path_str);
        if let Ok(meta) = std::fs::metadata(&path) {
            let name = path
                .file_name()
                .map(|s| s.to_string_lossy().to_string())
                .unwrap_or_else(|| "shared_file.bin".to_string());
            state.server.add_shared_file(name, path, meta.len()).await;
            added += 1;
        }
    }
    Ok(added)
}

#[tauri::command]
pub async fn webdrop_get_shared_files(
    state: State<'_, AppState>,
) -> Result<Vec<shanusend_core::server::WebDropSharedFile>, String> {
    Ok(state.server.get_shared_files().await)
}

#[tauri::command]
pub async fn webdrop_clear_shared_files(state: State<'_, AppState>) -> Result<(), String> {
    state.server.clear_shared_files().await;
    Ok(())
}

// --- ScrcpyGUI v4 Complete Suite Commands ---

const KNOWN_ADB_STATES: &[&str] = &[
    "device",
    "offline",
    "unauthorized",
    "authorizing",
    "unknown",
    "bootloader",
    "recovery",
    "sideload",
    "host",
    "connecting",
];

fn parse_adb_device_line(line: &str) -> Option<(String, String)> {
    let tokens: Vec<&str> = line.split_whitespace().collect();
    let state_idx = tokens.iter().position(|t| KNOWN_ADB_STATES.contains(t))?;
    if state_idx == 0 {
        return None;
    }
    Some((tokens[..state_idx].join(" "), tokens[state_idx].to_string()))
}

fn extract_device_model(line: &str) -> Option<String> {
    let model = line
        .split_whitespace()
        .find_map(|t| t.strip_prefix("model:"))?;
    if model.is_empty() {
        return None;
    }
    Some(model.replace('_', " "))
}

#[tauri::command]
pub async fn check_scrcpy(custom_path: Option<String>) -> serde_json::Value {
    let exe_path = get_binary_path("scrcpy", custom_path);
    let output = create_command(&exe_path)
        .arg("--version")
        .output()
        .await;

    match output {
        Ok(o) if o.status.success() => json!({ "found": true, "message": "Scrcpy Ready" }),
        Ok(_) => json!({ "found": false, "message": "Failed to start scrcpy (Exit Code != 0)" }),
        Err(_) => json!({ "found": false, "message": "Scrcpy not found" }),
    }
}

#[tauri::command]
pub async fn get_devices(custom_path: Option<String>) -> serde_json::Value {
    let adb_path = get_binary_path("adb", custom_path);
    let output = create_command(&adb_path)
        .arg("devices")
        .arg("-l")
        .output()
        .await;

    match output {
        Ok(o) => {
            if o.status.success() {
                let out_str = String::from_utf8_lossy(&o.stdout);
                let mut devices: Vec<String> = Vec::new();
                let mut device_models = serde_json::Map::new();
                for line in out_str.lines().skip(1) {
                    let Some((serial, state)) = parse_adb_device_line(line) else { continue };
                    if state != "device" {
                        continue;
                    }
                    if let Some(model) = extract_device_model(line) {
                        device_models.insert(serial.clone(), json!(model));
                    }
                    devices.push(serial);
                }
                json!({ "error": false, "devices": devices, "deviceModels": device_models })
            } else {
                json!({ "error": true, "message": "ADB returned error" })
            }
        }
        Err(e) => json!({ "error": true, "message": e.to_string() }),
    }
}

#[tauri::command]
pub async fn get_mdns_devices(custom_path: Option<String>) -> serde_json::Value {
    let adb_path = get_binary_path("adb", custom_path);
    let output = create_command(&adb_path)
        .arg("mdns")
        .arg("services")
        .output()
        .await;

    match output {
        Ok(o) => {
            if o.status.success() {
                let out_str = String::from_utf8_lossy(&o.stdout);
                let mut services = Vec::new();
                let mut seen = std::collections::HashSet::new();
                for line in out_str.lines().skip(1) {
                    let parts: Vec<&str> = line.split('\t').collect();
                    if parts.len() >= 3 {
                        let name = parts[0].trim();
                        let service = parts[1].trim();
                        let address = parts[2].trim();
                        let key = format!("{}|{}|{}", name, service, address);
                        if !seen.contains(&key) {
                            services.push(json!({
                                "name": name,
                                "service": service,
                                "address": address
                            }));
                            seen.insert(key);
                        }
                    }
                }
                json!({ "error": false, "services": services })
            } else {
                json!({ "error": true, "message": "ADB mdns returned error" })
            }
        }
        Err(e) => json!({ "error": true, "message": e.to_string() }),
    }
}

#[tauri::command]
pub async fn adb_connect(window: Window, ip: String, custom_path: Option<String>, silent: Option<bool>) -> Result<serde_json::Value, String> {
    let silent = silent.unwrap_or(false);
    let adb_path = get_binary_path("adb", custom_path);
    if !silent {
        let _ = window.emit("scrcpy-log", format!("[SYSTEM] Attempting wireless connection to {}...", ip));
    }

    let child = create_command(&adb_path)
        .arg("connect")
        .arg(&ip)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|e| format!("Failed to start adb connect: {}", e))?;

    let output_res = timeout(Duration::from_secs(5), child.wait_with_output()).await;

    match output_res {
        Ok(Ok(output)) => {
            let out_text = String::from_utf8_lossy(&output.stdout).trim().to_string();
            let err_text = String::from_utf8_lossy(&output.stderr).trim().to_string();

            if !silent {
                if !out_text.is_empty() { let _ = window.emit("scrcpy-log", format!("[ADB] {}", out_text)); }
                if !err_text.is_empty() { let _ = window.emit("scrcpy-log", format!("[ADB ERROR] {}", err_text)); }
            }

            let success = output.status.success() && !out_text.contains("cannot connect") && !out_text.contains("failed");
            Ok(json!({ "success": success, "message": if out_text.is_empty() { err_text } else { out_text } }))
        }
        Ok(Err(e)) => Err(e.to_string()),
        Err(_) => {
            if !silent {
                let _ = window.emit("scrcpy-log", format!("[SYSTEM] Connection to {} timed out after 5s.", ip));
            }
            Ok(json!({ "success": false, "message": "connection timed out" }))
        }
    }
}

#[tauri::command]
pub async fn adb_pair(window: Window, ip: String, code: String, custom_path: Option<String>) -> Result<serde_json::Value, String> {
    let adb_path = get_binary_path("adb", custom_path);
    let _ = window.emit("scrcpy-log", format!("[SYSTEM] Pairing with {}...", ip));

    let output = create_command(&adb_path)
        .arg("pair")
        .arg(&ip)
        .arg(&code)
        .output()
        .await
        .map_err(|e| e.to_string())?;

    let out_text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let err_text = String::from_utf8_lossy(&output.stderr).trim().to_string();

    if !out_text.is_empty() { let _ = window.emit("scrcpy-log", format!("[ADB] {}", out_text)); }
    if !err_text.is_empty() { let _ = window.emit("scrcpy-log", format!("[ADB ERROR] {}", err_text)); }

    let success = output.status.success() && (out_text.contains("Successfully paired") || err_text.contains("Successfully paired"));

    Ok(json!({ "success": success, "message": if out_text.is_empty() { err_text } else { out_text } }))
}

#[tauri::command]
pub async fn adb_shell(device: String, command: String, custom_path: Option<String>) -> serde_json::Value {
    let adb_path = get_binary_path("adb", custom_path);
    let output = create_command(&adb_path)
        .arg("-s")
        .arg(&device)
        .arg("shell")
        .arg(&command)
        .output()
        .await;

    match output {
        Ok(o) => json!({ "success": o.status.success(), "output": String::from_utf8_lossy(&o.stdout).to_string() }),
        Err(e) => json!({ "success": false, "message": e.to_string() }),
    }
}

#[tauri::command]
pub async fn run_terminal_command(device: Option<String>, cmd: String, custom_path: Option<String>) -> serde_json::Value {
    let mut parts = split_args(&cmd).unwrap_or_else(|_| cmd.split_whitespace().map(|s| s.to_string()).collect());
    if parts.is_empty() { return json!({ "success": false, "message": "No command provided" }); }

    let first_part = parts[0].to_lowercase();
    let is_scrcpy = first_part == "scrcpy";
    let is_adb = first_part == "adb";

    let binary_name = if is_scrcpy { "scrcpy" } else { "adb" };
    let exe_path = get_binary_path(binary_name, custom_path);

    if is_adb || is_scrcpy {
        parts.remove(0);
    }

    let mut args = Vec::new();
    let has_serial_flag = parts.contains(&"-s".to_string()) || parts.contains(&"--serial".to_string());

    if !has_serial_flag {
        if let Some(ref d) = device {
            if !d.is_empty() {
                let is_global_adb = binary_name == "adb" && !parts.is_empty() && (parts[0] == "devices" || parts[0] == "connect" || parts[0] == "pair");
                if !is_global_adb {
                    args.push("-s".to_string());
                    args.push(d.clone());
                }
            }
        }
    }

    for part in parts {
        args.push(part);
    }

    let output = create_command(&exe_path)
        .args(&args)
        .output()
        .await;

    match output {
        Ok(o) => json!({ 
            "success": o.status.success(), 
            "binary": binary_name,
            "stdout": String::from_utf8_lossy(&o.stdout).to_string(),
            "stderr": String::from_utf8_lossy(&o.stderr).to_string()
        }),
        Err(e) => json!({ "success": false, "message": e.to_string() }),
    }
}

fn split_args(s: &str) -> Result<Vec<String>, String> {
    let mut args = Vec::new();
    let mut current = String::new();
    let mut in_quotes = false;

    for c in s.chars() {
        if c == '"' {
            in_quotes = !in_quotes;
        } else if c.is_whitespace() && !in_quotes {
            if !current.is_empty() {
                args.push(current.clone());
                current.clear();
            }
        } else {
            current.push(c);
        }
    }
    if !current.is_empty() {
        args.push(current);
    }
    if in_quotes {
        return Err("Unclosed quotes".to_string());
    }
    Ok(args)
}

#[tauri::command]
pub async fn push_file(device: String, file_path: String, custom_path: Option<String>) -> serde_json::Value {
    let adb_path = get_binary_path("adb", custom_path);
    let output = create_command(&adb_path)
        .arg("-s")
        .arg(&device)
        .arg("push")
        .arg(&file_path)
        .arg("/sdcard/Download/")
        .output()
        .await;

    match output {
        Ok(o) => {
            if o.status.success() {
                json!({ "success": true, "message": "File pushed to Downloads" })
            } else {
                json!({ "success": false, "message": "Transfer failed" })
            }
        }
        Err(e) => json!({ "success": false, "message": e.to_string() }),
    }
}

#[tauri::command]
pub async fn install_apk(device: String, file_path: String, custom_path: Option<String>) -> serde_json::Value {
    let adb_path = get_binary_path("adb", custom_path);
    let output = create_command(&adb_path)
        .arg("-s")
        .arg(&device)
        .arg("install")
        .arg(&file_path)
        .output()
        .await;

    match output {
        Ok(o) => {
            let out_text = String::from_utf8_lossy(&o.stdout);
            let err_text = String::from_utf8_lossy(&o.stderr);
            if o.status.success() {
                json!({ "success": true, "message": out_text.trim() })
            } else {
                json!({ "success": false, "message": err_text.trim() })
            }
        }
        Err(e) => json!({ "success": false, "message": e.to_string() }),
    }
}

#[tauri::command]
pub async fn kill_adb(window: Window, custom_path: Option<String>) -> Result<serde_json::Value, String> {
    let adb_path = get_binary_path("adb", custom_path);
    let _ = window.emit("scrcpy-log", "[SYSTEM] Terminating ADB stack...".to_string());

    let mut child = create_command(&adb_path)
        .arg("kill-server")
        .spawn()
        .map_err(|e| e.to_string())?;

    let _ = child.wait().await;

    #[cfg(target_os = "windows")]
    {
        let _ = TokioCommand::new("taskkill")
            .args(&["/F", "/IM", "adb.exe", "/T"])
            .creation_flags(CREATE_NO_WINDOW)
            .output()
            .await;
    }

    #[cfg(not(target_os = "windows"))]
    {
        let _ = TokioCommand::new("pkill")
            .arg("adb")
            .output()
            .await;
    }

    let _ = window.emit("scrcpy-log", "[SYSTEM] ADB Stack Terminated.".to_string());
    Ok(json!({ "success": true, "message": "ADB Stack Terminated" }))
}

#[tauri::command]
pub async fn list_scrcpy_options(device: String, arg: String, custom_path: Option<String>) -> serde_json::Value {
    let exe_path = get_binary_path("scrcpy", custom_path);
    let mut command = create_command(&exe_path);
    command.arg("-s").arg(&device).arg(&arg);
    let output = command.output().await;

    match output {
        Ok(o) => {
            let out_text = String::from_utf8_lossy(&o.stdout);
            let err_text = String::from_utf8_lossy(&o.stderr);
            let combined = format!("{}{}", out_text, err_text);
            json!({ "success": o.status.success(), "output": combined })
        }
        Err(e) => json!({ "success": false, "message": e.to_string() }),
    }
}

fn detect_host_os() -> &'static str {
    if cfg!(target_os = "windows") {
        "windows"
    } else if cfg!(target_os = "macos") {
        "macos"
    } else if cfg!(target_os = "linux") {
        "linux"
    } else {
        "unknown"
    }
}

fn render_driver_label(driver: &str) -> String {
    match driver {
        "direct3d" => "D3D11 (Direct3D)".to_string(),
        "opengl" => "OpenGL".to_string(),
        "opengles2" => "OpenGL ES 2.0".to_string(),
        "metal" => "Metal".to_string(),
        "software" => "Software (CPU)".to_string(),
        _ => driver.to_string(),
    }
}

#[tauri::command]
pub async fn get_render_drivers(custom_path: Option<String>) -> serde_json::Value {
    let host_os = detect_host_os();
    let exe_path = get_binary_path("scrcpy", custom_path);
    let output = create_command(&exe_path).arg("--help").output().await;

    match output {
        Ok(o) => {
            let stdout = String::from_utf8_lossy(&o.stdout);
            let stderr = String::from_utf8_lossy(&o.stderr);
            let combined = format!("{}\n{}", stdout, stderr);

            let driver_line = combined.lines().find(|l| l.contains("--render-driver"));
            let detected_drivers: Vec<String> = if let Some(line) = driver_line {
                let parts: Vec<&str> = line.split('(').collect();
                if parts.len() > 1 {
                    parts[1]
                        .trim_end_matches(')')
                        .split(',')
                        .map(|s| s.trim().trim_matches('\'').to_string())
                        .filter(|s| !s.is_empty())
                        .collect()
                } else {
                    Vec::new()
                }
            } else {
                Vec::new()
            };

            let supported_drivers: Vec<serde_json::Value> = detected_drivers
                .iter()
                .map(|driver| {
                    json!({
                        "id": driver,
                        "label": render_driver_label(driver)
                    })
                })
                .collect();

            json!({
                "success": o.status.success(),
                "hostOs": host_os,
                "supportsRenderDriver": true,
                "detectedDrivers": detected_drivers,
                "supportedDrivers": supported_drivers,
                "diagnostics": "render drivers parsed from scrcpy --help"
            })
        }
        Err(e) => json!({
            "success": false,
            "hostOs": host_os,
            "supportsRenderDriver": false,
            "detectedDrivers": [],
            "supportedDrivers": [],
            "message": e.to_string()
        }),
    }
}

fn resolve_audio_codec_flag<'a>(config: &'a ScrcpyConfig, override_codec: Option<&'a str>) -> Option<&'a str> {
    if let Some(c) = override_codec {
        let trimmed = c.trim();
        if !trimmed.is_empty() {
            return Some(trimmed);
        }
    }
    if let Some(ref user_codec) = config.audio_codec {
        let trimmed = user_codec.trim();
        if !trimmed.is_empty() && !trimmed.eq_ignore_ascii_case("auto") {
            return Some(trimmed);
        }
    }
    None
}

fn build_scrcpy_args(config: &ScrcpyConfig, video_dir_fallback: Option<String>, audio_codec_override: Option<&str>) -> Vec<String> {
    let mut args = Vec::new();

    if !config.device.is_empty() {
        args.push("-s".to_string());
        args.push(config.device.clone());
    }

    let codec = config.codec.as_deref().unwrap_or("h264");
    args.push(format!("--video-codec={}", codec));

    let otg_pure = config.otg_pure.unwrap_or(false);
    let hid_keyboard = config.hid_keyboard.unwrap_or(false);
    let hid_mouse = config.hid_mouse.unwrap_or(false);

    if config.session_mode == "mirror" && (hid_keyboard || hid_mouse) && otg_pure {
        if config.device.contains('.') || config.device.contains(':') {
            args.push("--no-video".to_string());
            args.push("--no-audio".to_string());
            args.push("--keyboard=uhid".to_string());
            args.push("--mouse=uhid".to_string());
        } else {
            args.push("--otg".to_string());
        }
    } else {
        if hid_keyboard {
            args.push("--keyboard=uhid".to_string());
        }
        if hid_mouse {
            args.push("--mouse=uhid".to_string());
        }

        if let Some(render_driver) = &config.render_driver {
            let selected_driver = render_driver.trim();
            if !selected_driver.is_empty() && selected_driver != "auto" {
                args.push("--render-driver".to_string());
                args.push(selected_driver.to_string());
            }
        }

        if let Some(bitrate) = config.bitrate {
            args.push("--video-bit-rate".to_string());
            args.push(format!("{}M", bitrate));
        }

        let audio_enabled = config.audio_enabled.unwrap_or(true);
        if !audio_enabled { args.push("--no-audio".to_string()); }
        if audio_enabled {
            if let Some(codec) = resolve_audio_codec_flag(config, audio_codec_override) {
                args.push(format!("--audio-codec={}", codec));
            }
        }
        if let Some(aot) = config.always_on_top { if aot { args.push("--always-on-top".to_string()); } }
        if let Some(fs) = config.fullscreen { if fs { args.push("--fullscreen".to_string()); } }
        if let Some(bl) = config.borderless { if bl { args.push("--window-borderless".to_string()); } }

        if config.session_mode == "mirror" && !config.fullscreen.unwrap_or(false) {
            if let Some(wx) = config.window_x {
                args.push(format!("--window-x={}", wx));
            }
            if let Some(wy) = config.window_y {
                args.push(format!("--window-y={}", wy));
            }
        }

        if let Some(rot) = &config.rotation {
            if rot != "0" {
                args.push("--orientation".to_string());
                args.push(rot.clone());
            }
        }

        let can_control = config.session_mode != "camera";
        if can_control {
            if let Some(sa) = config.stay_awake { if sa { args.push("--stay-awake".to_string()); } }
            if let Some(ka) = config.keep_active { if ka { args.push("--keep-active".to_string()); } }
            if let Some(to) = config.turn_off { if to { args.push("--turn-screen-off".to_string()); args.push("--no-power-on".to_string()); } }
        }

        if config.session_mode == "camera" {
            args.push("--video-source=camera".to_string());
            if let Some(cid) = &config.camera_id {
                if !cid.is_empty() { args.push(format!("--camera-id={}", cid)); }
                else if let Some(facing) = &config.camera_facing { args.push(format!("--camera-facing={}", facing)); }
            } else if let Some(facing) = &config.camera_facing { args.push(format!("--camera-facing={}", facing)); }

            if let Some(res) = &config.res {
                if res != "0" {
                    let camera_size = match res.as_str() {
                        "3840" => "3840x2160",
                        "2560" => "2560x1440",
                        "1920" => "1920x1080",
                        "1600" => "1600x900",
                        "1280" => "1280x720",
                        "1024" => "1024x576",
                        "800" => "800x480",
                        _ => "1920x1080",
                    };
                    args.push(format!("--camera-size={}", camera_size));
                } else {
                    args.push("--camera-size=1920x1080".to_string());
                }
            } else {
                args.push("--camera-size=1920x1080".to_string());
            }

            if let Some(ar) = &config.camera_ar { if ar != "0" { args.push(format!("--camera-ar={}", ar)); } }
            if let Some(chs) = config.camera_high_speed { if chs { args.push("--camera-high-speed".to_string()); } }
            if let Some(true) = config.camera_torch { args.push("--camera-torch".to_string()); }
            if let Some(zoom) = config.camera_zoom {
                if zoom > 1.005 {
                    args.push(format!("--camera-zoom={:.1}", zoom));
                }
            }
        } else if config.session_mode == "desktop" {
            let w = config.vd_width.unwrap_or(1920);
            let h = config.vd_height.unwrap_or(1080);
            let dpi = config.vd_dpi.unwrap_or(420);
            args.push(format!("--new-display={}x{}/{}", w, h, dpi));
            args.push("--video-buffer=100".to_string());
            if let Some(true) = config.flex_display { args.push("--flex-display".to_string()); }
        }

        if let Some(fps) = config.fps {
            if fps > 0 {
                if config.session_mode == "camera" {
                    args.push("--camera-fps".to_string());
                } else {
                    args.push("--max-fps".to_string());
                }
                args.push(fps.to_string());
            }
        } else if config.session_mode == "camera" && config.camera_high_speed.unwrap_or(false) {
            args.push("--camera-fps".to_string());
            args.push("60".to_string());
        }

        if config.session_mode != "camera" {
            if let Some(res) = &config.res {
                if res != "0" {
                    args.push("--max-size".to_string());
                    args.push(res.clone());
                }
            }
        }

        if let Some(rec) = config.record {
            if rec {
                let mut path = config.record_path.clone().unwrap_or_default();
                if path.trim().is_empty() {
                    path = video_dir_fallback.unwrap_or_else(|| ".".to_string());
                }
                let filename = format!("scrcpy_{}_{}.mkv", config.device.replace(":", "-"), chrono::Local::now().format("%Y%m%d_%H%M%S"));
                let full_path = std::path::Path::new(&path).join(filename);
                args.push(format!("--record={}", full_path.to_string_lossy()));
            }
        }

        if let Some(ref color) = config.background_color {
            let trimmed = color.trim();
            if !trimmed.is_empty() {
                args.push(format!("--background-color={}", trimmed));
            }
        }

        if let Some(true) = config.ignore_video_encoder_constraints {
            args.push("--ignore-video-encoder-constraints".to_string());
        }
    }

    args
}

async fn spawn_scrcpy_streams(
    window: &Window,
    exe_path: &str,
    adb_exe_path: &str,
    server_path: Option<&str>,
    args: &[String],
    vsync: bool,
) -> Result<(tokio::process::Child, Arc<AtomicBool>), String> {
    let command_str = format!("> scrcpy {}", args.join(" "));
    let _ = window.emit("scrcpy-log", command_str);

    let mut command = create_command(exe_path);
    command.args(args);
    command.env("ADB", adb_exe_path);
    if let Some(sp) = server_path {
        if Path::new(sp).exists() {
            command.env("SCRCPY_SERVER_PATH", sp);
        }
    }
    command.env("SDL_RENDER_VSYNC", if vsync { "1" } else { "0" });
    command.stdout(Stdio::piped());
    command.stderr(Stdio::piped());

    let mut child = command.spawn().map_err(|e| e.to_string())?;

    let stdout = child.stdout.take().expect("Failed to capture stdout");
    let stderr = child.stderr.take().expect("Failed to capture stderr");

    let audio_error_flag = Arc::new(AtomicBool::new(false));

    let window_stdout = window.clone();
    tokio::spawn(async move {
        let reader = BufReader::new(stdout);
        let mut lines = reader.lines();
        let mut buffer = Vec::new();
        let mut interval = tokio::time::interval(Duration::from_millis(100));

        loop {
            tokio::select! {
                line_res = lines.next_line() => {
                    match line_res {
                        Ok(Some(line)) => buffer.push(line),
                        Ok(None) => break,
                        Err(_) => break,
                    }
                }
                _ = interval.tick() => {
                    if !buffer.is_empty() {
                        let combined = buffer.join("\n");
                        let _ = window_stdout.emit("scrcpy-log", combined);
                        buffer.clear();
                    }
                }
            }
        }
        if !buffer.is_empty() {
            let _ = window_stdout.emit("scrcpy-log", buffer.join("\n"));
        }
    });

    let window_stderr = window.clone();
    let flag_clone = audio_error_flag.clone();
    tokio::spawn(async move {
        let reader = BufReader::new(stderr);
        let mut lines = reader.lines();
        let mut buffer = Vec::new();
        let mut interval = tokio::time::interval(Duration::from_millis(100));

        loop {
            tokio::select! {
                line_res = lines.next_line() => {
                    match line_res {
                        Ok(Some(line)) => {
                            if is_audio_codec_error(&line) {
                                flag_clone.store(true, Ordering::SeqCst);
                            }
                            buffer.push(line);
                        }
                        Ok(None) => break,
                        Err(_) => break,
                    }
                }
                _ = interval.tick() => {
                    if !buffer.is_empty() {
                        let combined = buffer.join("\n");
                        let _ = window_stderr.emit("scrcpy-log", combined);
                        buffer.clear();
                    }
                }
            }
        }
        if !buffer.is_empty() {
            let _ = window_stderr.emit("scrcpy-log", buffer.join("\n"));
        }
    });

    Ok((child, audio_error_flag))
}

enum AttemptOutcome {
    Exited(String),
    WaitError(String),
    UserStopped,
}

#[tauri::command]
pub async fn run_scrcpy(window: Window, state: State<'_, ScrcpyState>, config: ScrcpyConfig, app_handle: AppHandle) -> Result<(), String> {
    let video_dir = app_handle.path().video_dir().ok().map(|p| p.to_string_lossy().to_string());
    let exe_path = get_binary_path("scrcpy", config.scrcpy_path.clone());

    let mode_label = match config.session_mode.as_str() {
        "camera" => "Camera Mode",
        "desktop" => "Desktop Mode",
        _ => "Screen Mirroring",
    };

    let res_label = config.res.as_ref().map(|r| if r == "0" { "Original" } else { r }).unwrap_or("Original");
    let bitrate_label = format!("{}Mbps", config.bitrate.unwrap_or(8));
    let fps_label = format!("{}fps", config.fps.unwrap_or(60));

    let _ = window.emit("scrcpy-log", format!("[SYSTEM] Starting {} session...", mode_label));
    let _ = window.emit("scrcpy-log", format!("[SYSTEM] Target: {} | Config: {} @ {}, {}", config.device, res_label, bitrate_label, fps_label));

    if config.record.unwrap_or(false) {
        let path = config.record_path.as_ref().map(|p| if p.is_empty() { "Videos" } else { p }).unwrap_or("Videos");
        let _ = window.emit("scrcpy-log", format!("[SYSTEM] Recording enabled -> output to {}", path));
    }

    let adb_exe_path = get_binary_path("adb", config.scrcpy_path.clone());
    let server_path = if !exe_path.is_empty() && exe_path != "scrcpy" {
        Path::new(&exe_path).parent().map(|p| p.join("scrcpy-server").to_string_lossy().to_string())
    } else {
        None
    };

    let _ = window.emit("scrcpy-log", format!("[SYSTEM] Using scrcpy: {}", exe_path));
    let _ = window.emit("scrcpy-log", format!("[SYSTEM] Using adb: {}", adb_exe_path));

    let audio_enabled = config.audio_enabled.unwrap_or(true);
    let audio_codec_mode = config.audio_codec.as_deref().unwrap_or("auto").trim();
    let should_auto_fallback = audio_enabled
        && (audio_codec_mode.is_empty() || audio_codec_mode.eq_ignore_ascii_case("auto"));

    let initial_args = build_scrcpy_args(&config, video_dir.clone(), None);

    let (child, audio_error_flag) = spawn_scrcpy_streams(
        &window,
        &exe_path,
        &adb_exe_path,
        server_path.as_deref(),
        &initial_args,
        config.vsync.unwrap_or(true),
    ).await?;

    let initial_scrcpy_pid = child.id();
    state.processes.lock().unwrap().insert(config.device.clone(), child);
    let _ = window.emit("scrcpy-status", json!({ "device": config.device, "running": true }));

    let device_mon = config.device.clone();
    let window_mon = window.clone();
    let app_handle_mon = window.app_handle().clone();
    let video_dir_mon = video_dir;
    let exe_path_mon = exe_path;
    let adb_exe_path_mon = adb_exe_path;
    let server_path_mon = server_path;
    let config_mon = config.clone();

    let requested_pos: Option<(i32, i32)> = match (config_mon.window_x, config_mon.window_y) {
        (Some(x), Some(y)) => Some((x, y)),
        _ => None,
    };
    let track_pos = config_mon.session_mode == "mirror" && !config_mon.fullscreen.unwrap_or(false);

    tokio::spawn(async move {
        let mut current_audio_flag = audio_error_flag;
        let mut chain_index: usize = 0;
        let mut current_scrcpy_pid = initial_scrcpy_pid;
        let mut first_window_pos: Option<(i32, i32)> = None;
        let mut last_window_pos: Option<(i32, i32)> = None;

        loop {
            tokio::time::sleep(Duration::from_millis(500)).await;

            if track_pos {
                if let Some(pid) = current_scrcpy_pid {
                    if let Some(pos) = try_capture_window_pos(pid) {
                        if first_window_pos.is_none() {
                            first_window_pos = Some(pos);
                        }
                        last_window_pos = Some(pos);
                    }
                }
            }

            let outcome = {
                let state_mon = app_handle_mon.state::<ScrcpyState>();
                let mut processes = state_mon.processes.lock().unwrap();
                match processes.get_mut(&device_mon) {
                    Some(child) => match child.try_wait() {
                        Ok(Some(status)) => {
                            processes.remove(&device_mon);
                            Some(AttemptOutcome::Exited(status.to_string()))
                        }
                        Ok(None) => None,
                        Err(e) => {
                            processes.remove(&device_mon);
                            Some(AttemptOutcome::WaitError(e.to_string()))
                        }
                    },
                    None => Some(AttemptOutcome::UserStopped),
                }
            };

            let outcome = match outcome {
                Some(o) => o,
                None => continue,
            };

            match outcome {
                AttemptOutcome::WaitError(e) => {
                    let _ = window_mon.emit("scrcpy-log", format!("[SYSTEM] Error waiting for scrcpy: {}", e));
                    emit_window_pos_and_stop(&window_mon, &device_mon, requested_pos, first_window_pos, last_window_pos);
                    break;
                }
                AttemptOutcome::UserStopped => {
                    let fresh_pos = app_handle_mon
                        .state::<ScrcpyState>()
                        .final_capture_hint
                        .lock()
                        .unwrap()
                        .remove(&device_mon);
                    let pos_to_persist = fresh_pos.or(last_window_pos);
                    emit_window_pos_and_stop(&window_mon, &device_mon, requested_pos, first_window_pos, pos_to_persist);
                    break;
                }
                AttemptOutcome::Exited(status) => {
                    let _ = window_mon.emit("scrcpy-log", format!("[SYSTEM] Scrcpy process exited with status: {}", status));
                    tokio::time::sleep(Duration::from_millis(250)).await;

                    let audio_failed = current_audio_flag.load(Ordering::SeqCst);

                    if should_auto_fallback && audio_failed && chain_index < AUDIO_FALLBACK_CHAIN.len() {
                        let next_codec = AUDIO_FALLBACK_CHAIN[chain_index];
                        let _ = window_mon.emit(
                            "scrcpy-log",
                            format!("[SYSTEM] Default audio codec failed, retrying with {}...", next_codec.to_uppercase()),
                        );

                        let new_args = build_scrcpy_args(&config_mon, video_dir_mon.clone(), Some(next_codec));

                        match spawn_scrcpy_streams(
                            &window_mon,
                            &exe_path_mon,
                            &adb_exe_path_mon,
                            server_path_mon.as_deref(),
                            &new_args,
                            config_mon.vsync.unwrap_or(true),
                        ).await {
                            Ok((new_child, new_flag)) => {
                                current_scrcpy_pid = new_child.id();
                                first_window_pos = None;
                                last_window_pos = None;
                                let state_mon = app_handle_mon.state::<ScrcpyState>();
                                state_mon.processes.lock().unwrap().insert(device_mon.clone(), new_child);
                                current_audio_flag = new_flag;
                                chain_index += 1;
                                continue;
                            }
                            Err(e) => {
                                let _ = window_mon.emit("scrcpy-log", format!("[SYSTEM] Failed to spawn retry: {}", e));
                                emit_window_pos_and_stop(&window_mon, &device_mon, requested_pos, first_window_pos, last_window_pos);
                                break;
                            }
                        }
                    } else if should_auto_fallback && audio_failed {
                        let _ = window_mon.emit(
                            "scrcpy-log",
                            "[SYSTEM] No compatible audio codec found. Consider disabling audio forwarding.".to_string(),
                        );
                        emit_window_pos_and_stop(&window_mon, &device_mon, requested_pos, first_window_pos, last_window_pos);
                        break;
                    } else {
                        emit_window_pos_and_stop(&window_mon, &device_mon, requested_pos, first_window_pos, last_window_pos);
                        break;
                    }
                }
            }
        }
    });

    Ok(())
}

fn try_capture_window_pos(pid: u32) -> Option<(i32, i32)> {
    #[cfg(target_os = "windows")]
    {
        use windows::Win32::Foundation::POINT;
        use windows::Win32::Graphics::Gdi::ClientToScreen;
        use windows::Win32::UI::WindowsAndMessaging::{IsIconic, IsZoomed};

        if let Some(hwnd) = find_window_by_pid(pid) {
            let special = unsafe { IsIconic(hwnd).as_bool() || IsZoomed(hwnd).as_bool() };
            if !special {
                let mut pt = POINT { x: 0, y: 0 };
                if unsafe { ClientToScreen(hwnd, &mut pt) }.as_bool() {
                    return Some((pt.x, pt.y));
                }
            }
        }
    }
    #[cfg(target_os = "linux")]
    {
        let pid_str = pid.to_string();
        let output = StdCommand::new("xdotool")
            .args(["search", "--pid", &pid_str, "getwindowgeometry", "--shell"])
            .output()
            .ok()?;
        if output.status.success() {
            let text = String::from_utf8_lossy(&output.stdout);
            let x = parse_shell_var_int(&text, "X")?;
            let y = parse_shell_var_int(&text, "Y")?;
            return Some((x, y));
        }
    }
    #[cfg(target_os = "macos")]
    {
        let script = format!(
            concat!(
                "tell application \"System Events\"\n",
                "try\n",
                "set proc to first process whose unix id is {}\n",
                "set pos to position of first window of proc\n",
                "((item 1 of pos) as string) & \" \" & ((item 2 of pos) as string)\n",
                "end try\n",
                "end tell"
            ),
            pid
        );
        let output = StdCommand::new("osascript")
            .args(["-e", &script])
            .output()
            .ok()?;
        if output.status.success() {
            let text = String::from_utf8_lossy(&output.stdout);
            let mut parts = text.split_whitespace();
            let x: i32 = parts.next()?.parse().ok()?;
            let y: i32 = parts.next()?.parse().ok()?;
            return Some((x, y));
        }
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
    let _ = pid;
    None
}

#[cfg(target_os = "linux")]
fn parse_shell_var_int(text: &str, var: &str) -> Option<i32> {
    let prefix = format!("{}=", var);
    for line in text.lines() {
        if line.starts_with(&prefix) {
            return line[prefix.len()..].parse().ok();
        }
    }
    None
}

#[cfg(target_os = "windows")]
fn find_window_by_pid(pid: u32) -> Option<windows::Win32::Foundation::HWND> {
    use windows::core::BOOL;
    use windows::Win32::Foundation::{HWND, LPARAM};
    use windows::Win32::UI::WindowsAndMessaging::{
        EnumWindows, GetWindow, GetWindowThreadProcessId, IsWindowVisible, GW_OWNER,
    };

    struct Search {
        target_pid: u32,
        found: HWND,
    }

    unsafe extern "system" fn enum_proc(hwnd: HWND, lparam: LPARAM) -> BOOL {
        let search = &mut *(lparam.0 as *mut Search);
        if !IsWindowVisible(hwnd).as_bool() {
            return BOOL(1);
        }
        if GetWindow(hwnd, GW_OWNER).map(|o| !o.0.is_null()).unwrap_or(false) {
            return BOOL(1);
        }
        let mut wnd_pid: u32 = 0;
        let _ = GetWindowThreadProcessId(hwnd, Some(&mut wnd_pid as *mut u32));
        if wnd_pid == search.target_pid {
            search.found = hwnd;
            return BOOL(0);
        }
        BOOL(1)
    }

    let mut search = Search {
        target_pid: pid,
        found: HWND::default(),
    };
    unsafe {
        let _ = EnumWindows(Some(enum_proc), LPARAM(&mut search as *mut Search as isize));
    }
    (!search.found.0.is_null()).then_some(search.found)
}

fn resolve_window_pos_to_persist(
    requested: Option<(i32, i32)>,
    first: Option<(i32, i32)>,
    last: (i32, i32),
) -> (i32, i32) {
    if let (Some((rx, ry)), Some((fx, fy))) = (requested, first) {
        let (dx, dy) = (fx - rx, fy - ry);
        if dx.abs() <= 80 && dy.abs() <= 120 {
            return (last.0 - dx, last.1 - dy);
        }
    }
    last
}

fn emit_window_pos_and_stop(
    window: &Window,
    device: &str,
    requested: Option<(i32, i32)>,
    first: Option<(i32, i32)>,
    last: Option<(i32, i32)>,
) {
    if let Some(last) = last {
        let (x, y) = resolve_window_pos_to_persist(requested, first, last);
        let _ = window.emit("scrcpy-window-pos", json!({ "device": device, "x": x, "y": y }));
    }
    let _ = window.emit("scrcpy-status", json!({ "device": device, "running": false }));
}

fn recenter_window(pid: u32) {
    #[cfg(target_os = "windows")]
    {
        use windows::Win32::Foundation::RECT;
        use windows::Win32::UI::WindowsAndMessaging::{
            GetSystemMetrics, GetWindowRect, IsIconic, IsZoomed, SetForegroundWindow,
            SetWindowPos, ShowWindow, SM_CXSCREEN, SM_CYSCREEN, SWP_NOSIZE, SWP_NOZORDER,
            SW_RESTORE,
        };

        let Some(hwnd) = find_window_by_pid(pid) else {
            return;
        };
        if unsafe { IsZoomed(hwnd) }.as_bool() {
            return;
        }
        if unsafe { IsIconic(hwnd) }.as_bool() {
            let _ = unsafe { ShowWindow(hwnd, SW_RESTORE) };
        }
        let mut rect = RECT::default();
        if unsafe { GetWindowRect(hwnd, &mut rect) }.is_err() {
            return;
        }
        let (w, h) = (rect.right - rect.left, rect.bottom - rect.top);
        let (screen_w, screen_h) =
            unsafe { (GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)) };
        let _ = unsafe {
            SetWindowPos(
                hwnd,
                None,
                (screen_w - w) / 2,
                (screen_h - h) / 2,
                0,
                0,
                SWP_NOSIZE | SWP_NOZORDER,
            )
        };
        let _ = unsafe { SetForegroundWindow(hwnd) };
    }
    #[cfg(target_os = "linux")]
    {
        let pid_str = pid.to_string();
        let Ok(search_out) = StdCommand::new("xdotool").args(["search", "--pid", &pid_str]).output() else {
            return;
        };
        let Some(window_id) = String::from_utf8_lossy(&search_out.stdout).lines().next().map(str::to_string) else {
            return;
        };
        let Ok(geom_out) = StdCommand::new("xdotool")
            .args(["getwindowgeometry", "--shell", &window_id])
            .output()
        else {
            return;
        };
        let geom_text = String::from_utf8_lossy(&geom_out.stdout);
        let (Some(w), Some(h)) = (
            parse_shell_var_int(&geom_text, "WIDTH"),
            parse_shell_var_int(&geom_text, "HEIGHT"),
        ) else {
            return;
        };
        let Ok(display_out) = StdCommand::new("xdotool").arg("getdisplaygeometry").output() else {
            return;
        };
        let display_text = String::from_utf8_lossy(&display_out.stdout);
        let mut parts = display_text.split_whitespace();
        let (Some(Ok(screen_w)), Some(Ok(screen_h))) = (
            parts.next().map(str::parse::<i32>),
            parts.next().map(str::parse::<i32>),
        ) else {
            return;
        };
        let x = ((screen_w - w).max(0) / 2).to_string();
        let y = ((screen_h - h).max(0) / 2).to_string();
        let _ = StdCommand::new("xdotool").args(["windowmove", &window_id, &x, &y]).output();
        let _ = StdCommand::new("xdotool").args(["windowactivate", &window_id]).output();
    }
    #[cfg(target_os = "macos")]
    {
        let script = format!(
            concat!(
                "tell application \"System Events\"\n",
                "try\n",
                "set proc to first process whose unix id is {}\n",
                "set win to first window of proc\n",
                "set {{winW, winH}} to size of win\n",
                "tell application \"Finder\" to set screenBounds to bounds of window of desktop\n",
                "set screenW to (item 3 of screenBounds)\n",
                "set screenH to (item 4 of screenBounds)\n",
                "set position of win to {{((screenW - winW) / 2), ((screenH - winH) / 2)}}\n",
                "set frontmost of proc to true\n",
                "end try\n",
                "end tell"
            ),
            pid
        );
        let _ = StdCommand::new("osascript").args(["-e", &script]).output();
    }
    #[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
    let _ = pid;
}

pub fn recenter_device(state: &ScrcpyState, device: &str) {
    let pid = state.processes.lock().unwrap().get(device).and_then(|c| c.id());
    if let Some(pid) = pid {
        recenter_window(pid);
    }
}

#[tauri::command]
pub fn recenter_scrcpy_window(state: State<'_, ScrcpyState>, device: String) -> Result<(), String> {
    recenter_device(&state, &device);
    Ok(())
}

#[tauri::command]
pub fn set_active_device(state: State<'_, ScrcpyState>, device: Option<String>) -> Result<(), String> {
    *state.active_device.lock().unwrap() = device;
    Ok(())
}

#[tauri::command]
pub async fn stop_scrcpy(state: State<'_, ScrcpyState>, device: String) -> Result<(), String> {
    let child = {
        let mut processes = state.processes.lock().unwrap();
        processes.remove(&device)
    };

    if let Some(mut c) = child {
        if let Some(pid) = c.id() {
            if let Some(pos) = try_capture_window_pos(pid) {
                state.final_capture_hint.lock().unwrap().insert(device.clone(), pos);
            }

            #[cfg(target_os = "windows")]
            {
                let _ = StdCommand::new("taskkill")
                    .args(&["/PID", &pid.to_string()])
                    .creation_flags(CREATE_NO_WINDOW)
                    .output();
            }

            #[cfg(not(target_os = "windows"))]
            {
                let _ = StdCommand::new("kill")
                    .arg(pid.to_string())
                    .output();
            }

            tokio::time::sleep(Duration::from_millis(500)).await;
        } else {
            let _ = c.kill().await;
        }
    }
    Ok(())
}

#[tauri::command]
pub async fn download_scrcpy(window: Window) -> Result<(), String> {
    use std::io::Write;

    let (os_tag, arch_tag, extension) = if cfg!(target_os = "windows") {
        let arch = if cfg!(target_arch = "x86_64") { "win64" } else { "win32" };
        (arch, arch, ".zip")
    } else if cfg!(target_os = "linux") {
        ("linux", "linux-x86_64", ".tar.gz")
    } else if cfg!(target_os = "macos") {
        let arch = if cfg!(target_arch = "aarch64") { "macos-aarch64" } else { "macos-x86_64" };
        ("macos", arch, ".tar.gz")
    } else {
        return Err("Unsupported OS for auto-download".to_string());
    };

    let _ = window.emit("scrcpy-log", format!("[SYSTEM] Detecting platform: {} ({})", os_tag, arch_tag));
    let _ = window.emit("scrcpy-status", json!({ "type": "downloading", "success": true, "message": format!("Fetching latest {} release...", arch_tag) }));

    let client = reqwest::Client::builder().user_agent("ScrcpyGui-Downloader").build().map_err(|e| e.to_string())?;

    let mut download_url = String::new();
    let mut filename = String::new();

    let api_url = "https://api.github.com/repos/Genymobile/scrcpy/releases/latest";
    let api_resp = client.get(api_url).send().await;
    let mut used_fallback = false;

    if let Ok(resp) = api_resp {
        if resp.status().is_success() {
            if let Ok(json_val) = resp.json::<serde_json::Value>().await {
                if let Some(assets) = json_val["assets"].as_array() {
                    for asset in assets {
                        let name = asset["name"].as_str().unwrap_or("");
                        if name.contains(arch_tag) && name.ends_with(extension) {
                            download_url = asset["browser_download_url"].as_str().unwrap_or("").to_string();
                            filename = name.to_string();
                            break;
                        }
                    }
                }
            }
        } else if resp.status() == reqwest::StatusCode::FORBIDDEN {
            let _ = window.emit("scrcpy-log", "[SYSTEM] API rate limited, attempting fallback discovery...");
            used_fallback = true;
        }
    } else {
        used_fallback = true;
    }

    if used_fallback || download_url.is_empty() {
        let redirect_res = client.get("https://github.com/Genymobile/scrcpy/releases/latest")
            .send().await.map_err(|e| format!("Fallback failed: {}", e))?;

        let final_url = redirect_res.url().as_str();
        if let Some(tag) = final_url.split('/').next_back() {
            if tag.starts_with('v') {
                filename = format!("scrcpy-{}-{}{}", arch_tag, tag, extension);
                download_url = format!("https://github.com/Genymobile/scrcpy/releases/download/{}/{}", tag, filename);
                let _ = window.emit("scrcpy-log", format!("[SYSTEM] Discovered latest tag via fallback: {}", tag));
            }
        }
    }

    if download_url.is_empty() {
        return Err(format!("Could not find {} binary. (API rate limit might be active)", arch_tag));
    }

    let _ = window.emit("scrcpy-log", format!("[SYSTEM] Found asset: {}", filename));

    let current_dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|p| p.to_path_buf()))
        .unwrap_or_else(|| std::env::current_dir().unwrap());

    let temp_archive_path = current_dir.join(format!("scrcpy_temp{}", extension));
    let extract_path = current_dir.join("scrcpy-bin");

    {
        let mut file = std::fs::File::create(&temp_archive_path).map_err(|e| format!("Failed to create archive file: {}", e))?;
        let mut download_resp = client.get(&download_url).send().await.map_err(|e| format!("Failed to connect to download URL: {}", e))?;
        let total_size = download_resp.content_length().unwrap_or(0);

        let _ = window.emit("scrcpy-log", format!("[SYSTEM] Downloading: {} MB", total_size / 1024 / 1024));

        let mut downloaded: u64 = 0;
        while let Some(chunk) = download_resp.chunk().await.map_err(|e| e.to_string())? {
            file.write_all(&chunk).map_err(|e| format!("Failed to write chunk: {}", e))?;
            downloaded += chunk.len() as u64;
            if total_size > 0 {
                let percent = (downloaded * 100) / total_size;
                let _ = window.emit("download-progress", json!({ "percent": percent }));
            }
        }
    }

    let _ = window.emit("scrcpy-log", "[SYSTEM] Download finished. Starting extraction...");
    let _ = window.emit("scrcpy-status", json!({ "type": "downloading", "success": true, "message": "Extracting binaries..." }));

    if extract_path.exists() {
        let _ = std::fs::remove_dir_all(&extract_path);
    }

    let temp_extract_dir = current_dir.join("temp_extract");
    if temp_extract_dir.exists() {
        let _ = std::fs::remove_dir_all(&temp_extract_dir);
    }
    std::fs::create_dir_all(&temp_extract_dir).map_err(|e| e.to_string())?;

    if extension == ".zip" {
        let _ = window.emit("scrcpy-log", "[SYSTEM] Decompressing ZIP archive...");
        let file = std::fs::File::open(&temp_archive_path).map_err(|e| format!("Failed to open zip: {}", e))?;
        let mut archive = zip::ZipArchive::new(file).map_err(|e| format!("Failed to read zip archive: {}", e))?;
        archive.extract(&temp_extract_dir).map_err(|e| format!("Failed to extract: {}", e))?;
    } else {
        let _ = window.emit("scrcpy-log", "[SYSTEM] Decompressing TAR.GZ archive...");
        let file = std::fs::File::open(&temp_archive_path).map_err(|e| format!("Failed to open tar.gz: {}", e))?;
        let tar = GzDecoder::new(file);
        let mut archive = Archive::new(tar);
        archive.unpack(&temp_extract_dir).map_err(|e| format!("Failed to extract tar: {}", e))?;
    }

    let mut entries = std::fs::read_dir(&temp_extract_dir).map_err(|e| e.to_string())?;
    if let Some(entry) = entries.next() {
        let entry = entry.map_err(|e| e.to_string())?;
        let path = entry.path();

        if path.is_dir() {
            let _ = std::fs::rename(&path, &extract_path).or_else(|_| {
                copy_dir_all(&path, &extract_path)
            });
        } else {
            let _ = std::fs::rename(&temp_extract_dir, &extract_path).or_else(|_| {
                copy_dir_all(&temp_extract_dir, &extract_path)
            });
        }
    }

    if temp_extract_dir.exists() { let _ = std::fs::remove_dir_all(&temp_extract_dir); }
    if temp_archive_path.exists() { let _ = std::fs::remove_file(&temp_archive_path); }

    let _ = window.emit("scrcpy-status", json!({ "type": "download-complete", "success": true, "message": extract_path.to_string_lossy() }));
    Ok(())
}

#[tauri::command]
pub async fn get_videos_dir(app_handle: AppHandle) -> Result<String, String> {
    app_handle.path().video_dir()
        .map(|p| p.to_string_lossy().to_string())
        .map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn save_report(app_handle: AppHandle, content: String, name: String) -> Result<String, String> {
    let downloads = app_handle.path().download_dir().map_err(|e| e.to_string())?;
    let path = downloads.join(&name);
    std::fs::write(&path, content).map_err(|e| e.to_string())?;
    Ok(path.to_string_lossy().to_string())
}

#[tauri::command]
pub async fn get_scrcpy_bin_dir() -> Result<String, String> {
    let current_dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|p| p.to_path_buf()))
        .unwrap_or_else(|| std::env::current_dir().unwrap());

    let extract_path = current_dir.join("scrcpy-bin");
    if extract_path.exists() {
        Ok(extract_path.to_string_lossy().to_string())
    } else {
        Ok(current_dir.to_string_lossy().to_string())
    }
}

pub fn get_local_scrcpy_version(custom_path: Option<String>) -> Option<String> {
    let exe_path = get_binary_path("scrcpy", custom_path);
    let mut cmd = StdCommand::new(&exe_path);
    #[cfg(target_os = "windows")]
    {
        cmd.creation_flags(CREATE_NO_WINDOW);
    }
    let output = cmd.arg("--version").output().ok()?;
    if output.status.success() {
        let out_str = String::from_utf8_lossy(&output.stdout);
        for line in out_str.lines() {
            if line.contains("scrcpy") {
                let parts: Vec<&str> = line.split_whitespace().collect();
                if let Some(idx) = parts.iter().position(|&x| x == "scrcpy") {
                    if let Some(version) = parts.get(idx + 1) {
                        return Some(version.trim_start_matches('v').to_string());
                    }
                }
            }
        }
    }
    None
}

pub async fn get_latest_scrcpy_version() -> Result<String, String> {
    let client = reqwest::Client::builder()
        .user_agent("ScrcpyGui-Updater")
        .build()
        .map_err(|e| e.to_string())?;

    let api_url = "https://api.github.com/repos/Genymobile/scrcpy/releases/latest";
    let api_resp = client.get(api_url).send().await;

    let mut tag_name = String::new();
    let mut used_fallback = false;

    if let Ok(resp) = api_resp {
        if resp.status().is_success() {
            if let Ok(json_val) = resp.json::<serde_json::Value>().await {
                if let Some(tag) = json_val["tag_name"].as_str() {
                    tag_name = tag.trim_start_matches('v').to_string();
                }
            }
        } else if resp.status() == reqwest::StatusCode::FORBIDDEN {
            used_fallback = true;
        }
    } else {
        used_fallback = true;
    }

    if used_fallback || tag_name.is_empty() {
        let redirect_res = client.get("https://github.com/Genymobile/scrcpy/releases/latest")
            .send().await
            .map_err(|e| format!("Fallback failed: {}", e))?;

        let final_url = redirect_res.url().as_str();
        if let Some(tag) = final_url.split('/').next_back() {
            if tag.starts_with('v') || tag.chars().next().map_or(false, |c| c.is_ascii_digit()) {
                tag_name = tag.trim_start_matches('v').to_string();
            }
        }
    }

    if tag_name.is_empty() {
        return Err("Could not determine latest version".to_string());
    }

    Ok(tag_name)
}

fn compare_versions(local: &str, remote: &str) -> bool {
    let local_parts: Vec<u32> = local.split('.')
        .filter_map(|s| s.chars().take_while(|c| c.is_ascii_digit()).collect::<String>().parse().ok())
        .collect();
    let remote_parts: Vec<u32> = remote.split('.')
        .filter_map(|s| s.chars().take_while(|c| c.is_ascii_digit()).collect::<String>().parse().ok())
        .collect();

    for i in 0..std::cmp::max(local_parts.len(), remote_parts.len()) {
        let local_val = local_parts.get(i).cloned().unwrap_or(0);
        let remote_val = remote_parts.get(i).cloned().unwrap_or(0);
        if remote_val > local_val {
            return true;
        } else if local_val > remote_val {
            return false;
        }
    }
    false
}

#[tauri::command]
pub async fn check_scrcpy_update(custom_path: Option<String>) -> serde_json::Value {
    let local_version = match get_local_scrcpy_version(custom_path.clone()) {
        Some(v) => v,
        None => return json!({ "update_available": false, "local_version": null, "latest_version": null, "message": "Scrcpy not installed or not working" }),
    };

    let latest_version = match get_latest_scrcpy_version().await {
        Ok(v) => v,
        Err(e) => return json!({ "update_available": false, "local_version": local_version, "latest_version": null, "message": format!("Could not fetch latest release: {}", e) }),
    };

    let update_available = compare_versions(&local_version, &latest_version);

    json!({
        "update_available": update_available,
        "local_version": local_version,
        "latest_version": latest_version
    })
}

// Legacy Scrcpy helpers preserved for backwards compatibility
#[derive(Debug, Serialize, Deserialize)]
pub struct AdbDevice {
    pub id: String,
    pub model: String,
    pub state: String,
}

#[derive(Debug, Serialize, Clone)]
pub struct DownloadProgress {
    pub percent: f32,
    pub status: String,
}

pub fn get_bin_dir(app: &AppHandle) -> Result<std::path::PathBuf, String> {
    let app_dir = app.path().app_data_dir().map_err(|e| e.to_string())?;
    let bin_dir = app_dir.join("bin");
    std::fs::create_dir_all(&bin_dir).map_err(|e| e.to_string())?;
    Ok(bin_dir)
}

pub fn resolve_binary_cmd(app: &AppHandle, name: &str) -> StdCommand {
    let exec_name = if cfg!(target_os = "windows") {
        format!("{}.exe", name)
    } else {
        name.to_string()
    };

    let system_check = if cfg!(target_os = "windows") {
        StdCommand::new("where").arg(name).output()
    } else {
        StdCommand::new("which").arg(name).output()
    };

    let is_in_system = system_check.map(|out| out.status.success()).unwrap_or(false);

    let mut cmd = if is_in_system {
        StdCommand::new(name)
    } else if let Ok(bin_dir) = get_bin_dir(app) {
        let local_path = bin_dir.join(&exec_name);
        if local_path.exists() {
            StdCommand::new(local_path)
        } else {
            StdCommand::new(name)
        }
    } else {
        StdCommand::new(name)
    };

    if let Ok(bin_dir) = get_bin_dir(app) {
        if let Some(path_env) = std::env::var_os("PATH") {
            let mut paths = std::env::split_paths(&path_env).collect::<Vec<_>>();
            paths.insert(0, bin_dir);
            if let Ok(new_path) = std::env::join_paths(paths) {
                cmd.env("PATH", new_path);
            }
        }
    }

    cmd
}

#[tauri::command]
pub async fn scrcpy_check_installed(app: AppHandle) -> Result<bool, String> {
    let mut scrcpy_cmd = resolve_binary_cmd(&app, "scrcpy");
    let mut adb_cmd = resolve_binary_cmd(&app, "adb");
    let scrcpy_ok = scrcpy_cmd.arg("--version").output().map(|o| o.status.success()).unwrap_or(false);
    let adb_ok = adb_cmd.arg("version").output().map(|o| o.status.success()).unwrap_or(false);
    Ok(scrcpy_ok && adb_ok)
}

#[tauri::command]
pub async fn scrcpy_download_dependencies(app: AppHandle) -> Result<String, String> {
    let bin_dir = get_bin_dir(&app)?;
    let _ = app.emit("scrcpy-download-progress", DownloadProgress {
        percent: 5.0,
        status: "Starting download of Scrcpy & ADB tools...".to_string(),
    });

    let download_url = if cfg!(target_os = "windows") {
        "https://github.com/Genymobile/scrcpy/releases/download/v3.1/scrcpy-win64-v3.1.zip"
    } else if cfg!(target_os = "macos") {
        "https://github.com/Genymobile/scrcpy/releases/download/v3.1/scrcpy-mac-v3.1.zip"
    } else {
        return Err("Linux requires system package install: sudo apt install scrcpy adb".to_string());
    };

    let client = reqwest::Client::builder()
        .user_agent("ShanuSend/1.0")
        .build()
        .map_err(|e| e.to_string())?;

    let res = client.get(download_url).send().await.map_err(|e| format!("Download request failed: {}", e))?;
    if !res.status().is_success() {
        return Err(format!("Server returned HTTP status: {}", res.status()));
    }

    let total_size = res.content_length().unwrap_or(30_000_000);
    let mut downloaded: u64 = 0;
    let mut stream = res.bytes_stream();
    let zip_file_path = bin_dir.join("scrcpy_temp.zip");
    let mut file = tokio::fs::File::create(&zip_file_path).await.map_err(|e| e.to_string())?;

    use futures_util::StreamExt;
    use tokio::io::AsyncWriteExt;

    while let Some(item) = stream.next().await {
        let chunk = item.map_err(|e| format!("Error downloading chunk: {}", e))?;
        file.write_all(&chunk).await.map_err(|e| format!("Write failed: {}", e))?;
        downloaded += chunk.len() as u64;
        let percent = (downloaded as f32 / total_size as f32 * 75.0).min(75.0);
        let _ = app.emit("scrcpy-download-progress", DownloadProgress {
            percent: 10.0 + percent,
            status: format!("Downloading... ({:.1} MB / {:.1} MB)", downloaded as f64 / 1_048_576.0, total_size as f64 / 1_048_576.0),
        });
    }
    file.flush().await.map_err(|e| e.to_string())?;
    drop(file);

    let _ = app.emit("scrcpy-download-progress", DownloadProgress {
        percent: 88.0,
        status: "Extracting binaries into app directory...".to_string(),
    });

    let zip_file = std::fs::File::open(&zip_file_path).map_err(|e| e.to_string())?;
    let mut archive = zip::ZipArchive::new(zip_file).map_err(|e| format!("Invalid zip archive: {}", e))?;

    for i in 0..archive.len() {
        let mut file = archive.by_index(i).map_err(|e| e.to_string())?;
        let outpath = match file.enclosed_name() {
            Some(path) => {
                let file_name = path.file_name().unwrap_or_default();
                if file_name.to_str().unwrap_or("").is_empty() {
                    continue;
                }
                bin_dir.join(file_name)
            }
            None => continue,
        };

        if (*file.name()).ends_with('/') {
            std::fs::create_dir_all(&outpath).ok();
        } else {
            if let Some(p) = outpath.parent() {
                if !p.exists() {
                    std::fs::create_dir_all(p).ok();
                }
            }
            let mut outfile = std::fs::File::create(&outpath).map_err(|e| e.to_string())?;
            std::io::copy(&mut file, &mut outfile).map_err(|e| e.to_string())?;
        }
    }

    let _ = std::fs::remove_file(&zip_file_path);

    let _ = app.emit("scrcpy-download-progress", DownloadProgress {
        percent: 100.0,
        status: "Scrcpy & ADB tools installed and configured!".to_string(),
    });

    Ok("Dependencies downloaded and installed successfully!".to_string())
}

#[tauri::command]
pub async fn scrcpy_list_adb_devices(app: AppHandle) -> Result<Vec<AdbDevice>, String> {
    let output = resolve_binary_cmd(&app, "adb")
        .args(["devices", "-l"])
        .output()
        .map_err(|e| format!("Failed to run adb: {}", e))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut devices = Vec::new();

    for line in stdout.lines().skip(1) {
        let line = line.trim();
        if line.is_empty() { continue; }
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 2 {
            let id = parts[0].to_string();
            let state = parts[1].to_string();
            let model = parts.iter()
                .find(|p| p.starts_with("model:"))
                .map(|p| p.trim_start_matches("model:").to_string())
                .unwrap_or_else(|| "Android Device".to_string());
            devices.push(AdbDevice { id, model, state });
        }
    }

    Ok(devices)
}

#[tauri::command]
pub async fn scrcpy_adb_connect(app: AppHandle, address: String) -> Result<String, String> {
    let output = resolve_binary_cmd(&app, "adb")
        .args(["connect", &address])
        .output()
        .map_err(|e| e.to_string())?;

    let result = String::from_utf8_lossy(&output.stdout).to_string();
    Ok(result)
}

#[tauri::command]
pub async fn scrcpy_adb_pair(app: AppHandle, address: String, code: String) -> Result<String, String> {
    let output = resolve_binary_cmd(&app, "adb")
        .args(["pair", &address, &code])
        .output()
        .map_err(|e| e.to_string())?;

    let result = String::from_utf8_lossy(&output.stdout).to_string();
    Ok(result)
}

#[tauri::command]
pub async fn scrcpy_start_mirror(
    app: AppHandle,
    device_id: Option<String>,
    max_size: Option<u32>,
    bit_rate: Option<u32>,
    fps: Option<u32>,
    video_codec: Option<String>,
    audio_codec: Option<String>,
    camera_mode: Option<bool>,
    camera_facing: Option<String>,
    stay_awake: Option<bool>,
    turn_screen_off: Option<bool>,
    show_touches: Option<bool>,
    otg_mode: Option<bool>,
    record: Option<bool>,
) -> Result<String, String> {
    let mut config = ScrcpyConfig::default();
    if let Some(id) = device_id { config.device = id; }
    if let Some(ms) = max_size { config.res = Some(ms.to_string()); }
    if let Some(br) = bit_rate { config.bitrate = Some(br); }
    if let Some(f) = fps { config.fps = Some(f); }
    if let Some(vc) = video_codec { config.codec = Some(vc); }
    if let Some(ac) = audio_codec { config.audio_codec = Some(ac); }
    if let Some(cm) = camera_mode {
        if cm { config.session_mode = "camera".to_string(); }
    }
    if let Some(cf) = camera_facing { config.camera_facing = Some(cf); }
    if let Some(sa) = stay_awake { config.stay_awake = Some(sa); }
    if let Some(to) = turn_screen_off { config.turn_off = Some(to); }
    if let Some(st) = show_touches { config.show_touches = Some(st); }
    if let Some(om) = otg_mode { config.otg_pure = Some(om); }
    if let Some(r) = record { config.record = Some(r); }

    let args = build_scrcpy_args(&config, None, None);
    let child = resolve_binary_cmd(&app, "scrcpy")
        .args(&args)
        .spawn()
        .map_err(|e| format!("Failed to launch scrcpy: {}. Try clicking Auto Install Engine.", e))?;

    Ok(format!("Scrcpy process launched (PID: {})", child.id()))
}

#[tauri::command]
pub async fn scrcpy_adb_send_keyevent(app: AppHandle, device_id: Option<String>, keycode: u32) -> Result<String, String> {
    let mut cmd = resolve_binary_cmd(&app, "adb");
    if let Some(ref id) = device_id {
        cmd.args(["-s", id]);
    }
    cmd.args(["shell", "input", "keyevent", &keycode.to_string()]);
    let output = cmd.output().map_err(|e| format!("ADB keyevent failed: {}", e))?;
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

#[tauri::command]
pub async fn scrcpy_adb_shell(app: AppHandle, device_id: Option<String>, command: String) -> Result<String, String> {
    let mut cmd = resolve_binary_cmd(&app, "adb");
    if let Some(ref id) = device_id {
        cmd.args(["-s", id]);
    }
    cmd.args(["shell", &command]);
    let output = cmd.output().map_err(|e| format!("ADB shell failed: {}", e))?;
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}
