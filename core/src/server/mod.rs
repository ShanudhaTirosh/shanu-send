//! HTTP server implementing the LocalSend v2.1 receiving side:
//!   GET  /api/localsend/v2/info
//!   POST /api/localsend/v2/register
//!   POST /api/localsend/v2/prepare-upload
//!   POST /api/localsend/v2/upload?sessionId=&fileId=&token=
//!   POST /api/localsend/v2/cancel?sessionId=
//!
//! The UI layer (Tauri commands) drives accept/reject decisions and receives
//! progress via the `events` channel rather than this module reaching into
//! the UI directly — keeps `core` UI-framework-agnostic.

use crate::models::{FileDto, PrepareUploadRequestDto, PrepareUploadResponseDto, RegisterDto};
use axum::{
    body::Body,
    extract::{Multipart, Query, State},
    http::StatusCode,
    response::Html,
    routing::{get, post},
    Json, Router,
};
use futures_util::StreamExt;
use serde::Deserialize;
use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use tokio::io::AsyncWriteExt;
use tokio::sync::{mpsc, oneshot, Mutex};
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct DeviceInfo {
    pub alias: String,
    pub version: String,
    pub device_model: Option<String>,
    pub device_type: crate::models::DeviceType,
    pub fingerprint: String,
}

impl DeviceInfo {
    fn to_register_dto(&self, port: u16, https: bool) -> RegisterDto {
        RegisterDto {
            alias: self.alias.clone(),
            version: Some(self.version.clone()),
            device_model: self.device_model.clone(),
            device_type: Some(self.device_type),
            fingerprint: self.fingerprint.clone(),
            port: Some(port),
            protocol: Some(if https {
                crate::models::ProtocolType::Https
            } else {
                crate::models::ProtocolType::Http
            }),
            download: Some(false),
        }
    }
}

/// Emitted to the UI layer so it can render toasts/progress bars. The UI
/// reacts to `IncomingRequest` by eventually calling
/// `ServerState::respond_prepare_upload`.
#[derive(Debug, Clone, serde::Serialize)]
#[serde(tag = "type")]
pub enum ServerEvent {
    IncomingRequest {
        session_id: String,
        sender_alias: String,
        files: HashMap<String, FileDto>,
    },
    UploadProgress {
        session_id: String,
        file_id: String,
        received_bytes: u64,
        total_bytes: u64,
        speed_bytes_per_sec: u64,
        eta_seconds: u64,
    },
    UploadComplete {
        session_id: String,
        file_id: String,
        saved_path: PathBuf,
    },
    UploadFailed {
        session_id: String,
        file_id: String,
        reason: String,
    },
    SessionCancelled {
        session_id: String,
    },
}

struct PendingSession {
    // Reserved for the upcoming transfer-history feature (Phase 5); not
    // read yet because history persistence isn't wired up in this phase.
    #[allow(dead_code)]
    sender_alias: String,
    files: HashMap<String, FileDto>,
    /// fileId -> single-use token, populated once the user accepts.
    tokens: HashMap<String, String>,
    accepted_file_ids: Option<Vec<String>>,
}

pub struct ServerState {
    pub device: DeviceInfo,
    pub port: u16,
    pub https: bool,
    /// None = no PIN required. Wrapped in a Mutex (not a plain field) so the
    /// settings UI can toggle it without an app restart.
    pub pin: Mutex<Option<String>>,
    /// Wrapped in a Mutex so the settings UI can change it without a restart.
    pub save_dir: Mutex<PathBuf>,
    /// Fingerprints the user has explicitly trusted -> auto-accept incoming requests.
    pub trusted_fingerprints: Mutex<Vec<String>>,
    sessions: Mutex<HashMap<String, PendingSession>>,
    accept_waiters: Mutex<HashMap<String, oneshot::Sender<Option<Vec<String>>>>>,
    events: mpsc::Sender<ServerEvent>,
}

impl ServerState {
    pub fn new(
        device: DeviceInfo,
        port: u16,
        https: bool,
        pin: Option<String>,
        save_dir: PathBuf,
    ) -> (Arc<Self>, mpsc::Receiver<ServerEvent>) {
        let (tx, rx) = mpsc::channel(128);
        let state = Arc::new(Self {
            device,
            port,
            https,
            pin: Mutex::new(pin),
            save_dir: Mutex::new(save_dir),
            trusted_fingerprints: Mutex::new(Vec::new()),
            sessions: Mutex::new(HashMap::new()),
            accept_waiters: Mutex::new(HashMap::new()),
            events: tx,
        });
        (state, rx)
    }

