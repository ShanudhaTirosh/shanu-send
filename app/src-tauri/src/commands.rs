use crate::state::AppState;
use serde::{Deserialize, Serialize};
use shanusend_core::discovery;
use shanusend_core::models::{Device, RegisterDto};
use shanusend_core::transfer::{self, LocalFile, SendEvent};
use tauri::{Emitter, Manager, State};

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

/// Re-sends our multicast announcement so peers (and we, seeing their
/// replies) refresh the device list. Discovery itself is push-based and
/// already running in the background (see main.rs); this just re-triggers
/// the "here I am" broadcast for a manual "Rescan" click.
#[tauri::command]
pub async fn refresh_discovery(state: State<'_, AppState>) -> Result<(), String> {
    let dto = discovery::build_self_announcement(
        &state.server.device.alias,
        &state.server.device.fingerprint,
        state.port,
        false, // HTTPS lands in Phase 3; announcing HTTP for now, see client/mod.rs
        state.server.device.device_model.clone(),
        state.server.device.device_type,
        true,
    );
    discovery::announce(&dto).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn send_files(
    app: tauri::AppHandle,
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

    // Keep file_name/size/path around by id for the history record we write
    // once each file's SendEvent resolves — the event stream itself only
    let mut local_files: Vec<LocalFile> = Vec::new();
    let mut file_meta: std::collections::HashMap<String, (String, u64, String)> = std::collections::HashMap::new();

    for f in files {
        let path_buf = std::path::PathBuf::from(&f.path);
        let mut actual_size = f.size;

        if let Ok(meta) = std::fs::metadata(&path_buf) {
            actual_size = meta.len();
        } else {
            tracing::warn!("File path metadata warning for path {:?}: file may not exist", path_buf);
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

/// Called by the UI after the user accepts/rejects an incoming transfer
/// prompt (wired up once the "IncomingRequest" toast is built in Phase 2 UI).
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

/// Takes effect immediately — no restart needed, unlike `rename_device`.
#[tauri::command]
pub async fn set_pin(state: State<'_, AppState>, pin: Option<String>) -> Result<(), String> {
    // Treat an empty string the same as "no PIN" so a cleared input field
    // disables protection instead of requiring an empty PIN.
    let normalized = pin.filter(|p| !p.trim().is_empty());
    state.server.set_pin(normalized).await;
    Ok(())
}

/// Called after the frontend's folder picker (tauri-plugin-dialog) returns a
/// path. We don't invoke the dialog from Rust — it's simpler and more
/// idiomatic to let the JS side call `open()` from `@tauri-apps/plugin-dialog`
/// directly and hand us the result, rather than routing through a command.
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

/// Persists a new display name for next launch. We deliberately don't apply
/// this live: the device's self-signed cert (and therefore its fingerprint —
/// the thing peers pin as "trusted") is derived from the alias at generation
/// time, so a live rename would silently break existing trust relationships.
/// A restart regenerates the identity cleanly instead.
#[tauri::command]
pub fn rename_device(app: tauri::AppHandle, new_alias: String) -> Result<(), String> {
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

#[tauri::command]
pub async fn kdeconnect_send_mousepad(
    state: State<'_, AppState>,
    dx: Option<f32>,
    dy: Option<f32>,
    click: Option<String>,
) -> Result<(), String> {
    tracing::info!("KDEConnect mousepad event: dx={:?}, dy={:?}, click={:?}", dx, dy, click);
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
    tracing::info!("KDEConnect Find My Phone triggered: ring={}", ring);
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
    tracing::info!("KDEConnect Lock Device triggered: locked={}", locked);
    let packet = shanusend_core::kdeconnect::KdePacket::new(
        "kdeconnect.lockdevice",
        serde_json::json!({ "isLocked": locked }),
    );
    let _ = state.kde_engine.process_incoming_packet(packet).await;
    if locked {
        #[cfg(target_os = "windows")]
        {
            let _ = std::process::Command::new("rundll32.exe")
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
    tracing::info!("KDEConnect Remote Command Requested: {}", command);
    let packet = shanusend_core::kdeconnect::KdePacket::new(
        "kdeconnect.runcommand",
        serde_json::json!({ "key": command }),
    );
    let _ = state.kde_engine.process_incoming_packet(packet).await;
    match command.trim() {
        "lock" | "LockWorkStation" => {
            #[cfg(target_os = "windows")]
            {
                let _ = std::process::Command::new("rundll32.exe")
                    .args(["user32.dll,LockWorkStation"])
                    .spawn();
            }
            Ok("Screen locked successfully".to_string())
        }
        "ping" => Ok("pong".to_string()),
        cmd => {
            tracing::warn!("Blocked execution of unauthorized command: {}", cmd);
            Err("Command execution restricted to pre-approved allow-list for security.".to_string())
        }
    }
}

#[tauri::command]
pub async fn kdeconnect_send_sms(
    state: State<'_, AppState>,
    recipient: String,
    body: String,
) -> Result<(), String> {
    tracing::info!("KDEConnect Send SMS to {}: {}", recipient, body);
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
    tracing::info!("ShanuConnect MPRIS Action: {} (volume: {:?})", action, volume);
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
    tracing::info!("ShanuConnect System Volume: {}", volume);
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
    tracing::info!("ShanuConnect Clipboard Sync: {} bytes", content.len());
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
    tracing::info!("ShanuConnect Pair Request: {}", pair);
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
    tracing::info!("ShanuConnect Notification Reply to {}: {}", notification_id, reply_message);
    let packet = shanusend_core::shanuconnect::ShanuPacket::new(
        "shanuconnect.notifications.reply",
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
    tracing::info!("ShanuConnect Telephony Action {}: {:?}", action, phone_number);
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
    tracing::info!("ShanuConnect SFTP Request: {:?}", path);
    let packet = shanusend_core::shanuconnect::ShanuPacket::new(
        "shanuconnect.sftp",
        serde_json::json!({ "startBrowsing": true, "path": path.unwrap_or_else(|| "/storage/emulated/0".to_string()) }),
    );
    let _ = state.kde_engine.process_incoming_packet(packet).await;
    Ok(())
}

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

pub fn get_bin_dir(app: &tauri::AppHandle) -> Result<std::path::PathBuf, String> {
    let app_dir = app.path().app_data_dir().map_err(|e| e.to_string())?;
    let bin_dir = app_dir.join("bin");
    std::fs::create_dir_all(&bin_dir).map_err(|e| e.to_string())?;
    Ok(bin_dir)
}

pub fn resolve_binary_cmd(app: &tauri::AppHandle, name: &str) -> std::process::Command {
    let exec_name = if cfg!(target_os = "windows") {
        format!("{}.exe", name)
    } else {
        name.to_string()
    };

    let system_check = if cfg!(target_os = "windows") {
        std::process::Command::new("where").arg(name).output()
    } else {
        std::process::Command::new("which").arg(name).output()
    };

    let is_in_system = system_check.map(|out| out.status.success()).unwrap_or(false);

    let mut cmd = if is_in_system {
        std::process::Command::new(name)
    } else if let Ok(bin_dir) = get_bin_dir(app) {
        let local_path = bin_dir.join(&exec_name);
        if local_path.exists() {
            std::process::Command::new(local_path)
        } else {
            std::process::Command::new(name)
        }
    } else {
        std::process::Command::new(name)
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
pub async fn scrcpy_check_installed(app: tauri::AppHandle) -> Result<bool, String> {
    let mut scrcpy_cmd = resolve_binary_cmd(&app, "scrcpy");
    let mut adb_cmd = resolve_binary_cmd(&app, "adb");

    let scrcpy_ok = scrcpy_cmd.arg("--version").output().map(|o| o.status.success()).unwrap_or(false);
    let adb_ok = adb_cmd.arg("version").output().map(|o| o.status.success()).unwrap_or(false);

    Ok(scrcpy_ok && adb_ok)
}

#[tauri::command]
pub async fn scrcpy_download_dependencies(app: tauri::AppHandle) -> Result<String, String> {
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
pub async fn scrcpy_list_adb_devices(app: tauri::AppHandle) -> Result<Vec<AdbDevice>, String> {
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
pub async fn scrcpy_adb_connect(app: tauri::AppHandle, address: String) -> Result<String, String> {
    let output = resolve_binary_cmd(&app, "adb")
        .args(["connect", &address])
        .output()
        .map_err(|e| e.to_string())?;

    let result = String::from_utf8_lossy(&output.stdout).to_string();
    Ok(result)
}

#[tauri::command]
pub async fn scrcpy_adb_pair(app: tauri::AppHandle, address: String, code: String) -> Result<String, String> {
    let output = resolve_binary_cmd(&app, "adb")
        .args(["pair", &address, &code])
        .output()
        .map_err(|e| e.to_string())?;

    let result = String::from_utf8_lossy(&output.stdout).to_string();
    Ok(result)
}

#[tauri::command]
pub async fn scrcpy_start_mirror(
    app: tauri::AppHandle,
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
    let mut config = shanusend_core::scrcpy::ScrcpyConfig::default();
    if let Some(id) = device_id { config.device_serial = id; }
    if let Some(ms) = max_size { config.max_size = ms; }
    if let Some(br) = bit_rate { config.bit_rate_mbps = br; }
    if let Some(f) = fps { config.max_fps = f; }
    if let Some(vc) = video_codec {
        match vc.to_lowercase().as_str() {
            "h265" => config.video_codec = shanusend_core::scrcpy::VideoCodec::H265,
            "av1" => config.video_codec = shanusend_core::scrcpy::VideoCodec::AV1,
            _ => config.video_codec = shanusend_core::scrcpy::VideoCodec::H264,
        }
    }
    if let Some(ac) = audio_codec {
        match ac.to_lowercase().as_str() {
            "aac" => config.audio_codec = shanusend_core::scrcpy::AudioCodec::Aac,
            "flac" => config.audio_codec = shanusend_core::scrcpy::AudioCodec::Flac,
            "raw" => config.audio_codec = shanusend_core::scrcpy::AudioCodec::Raw,
            "disabled" => config.audio_codec = shanusend_core::scrcpy::AudioCodec::Disabled,
            _ => config.audio_codec = shanusend_core::scrcpy::AudioCodec::Opus,
        }
    }
    if let Some(cm) = camera_mode { config.camera_mode = cm; }
    if let Some(cf) = camera_facing {
        if cf.to_lowercase() == "front" {
            config.camera_facing = shanusend_core::scrcpy::CameraFacing::Front;
        } else {
            config.camera_facing = shanusend_core::scrcpy::CameraFacing::Back;
        }
    }
    if let Some(sa) = stay_awake { config.stay_awake = sa; }
    if let Some(to) = turn_screen_off { config.turn_screen_off = to; }
    if let Some(st) = show_touches { config.show_touches = st; }
    if let Some(om) = otg_mode { config.otg_mode = om; }
    if let Some(r) = record {
        if r {
            config.record_format = shanusend_core::scrcpy::RecordFormat::Mp4;
        }
    }

    let args = config.build_cli_args();
    tracing::info!("Launching scrcpy with args: {:?}", args);
    let child = resolve_binary_cmd(&app, "scrcpy")
        .args(&args)
        .spawn()
        .map_err(|e| format!("Failed to launch scrcpy: {}. Try clicking Auto Install Engine.", e))?;

    Ok(format!("Scrcpy process launched (PID: {})", child.id()))
}

#[tauri::command]
pub async fn scrcpy_adb_send_keyevent(app: tauri::AppHandle, device_id: Option<String>, keycode: u32) -> Result<String, String> {
    let mut cmd = resolve_binary_cmd(&app, "adb");
    if let Some(ref id) = device_id {
        cmd.args(["-s", id]);
    }
    cmd.args(["shell", "input", "keyevent", &keycode.to_string()]);
    let output = cmd.output().map_err(|e| format!("ADB keyevent failed: {}", e))?;
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

#[tauri::command]
pub async fn scrcpy_adb_shell(app: tauri::AppHandle, device_id: Option<String>, command: String) -> Result<String, String> {
    let mut cmd = resolve_binary_cmd(&app, "adb");
    if let Some(ref id) = device_id {
        cmd.args(["-s", id]);
    }
    cmd.args(["shell", &command]);
    let output = cmd.output().map_err(|e| format!("ADB shell failed: {}", e))?;
    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

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


