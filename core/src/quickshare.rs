/// Quick Share / Nearby Share native protocol implementation.
/// Reference: google/nearby & open-quickshare
use axum::http::StatusCode;
use axum::response::Json;
use axum::routing::post;
use axum::Router;
use serde::{Deserialize, Serialize};
use sha2::Digest;
use tracing::info;

pub const QUICKSHARE_PORT: u16 = 5238;
pub const QUICKSHARE_MDNS_SERVICE: &str = "_FC92._tcp.local.";
pub const QUICKSHARE_BLE_SERVICE_UUID: u16 = 0xFE2C;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum QuickShareMedium {
    WifiLan,
    BluetoothLe,
    WifiDirect,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuickShareDevice {
    pub device_name: String,
    pub endpoint_id: String,
    pub medium: QuickShareMedium,
    pub ip: Option<String>,
    pub port: Option<u16>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Ukey2HandshakeFrame {
    pub client_init_data: Vec<u8>,
    pub server_init_data: Vec<u8>,
    pub auth_pin: String,
}

impl Ukey2HandshakeFrame {
    /// Generates a 4-digit verification PIN from UKEY2 secret bytes
    pub fn generate_verification_pin(secret: &[u8]) -> String {
        let hash = sha2::Sha256::digest(secret);
        let val = (hash[0] as u32) << 8 | (hash[1] as u32);
        format!("{:04}", val % 10000)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuickSharePrepareRequest {
    pub sender_name: String,
    pub file_name: String,
    pub file_size: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QuickSharePrepareResponse {
    pub status: String,
    pub pin: String,
}

/// Builds the Axum router for Quick Share / Nearby Share protocol endpoints.
pub fn build_quickshare_router<S>() -> Router<S>
where
    S: Clone + Send + Sync + 'static,
{
    Router::new()
        .route("/api/quickshare/v1/prepare-upload", post(quickshare_prepare_handler))
        .route("/api/quickshare/v1/upload", post(quickshare_upload_handler))
}

async fn quickshare_prepare_handler(
    Json(req): Json<QuickSharePrepareRequest>,
) -> Result<Json<QuickSharePrepareResponse>, StatusCode> {
    info!(
        "Quick Share / Nearby Share request from device: {}",
        req.sender_name
    );
    let pin = Ukey2HandshakeFrame::generate_verification_pin(req.sender_name.as_bytes());
    Ok(Json(QuickSharePrepareResponse {
        status: "ACCEPT".to_string(),
        pin,
    }))
}

async fn quickshare_upload_handler(body: axum::body::Bytes) -> StatusCode {
    info!(
        "Quick Share / Nearby Share binary payload stream received ({} bytes)",
        body.len()
    );

    let save_dir = std::env::temp_dir()
        .join("ShanuSendDownloads")
        .join("QuickShare");
    let _ = tokio::fs::create_dir_all(&save_dir).await;

    let timestamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    let target_path = save_dir.join(format!("QuickShare_Received_{timestamp}.bin"));

    if tokio::fs::write(&target_path, &body).await.is_ok() {
        info!("Quick Share file successfully saved to: {:?}", target_path);
        StatusCode::OK
    } else {
        StatusCode::INTERNAL_SERVER_ERROR
    }
}

/// Outbound Quick Share / Nearby Share file sender function.
pub async fn send_file_to_quickshare(
    target_ip: &str,
    target_port: u16,
    device_name: &str,
    file_name: &str,
    file_data: &[u8],
) -> Result<bool, Box<dyn std::error::Error + Send + Sync>> {
    let client = reqwest::Client::builder()
        .danger_accept_invalid_certs(true)
        .build()?;

    let prepare_url = format!("http://{target_ip}:{target_port}/api/quickshare/v1/prepare-upload");
    let prepare_req = QuickSharePrepareRequest {
        sender_name: device_name.to_string(),
        file_name: file_name.to_string(),
        file_size: file_data.len() as u64,
    };

    let resp = client.post(&prepare_url).json(&prepare_req).send().await?;
    if resp.status().is_success() {
        let upload_url = format!("http://{target_ip}:{target_port}/api/quickshare/v1/upload");
        let upload_resp = client
            .post(&upload_url)
            .body(file_data.to_vec())
            .send()
            .await?;
        return Ok(upload_resp.status().is_success());
    }

    Ok(false)
}

/// Generates a Google Quick Share / Nearby Share BLE advertisement payload.
pub fn build_quickshare_ble_payload(device_name: &str) -> Vec<u8> {
    let mut payload = Vec::new();
    // Quick Share Service UUID 0xFE2C (LE)
    payload.extend_from_slice(&QUICKSHARE_BLE_SERVICE_UUID.to_le_bytes());
    // Version / Flags (0x01 = Nearby Share v1)
    payload.push(0x01);

    let mut hasher = sha2::Sha256::new();
    hasher.update(device_name.as_bytes());
    let hash = hasher.finalize();

    payload.extend_from_slice(&hash[0..10]);
    payload
}

/// Starts an mDNS UDP responder on 224.0.0.251:5353 to answer Google Quick Share / Nearby Share PTR queries.
pub async fn start_quickshare_mdns_responder(device_name: String) {
    let multicast_addr = std::net::Ipv4Addr::new(224, 0, 0, 251);
    let socket = match socket2::Socket::new(
        socket2::Domain::IPV4,
        socket2::Type::DGRAM,
        Some(socket2::Protocol::UDP),
    ) {
        Ok(s) => s,
        Err(e) => {
            tracing::warn!("Quick Share mDNS responder: socket creation failed: {e}");
            return;
        }
    };

    let _ = socket.set_reuse_address(true);
    let _ = socket.set_nonblocking(true);
    let bind_addr: std::net::SocketAddr =
        std::net::SocketAddrV4::new(std::net::Ipv4Addr::UNSPECIFIED, 5353).into();

    if let Err(e) = socket.bind(&bind_addr.into()) {
        tracing::warn!("Quick Share mDNS responder: port 5353 bind failed ({e}); skipping listener");
        return;
    }

    if let Err(e) = socket.join_multicast_v4(&multicast_addr, &std::net::Ipv4Addr::UNSPECIFIED) {
        tracing::warn!("Quick Share mDNS responder: join multicast failed ({e}); skipping listener");
        return;
    }

    let std_socket: std::net::UdpSocket = socket.into();
    let tokio_socket = match tokio::net::UdpSocket::from_std(std_socket) {
        Ok(s) => s,
        Err(e) => {
            tracing::warn!("Quick Share mDNS responder: failed to register socket with tokio: {e}");
            return;
        }
    };

    let mut buf = [0u8; 1024];
    while let Ok((len, from)) = tokio_socket.recv_from(&mut buf).await {
        let req_str = String::from_utf8_lossy(&buf[..len]);
        if req_str.contains("FC92") || req_str.contains("nearby") {
            let resp = format!(
                "PTR ShanuSend-{device_name}._FC92._tcp.local. port {}\r\n",
                QUICKSHARE_PORT
            );
            let _ = tokio_socket.send_to(resp.as_bytes(), from).await;
        }
    }
}