    /// Called by the UI layer once the user accepts/rejects an incoming
    /// transfer request. `accepted_file_ids = None` rejects the whole session.
    pub async fn respond_prepare_upload(
        &self,
        session_id: &str,
        accepted_file_ids: Option<Vec<String>>,
    ) {
        if let Some(waiter) = self.accept_waiters.lock().await.remove(session_id) {
            let _ = waiter.send(accepted_file_ids);
        }
    }

    /// Enables/disables PIN protection. `Some(pin)` requires that PIN on
    /// every future `prepare-upload`; `None` removes the requirement.
    pub async fn set_pin(&self, pin: Option<String>) {
        *self.pin.lock().await = pin;
    }

    pub async fn pin_enabled(&self) -> bool {
        self.pin.lock().await.is_some()
    }

    pub async fn trust_device(&self, fingerprint: String) {
        let mut trusted = self.trusted_fingerprints.lock().await;
        if !trusted.contains(&fingerprint) {
            trusted.push(fingerprint);
        }
    }

    pub async fn untrust_device(&self, fingerprint: &str) {
        self.trusted_fingerprints
            .lock()
            .await
            .retain(|f| f != fingerprint);
    }

    pub async fn list_trusted(&self) -> Vec<String> {
        self.trusted_fingerprints.lock().await.clone()
    }

    pub async fn get_save_dir(&self) -> PathBuf {
        self.save_dir.lock().await.clone()
    }

    pub async fn set_save_dir(&self, dir: PathBuf) {
        *self.save_dir.lock().await = dir;
    }
}

/// Serves `router` over HTTPS using the given self-signed cert/key (DER-encoded,
/// as produced by `crypto::generate_self_signed`). This is what makes the
/// `https: true` we announce over multicast (see `discovery::build_self_announcement`)
/// actually true — plain HTTP was a deliberate Phase 1/2 stand-in.
///
/// Gated behind the `tls` feature — see the comment on that feature in
/// Cargo.toml for why (a sandbox-only dependency version-skew issue, not a
/// problem with this code on a normal toolchain).
#[cfg(feature = "tls")]
pub async fn serve_tls(
    router: Router,
    addr: std::net::SocketAddr,
    cert_der: Vec<u8>,
    key_der: Vec<u8>,
) -> std::io::Result<()> {
    let config = axum_server::tls_rustls::RustlsConfig::from_der(vec![cert_der], key_der).await?;
    axum_server::bind_rustls(addr, config)
        .serve(router.into_make_service())
        .await
}

pub fn build_router(state: Arc<ServerState>) -> Router {
    Router::new()
        .route("/", get(webdrop_page_handler))
        .route("/web", get(webdrop_page_handler))
        .route("/api/localsend/v2/info", get(info_handler))
        .route("/api/localsend/v2/register", post(register_handler))
        .route(
            "/api/localsend/v2/prepare-upload",
            post(prepare_upload_handler),
        )
        .route("/api/localsend/v2/upload", post(upload_handler))
        .route("/api/localsend/v2/cancel", post(cancel_handler))
        .route("/webdrop", get(webdrop_page_handler))
        .route("/api/webdrop/upload", post(webdrop_upload_handler))
        .route("/api/webdrop/text", post(webdrop_text_handler))
        .with_state(state)
}

async fn info_handler(State(state): State<Arc<ServerState>>) -> Json<RegisterDto> {
    Json(state.device.to_register_dto(state.port, state.https))
}

async fn register_handler(
    State(state): State<Arc<ServerState>>,
    Json(_peer): Json<RegisterDto>,
) -> Json<RegisterDto> {
    // We don't need the peer's payload here beyond having learned about them
    // (the caller/discovery layer records it); we just reply with who we are,
    // per protocol, so the peer can add us to its device list too.
    Json(state.device.to_register_dto(state.port, state.https))
}

#[derive(Debug, Deserialize)]
struct PinQuery {
    pin: Option<String>,
}

