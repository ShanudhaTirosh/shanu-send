//! Sender-side orchestration: given a target `Device` and a list of local
//! files, run prepare-upload then stream each accepted file, emitting
//! progress events the UI can subscribe to.
//!
//! v1 reads whole files into memory before sending (fine up to a few hundred
//! MB). Chunked/resumable streaming is a Phase 5 enhancement (see plan §3) —
//! the event shape below is already resume-friendly (`bytes_sent` is an
//! absolute offset) so upgrading later won't change the UI contract.

use crate::client;
use crate::models::{Device, FileDto, RegisterDto};
use serde::Serialize;
use std::collections::HashMap;
use std::path::PathBuf;
use tokio::sync::mpsc;

#[derive(Debug, Clone, Serialize)]
pub struct LocalFile {
    pub id: String,
    pub path: PathBuf,
    pub file_name: String,
    pub size: u64,
    pub mime: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type")]
pub enum SendEvent {
    Preparing,
    Rejected,
    PinRequired,
    FileProgress {
        file_id: String,
        bytes_sent: u64,
        total_bytes: u64,
        speed_bytes_per_sec: u64,
        eta_seconds: u64,
    },
    FileDone {
        file_id: String,
    },
    FileFailed {
        file_id: String,
        reason: String,
    },
    AllDone,
}

pub async fn send_files(
    target: Device,
    self_info: RegisterDto,
    files: Vec<LocalFile>,
    pin: Option<String>,
    events: mpsc::Sender<SendEvent>,
) {
    let _ = events.send(SendEvent::Preparing).await;

    let file_dtos: HashMap<String, FileDto> = files
        .iter()
        .map(|f| {
            (
                f.id.clone(),
                FileDto {
                    id: f.id.clone(),
                    file_name: f.file_name.clone(),
                    size: f.size,
                    file_type: f.mime.clone(),
                    hash: None,
                    preview: None,
                },
            )
        })
        .collect();

    let prepare = client::request_upload(&target, self_info, file_dtos, pin.as_deref()).await;

    let response = match prepare {
        Ok(r) => r,
        Err(client::ClientError::PinRequired) => {
            let _ = events.send(SendEvent::PinRequired).await;
            return;
        }
        Err(_) => {
            let _ = events.send(SendEvent::Rejected).await;
            return;
        }
    };

    for file in &files {
        let Some(token) = response.files.get(&file.id) else {
            // Receiver didn't accept this particular file.
            continue;
        };

        let handle = match tokio::fs::File::open(&file.path).await {
            Ok(f) => f,
            Err(e) => {
                let _ = events
                    .send(SendEvent::FileFailed {
                        file_id: file.id.clone(),
                        reason: e.to_string(),
                    })
                    .await;
                continue;
            }
        };

        let total = file.size;
        let start_time = std::time::Instant::now();

        let _ = events
            .send(SendEvent::FileProgress {
                file_id: file.id.clone(),
                bytes_sent: 0,
                total_bytes: total,
                speed_bytes_per_sec: 0,
                eta_seconds: 0,
            })
            .await;

        match client::upload_file_stream(&target, &response.session_id, &file.id, token, handle)
            .await
        {
            Ok(()) => {
                let elapsed_secs = start_time.elapsed().as_secs_f64();
                let speed = if elapsed_secs > 0.0 {
                    (total as f64 / elapsed_secs) as u64
                } else {
                    0
                };

                let _ = events
                    .send(SendEvent::FileProgress {
                        file_id: file.id.clone(),
                        bytes_sent: total,
                        total_bytes: total,
                        speed_bytes_per_sec: speed,
                        eta_seconds: 0,
                    })
                    .await;
                let _ = events
                    .send(SendEvent::FileDone {
                        file_id: file.id.clone(),
                    })
                    .await;
            }
            Err(e) => {
                let _ = events
                    .send(SendEvent::FileFailed {
                        file_id: file.id.clone(),
                        reason: e.to_string(),
                    })
                    .await;
            }
        }
    }

    let _ = events.send(SendEvent::AllDone).await;
}
