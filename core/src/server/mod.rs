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
    extract::{Query, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
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
    pub async fn respond_prepare_upload(&self, session_id: &str, accepted_file_ids: Option<Vec<String>>) {
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
        self.trusted_fingerprints.lock().await.retain(|f| f != fingerprint);
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
        .route("/api/localsend/v2/info", get(info_handler))
        .route("/api/localsend/v2/register", post(register_handler))
        .route("/api/localsend/v2/prepare-upload", post(prepare_upload_handler))
        .route("/api/localsend/v2/upload", post(upload_handler))
        .route("/api/localsend/v2/cancel", post(cancel_handler))
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
        state.accept_waiters.lock().await.insert(session_id.clone(), accept_tx);

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

async fn upload_handler(
    State(state): State<Arc<ServerState>>,
    Query(q): Query<UploadQuery>,
    body: axum::body::Bytes,
) -> Result<StatusCode, StatusCode> {
    let (file_name, expected_size) = {
        let sessions = state.sessions.lock().await;
        let session = sessions.get(&q.session_id).ok_or(StatusCode::NOT_FOUND)?;
        let real_token = session.tokens.get(&q.file_id).ok_or(StatusCode::FORBIDDEN)?;
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
    f.write_all(&body).await.map_err(|_| StatusCode::INTERNAL_SERVER_ERROR)?;

    let _ = state
        .events
        .send(ServerEvent::UploadProgress {
            session_id: q.session_id.clone(),
            file_id: q.file_id.clone(),
            received_bytes: body.len() as u64,
            total_bytes: expected_size,
        })
        .await;
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

async fn cancel_handler(State(state): State<Arc<ServerState>>, Query(q): Query<CancelQuery>) -> StatusCode {
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