async fn prepare_upload_handler(
    State(state): State<Arc<ServerState>>,
    Query(pin_query): Query<PinQuery>,
    Json(req): Json<PrepareUploadRequestDto>,
) -> Result<Json<PrepareUploadResponseDto>, StatusCode> {
    if let Some(expected_pin) = state.pin.lock().await.as_ref() {
        match &pin_query.pin {
            Some(provided) if crate::crypto::verify_pin(provided, expected_pin) => {}
            _ => return Err(StatusCode::UNAUTHORIZED),
        }
    }

    let session_id = Uuid::new_v4().to_string();
    let is_trusted = state
        .trusted_fingerprints
        .lock()
        .await
        .contains(&req.info.fingerprint);

    let (accept_tx, accept_rx) = oneshot::channel();

    {
        let mut sessions = state.sessions.lock().await;
        sessions.insert(
            session_id.clone(),
            PendingSession {
                sender_alias: req.info.alias.clone(),
                files: req.files.clone(),
                tokens: HashMap::new(),
                accepted_file_ids: None,
            },
        );
    }

    let accepted_ids: Option<Vec<String>> = if is_trusted {
        // Auto-accept: skip the UI round-trip entirely.
        Some(req.files.keys().cloned().collect())
    } else {
        state
            .accept_waiters
            .lock()
            .await
            .insert(session_id.clone(), accept_tx);

        let _ = state
            .events
            .send(ServerEvent::IncomingRequest {
                session_id: session_id.clone(),
                sender_alias: req.info.alias.clone(),
                files: req.files.clone(),
            })
            .await;

        // Give the user 30s to respond, matching LocalSend's UX (auto-decline on timeout).
        match tokio::time::timeout(std::time::Duration::from_secs(30), accept_rx).await {
            Ok(Ok(ids)) => ids,
            _ => None,
        }
    };

    let Some(accepted_ids) = accepted_ids else {
        state.sessions.lock().await.remove(&session_id);
        return Err(StatusCode::FORBIDDEN);
    };

    let mut sessions = state.sessions.lock().await;
    let session = sessions.get_mut(&session_id).ok_or(StatusCode::NOT_FOUND)?;

    let mut response_files = HashMap::new();
    for file_id in &accepted_ids {
        if session.files.contains_key(file_id) {
            let token = Uuid::new_v4().to_string();
            session.tokens.insert(file_id.clone(), token.clone());
            response_files.insert(file_id.clone(), token);
        }
    }
    session.accepted_file_ids = Some(accepted_ids);

    Ok(Json(PrepareUploadResponseDto {
        session_id,
        files: response_files,
    }))
}

#[derive(Debug, Deserialize)]
struct UploadQuery {
    #[serde(rename = "sessionId")]
    session_id: String,
    #[serde(rename = "fileId")]
    file_id: String,
    token: String,
}

