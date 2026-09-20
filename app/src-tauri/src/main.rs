#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod state;

use shanusend_core::discovery;
use shanusend_core::models::{Device, DeviceType};
use shanusend_core::server::{DeviceInfo, ServerEvent, ServerState};
use state::AppState;
use tauri::{Emitter, Manager};
use tracing::info;

fn main() {
    std::panic::set_hook(Box::new(|info| {
        let log_file = std::env::temp_dir().join("shanusend_crash.log");
        let _ = std::fs::write(&log_file, format!("PANIC: {info:?}\n"));
        let _ = std::fs::write("shanusend_crash.log", format!("PANIC: {info:?}\n"));
    }));

    let _ = tracing_subscriber::fmt().try_init();

    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let app_handle = app.handle().clone();
            let app_data_dir = app
                .path()
                .app_data_dir()
                .unwrap_or_else(|_| std::env::temp_dir().join("shanusend"));

            let (alias, cert) = state::load_or_create_identity(&app_data_dir);
            let port = discovery::DEFAULT_PORT;

            let device_info = DeviceInfo {
                alias: alias.clone(),
                version: "2.1".to_string(),
                device_model: Some("Desktop".to_string()),
                device_type: DeviceType::Desktop,
                fingerprint: cert.fingerprint.clone(),
            };

            let (server_state, mut server_events) =
                ServerState::new(device_info, port, false, None, state::default_save_dir());

            let history_path = app_data_dir.join("history.json");
            let shanu_app_handle = app_handle.clone();
            let kde_engine = std::sync::Arc::new(shanusend_core::shanuconnect::ShanuConnectEngine::new_with_callback(
                alias.clone(),
                std::sync::Arc::new(move |event_type, body| {
                    let payload = serde_json::json!({
                        "type": event_type,
                        "body": body,
                    });
                    let _ = shanu_app_handle.emit("shanuconnect-event", &payload);
                    let _ = shanu_app_handle.emit("kdeconnect-event", &payload);
                }),
            ));
            tauri::async_runtime::spawn(kde_engine.clone().start_listeners());

            app.manage(AppState {
                server: server_state.clone(),
                port,
                history_path: history_path.clone(),
                kde_engine,
            });

            // --- Receiving side: HTTP server -------------------------------
            let router = shanusend_core::server::build_router(server_state.clone());
            tauri::async_runtime::spawn(async move {
                let listener = match tokio::net::TcpListener::bind(("0.0.0.0", port)).await {
                    Ok(l) => l,
                    Err(e) => {
                        tracing::error!("failed to bind HTTP server on port {port}: {e}");
                        return;
                    }
                };
                info!("ShanuSend HTTP server listening on 0.0.0.0:{port}");
                if let Err(e) = axum::serve(listener, router).await {
                    tracing::error!("HTTP server error: {e}");
                }
            });

            // --- Forward server-side events (incoming requests, upload
            // progress) to the frontend as Tauri events, and persist
            // completed/failed receives to history. -------------------------
            let events_handle = app_handle.clone();
            let history_path_for_receive = history_path.clone();
            tauri::async_runtime::spawn(async move {
                // ServerEvent::UploadComplete/Failed only carry session_id +
                // file_id, not the original file name or sender — so we
                // remember those from the IncomingRequest event that always
                // precedes them for the same session.
                let mut pending_meta: std::collections::HashMap<
                    (String, String),
                    (String, String, u64),
                > = std::collections::HashMap::new();

                while let Some(event) = server_events.recv().await {
                    let event_name = match &event {
                        ServerEvent::IncomingRequest { .. } => "incoming-request",
                        ServerEvent::UploadProgress { .. } => "upload-progress",
                        ServerEvent::UploadComplete { .. } => "upload-complete",
                        ServerEvent::UploadFailed { .. } => "upload-failed",
                        ServerEvent::SessionCancelled { .. } => "session-cancelled",
                    };
                    let _ = events_handle.emit(event_name, &event);

                    match &event {
                        ServerEvent::IncomingRequest {
                            session_id,
                            sender_alias,
                            files,
                        } => {
                            for (file_id, file) in files {
                                pending_meta.insert(
                                    (session_id.clone(), file_id.clone()),
                                    (file.file_name.clone(), sender_alias.clone(), file.size),
                                );
                            }
                        }
                        ServerEvent::UploadComplete {
                            session_id,
                            file_id,
                            ..
                        } => {
                            if let Some((file_name, sender_alias, size)) =
                                pending_meta.remove(&(session_id.clone(), file_id.clone()))
                            {
                                let record = shanusend_core::history::TransferRecord::new(
                                    shanusend_core::history::Direction::Received,
                                    sender_alias,
                                    file_name,
                                    size,
                                    shanusend_core::history::RecordStatus::Done,
                                    None,
                                );
                                let _ = shanusend_core::history::append(
                                    &history_path_for_receive,
                                    record,
                                )
                                .await;
                            }
                        }
                        ServerEvent::UploadFailed {
                            session_id,
                            file_id,
                            ..
                        } => {
                            if let Some((file_name, sender_alias, size)) =
                                pending_meta.remove(&(session_id.clone(), file_id.clone()))
                            {
                                let record = shanusend_core::history::TransferRecord::new(
                                    shanusend_core::history::Direction::Received,
                                    sender_alias,
                                    file_name,
                                    size,
                                    shanusend_core::history::RecordStatus::Failed,
                                    None,
                                );
                                let _ = shanusend_core::history::append(
                                    &history_path_for_receive,
                                    record,
                                )
                                .await;
                            }
                        }
                        _ => {}
                    }
                }
            });

            // --- Sending side: multicast discovery listener -----------------
            let discovery_events_handle = app_handle.clone();
            let discovery_alias = alias.clone();
            tauri::async_runtime::spawn(async move {
                let (mut discovery_rx, _discovery_handle) = discovery::listen();
                while let Some(evt) = discovery_rx.recv().await {
                    // Don't surface our own announcements back to ourselves.
                    if evt.dto.fingerprint == cert.fingerprint {
                        continue;
                    }
                    let device = Device {
                        ip: evt.from_addr.ip().to_string(),
                        port: evt.dto.port.unwrap_or(discovery::DEFAULT_PORT),
                        https: matches!(
                            evt.dto.protocol,
                            Some(shanusend_core::models::ProtocolType::Https)
                        ),
                        alias: evt.dto.alias.clone(),
                        version: evt.dto.version.clone().unwrap_or_default(),
                        device_model: evt.dto.device_model.clone(),
                        device_type: evt.dto.device_type.unwrap_or(DeviceType::Desktop),
                        fingerprint: evt.dto.fingerprint.clone(),
                        download: evt.dto.download.unwrap_or(false),
                        trusted: false,
                    };
                    let _ = discovery_events_handle.emit("device-discovered", &device);

                    // Per protocol: reply directly (unicast) rather than
                    // re-broadcasting, to keep multicast traffic low.
                    if evt
                        .dto
                        .announce
                        .unwrap_or(evt.dto.announcement.unwrap_or(false))
                    {
                        let self_dto = discovery::build_self_announcement(
                            &discovery_alias,
                            &cert.fingerprint,
                            port,
                            false,
                            Some("Desktop".to_string()),
                            DeviceType::Desktop,
                            false,
                        );
                        let _ = discovery::reply_to(&self_dto, evt.from_addr).await;
                    }
                }
            });

            // --- Periodic self-announce --------------------------------------
            let announce_alias = alias.clone();
            let announce_fingerprint = server_state.device.fingerprint.clone();
            tauri::async_runtime::spawn(async move {
                loop {
                    let dto = discovery::build_self_announcement(
                        &announce_alias,
                        &announce_fingerprint,
                        port,
                        false,
                        Some("Desktop".to_string()),
                        DeviceType::Desktop,
                        true,
                    );
                    let _ = discovery::announce(&dto).await;
                    tokio::time::sleep(std::time::Duration::from_secs(5)).await;
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::get_self_info,
            commands::refresh_discovery,
            commands::send_files,
            commands::respond_prepare_upload,
            commands::get_settings,
            commands::set_pin,
            commands::set_device_trusted,
            commands::set_save_dir,
            commands::rename_device,
            commands::list_history,
            commands::clear_history,
            commands::shanuconnect_send_mousepad,
            commands::shanuconnect_trigger_find_phone,
            commands::shanuconnect_lock_device,
            commands::shanuconnect_run_remote_command,
            commands::shanuconnect_send_sms,
            commands::shanuconnect_mpris_control,
            commands::kdeconnect_send_mousepad,
            commands::kdeconnect_trigger_find_phone,
            commands::kdeconnect_lock_device,
            commands::kdeconnect_run_remote_command,
            commands::kdeconnect_send_sms,
            commands::kdeconnect_mpris_control,
            commands::scrcpy_check_installed,
            commands::scrcpy_list_adb_devices,
            commands::scrcpy_adb_connect,
            commands::scrcpy_adb_pair,
            commands::scrcpy_start_mirror,
            commands::quickshare_generate_ukey2_pin,
        ])
        .run(tauri::generate_context!())
        .expect("error while running ShanuSend");
}
