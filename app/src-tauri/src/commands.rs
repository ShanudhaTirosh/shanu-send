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
}

#[tauri::command]
pub fn get_self_info(state: State<AppState>) -> SelfInfo {
    SelfInfo {
        alias: state.server.device.alias.clone(),
        fingerprint: state.server.device.fingerprint.clone(),
        port: state.port,
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
    // carries file_id, same reasoning as the receive-side history wiring.
    let file_meta: std::collections::HashMap<String, (String, u64, String)> = files
        .iter()
        .map(|f| (f.id.clone(), (f.file_name.clone(), f.size, f.path.clone())))
        .collect();

    let local_files: Vec<LocalFile> = files
        .into_iter()
        .map(|f| LocalFile {
            id: f.id,
            path: f.path.into(),
            file_name: f.file_name,
            size: f.size,
            mime: f.mime,
        })
        .collect();

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