async fn webdrop_page_handler() -> Html<&'static str> {
    Html(
        r##"<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>ShanuSend WebDrop</title>
<style>
  body { font-family: system-ui, -apple-system, sans-serif; background: #0b0f19; color: #f8fafc; display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 100vh; margin: 0; padding: 20px; }
  .card { background: #161e2e; border: 1px solid #283548; border-radius: 20px; padding: 36px; max-width: 480px; width: 100%; text-align: center; box-shadow: 0 25px 50px -12px rgba(0,0,0,0.6); }
  h1 { font-size: 24px; margin: 0 0 8px 0; display: flex; items-center; justify-content: center; gap: 8px; background: linear-gradient(135deg, #38bdf8, #818cf8); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
  p { color: #94a3b8; font-size: 14px; margin: 0 0 24px 0; }
  .dropzone { border: 2px dashed #334155; border-radius: 14px; padding: 40px 20px; cursor: pointer; transition: all 0.2s; background: #0f172a; display: flex; flex-direction: column; align-items: center; }
  .dropzone:hover { border-color: #6366f1; background: #1e1b4b; }
  .btn { background: linear-gradient(135deg, #6366f1, #4f46e5); color: white; border: none; padding: 14px 24px; border-radius: 10px; font-weight: 600; cursor: pointer; width: 100%; margin-top: 20px; font-size: 16px; transition: opacity 0.2s; }
  .btn:disabled { opacity: 0.4; cursor: not-allowed; }
  .progress { width: 100%; background: #1e293b; border-radius: 999px; height: 10px; margin-top: 20px; overflow: hidden; display: none; }
  .bar { height: 100%; background: linear-gradient(90deg, #38bdf8, #818cf8); width: 0%; transition: width 0.1s; }
  #status { margin-top: 14px; font-size: 14px; font-weight: 500; color: #38bdf8; display: flex; align-items: center; justify-content: center; gap: 6px; }
  .icon-svg { width: 44px; height: 44px; stroke: #38bdf8; fill: none; stroke-width: 2; stroke-linecap: round; stroke-linejoin: round; }
  .icon-small { width: 20px; height: 20px; vertical-align: middle; }
</style>
</head>
<body>
<div class="card">
  <h1>
    <svg class="icon-small" viewBox="0 0 24 24" fill="none" stroke="#38bdf8" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>
    ShanuSend WebDrop
  </h1>
  <p>AirDrop & Nearby Share Portal. Send files directly to this device from Safari / Chrome!</p>
  <div class="dropzone" id="dz" onclick="document.getElementById('fi').click()">
    <svg class="icon-svg" viewBox="0 0 24 24"><path d="M22 19a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h5l2 3h9a2 2 0 0 1 2 2z"/></svg>
    <div style="margin-top: 12px; font-weight: 500; color: #cbd5e1;">Tap or Drag files here to send</div>
  </div>
  <input type="file" id="fi" multiple style="display:none" onchange="updateFiles()">
  <button class="btn" id="sbtn" onclick="upload()" disabled>Send Files</button>
  <div class="progress" id="prg"><div class="bar" id="bar"></div></div>
  <div id="status"></div>
</div>
<script>
  let files = [];
  function updateFiles() {
    files = Array.from(document.getElementById('fi').files);
    if(files.length > 0) {
      document.getElementById('dz').innerHTML = `<svg class="icon-svg" viewBox="0 0 24 24"><path d="M14.5 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7.5L14.5 2z"/><polyline points="14 2 14 8 20 8"/></svg><div style="margin-top:12px;font-weight:600;color:#e2e8f0">${files.length} file(s) selected</div>`;
      document.getElementById('sbtn').disabled = false;
    }
  }
  async function upload() {
    if(!files.length) return;
    document.getElementById('sbtn').disabled = true;
    document.getElementById('prg').style.display = 'block';
    const status = document.getElementById('status');
    const formData = new FormData();
    for(const f of files) formData.append('files', f);
    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/api/webdrop/upload');
    xhr.upload.onprogress = (e) => {
      if(e.lengthComputable) {
        const pct = Math.round((e.loaded / e.total) * 100);
        document.getElementById('bar').style.width = pct + '%';
        status.innerHTML = `Uploading: ${pct}% (${(e.loaded/1048576).toFixed(1)} MB / ${(e.total/1048576).toFixed(1)} MB)`;
      }
    };
    xhr.onload = () => {
      if(xhr.status === 200) {
        status.innerHTML = `<span style="color:#34d399">Files transferred successfully!</span>`;
        document.getElementById('bar').style.width = '100%';
      } else {
        status.innerHTML = `<span style="color:#f87171">Upload failed</span>`;
      }
    };
    xhr.send(formData);
  }
</script>
</body>
</html>"##,
    )
}

async fn webdrop_upload_handler(
    State(state): State<Arc<ServerState>>,
    mut multipart: Multipart,
) -> Result<StatusCode, StatusCode> {
    let save_dir = state.save_dir.lock().await.clone();
    tokio::fs::create_dir_all(&save_dir)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let session_id = Uuid::new_v4().to_string();

    while let Ok(Some(mut field)) = multipart.next_field().await {
        let file_name = field
            .file_name()
            .map(sanitize_filename)
            .unwrap_or_else(|| format!("webdrop_{}.bin", Uuid::new_v4()));

        let dest_path = unique_dest_path(&save_dir, &file_name).await;
        let mut f = tokio::fs::File::create(&dest_path)
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

        let mut _received: u64 = 0;
        while let Ok(Some(chunk)) = field.chunk().await {
            f.write_all(&chunk)
                .await
                .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
            _received += chunk.len() as u64;
        }

        let file_id = Uuid::new_v4().to_string();
        let _ = state
            .events
            .send(ServerEvent::UploadComplete {
                session_id: session_id.clone(),
                file_id,
                saved_path: dest_path,
            })
            .await;
    }

    Ok(StatusCode::OK)
}

#[derive(Debug, Deserialize)]
struct WebdropTextPayload {
    text: String,
}

async fn webdrop_text_handler(
    State(state): State<Arc<ServerState>>,
    Json(payload): Json<WebdropTextPayload>,
) -> StatusCode {
    if payload.text.trim().is_empty() {
        return StatusCode::BAD_REQUEST;
    }
    let session_id = Uuid::new_v4().to_string();
    let file_id = Uuid::new_v4().to_string();
    let save_dir = state.save_dir.lock().await.clone();
    let _ = tokio::fs::create_dir_all(&save_dir).await;
    let file_path = save_dir.join(format!("shared_note_{}.txt", &session_id[..8]));
    let _ = tokio::fs::write(&file_path, payload.text.as_bytes()).await;

    let _ = state
        .events
        .send(ServerEvent::UploadComplete {
            session_id,
            file_id,
            saved_path: file_path,
        })
        .await;

    StatusCode::OK
}

async fn upload_handler(
    State(state): State<Arc<ServerState>>,
    Query(q): Query<UploadQuery>,
    body: Body,
) -> Result<StatusCode, StatusCode> {
    let (file_name, expected_size) = {
        let sessions = state.sessions.lock().await;
        let session = sessions.get(&q.session_id).ok_or(StatusCode::NOT_FOUND)?;
        let real_token = session
            .tokens
            .get(&q.file_id)
            .ok_or(StatusCode::FORBIDDEN)?;
        if real_token != &q.token {
            return Err(StatusCode::FORBIDDEN);
        }
        let file = session.files.get(&q.file_id).ok_or(StatusCode::NOT_FOUND)?;
        (sanitize_filename(&file.file_name), file.size)
    };

    let save_dir = state.save_dir.lock().await.clone();
    tokio::fs::create_dir_all(&save_dir)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
    let dest_path = unique_dest_path(&save_dir, &file_name).await;

    let mut f = tokio::fs::File::create(&dest_path)
        .await
        .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let mut stream = body.into_data_stream();
    let mut received_bytes: u64 = 0;
    let start_time = std::time::Instant::now();
    let mut last_emit = std::time::Instant::now();

    while let Some(chunk_res) = stream.next().await {
        let chunk = chunk_res.map_err(|_| StatusCode::BAD_REQUEST)?;
        f.write_all(&chunk)
            .await
            .map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;
        received_bytes += chunk.len() as u64;

        let now = std::time::Instant::now();
        if now.duration_since(last_emit).as_millis() >= 150 || received_bytes == expected_size {
            last_emit = now;
            let elapsed_secs = start_time.elapsed().as_secs_f64();
            let speed = if elapsed_secs > 0.0 {
                (received_bytes as f64 / elapsed_secs) as u64
            } else {
                0
            };
            let remaining = expected_size.saturating_sub(received_bytes);
            let eta = remaining.checked_div(speed).unwrap_or(0);

            let _ = state
                .events
                .send(ServerEvent::UploadProgress {
                    session_id: q.session_id.clone(),
                    file_id: q.file_id.clone(),
                    received_bytes,
                    total_bytes: expected_size,
                    speed_bytes_per_sec: speed,
                    eta_seconds: eta,
                })
                .await;
        }
    }

    let _ = state
        .events
        .send(ServerEvent::UploadComplete {
            session_id: q.session_id,
            file_id: q.file_id,
            saved_path: dest_path,
        })
        .await;

    Ok(StatusCode::OK)
}

#[derive(Debug, Deserialize)]
struct CancelQuery {
    #[serde(rename = "sessionId")]
    session_id: String,
}

async fn cancel_handler(
    State(state): State<Arc<ServerState>>,
    Query(q): Query<CancelQuery>,
) -> StatusCode {
    state.sessions.lock().await.remove(&q.session_id);
    state.accept_waiters.lock().await.remove(&q.session_id);
    let _ = state
        .events
        .send(ServerEvent::SessionCancelled {
            session_id: q.session_id,
        })
        .await;
    StatusCode::OK
}

/// Strips path separators etc. so a malicious `fileName` can't escape `save_dir`.
fn sanitize_filename(name: &str) -> String {
    name.replace(['/', '\\'], "_")
}

async fn unique_dest_path(dir: &std::path::Path, file_name: &str) -> PathBuf {
    let mut candidate = dir.join(file_name);
    let mut counter = 1;
    let stem = PathBuf::from(file_name)
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| file_name.to_string());
    let ext = PathBuf::from(file_name)
        .extension()
        .map(|s| s.to_string_lossy().to_string());

    while tokio::fs::metadata(&candidate).await.is_ok() {
        let new_name = match &ext {
            Some(ext) => format!("{stem} ({counter}).{ext}"),
            None => format!("{stem} ({counter})"),
        };
        candidate = dir.join(new_name);
        counter += 1;
    }
    candidate
}
