//! Outbound requests to a peer's LocalSend-compatible HTTP server.
//! Note: for v1 we talk plain HTTP even when the peer advertises HTTPS
//! fingerprint pinning; TLS + fingerprint verification is wired in during
//! Phase 3 (see plan §7) once `crypto::generate_self_signed` output is
//! threaded through here as a custom `rustls` verifier.

use crate::models::{
    Device, FileDto, PrepareUploadRequestDto, PrepareUploadResponseDto, RegisterDto,
};
use std::collections::HashMap;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ClientError {
    #[error("network error: {0}")]
    Network(std::io::Error),
    #[error("peer rejected the request (status {0})")]
    Rejected(u16),
    #[error("peer requires a PIN")]
    PinRequired,
}

fn base_url(device: &Device) -> String {
    let scheme = if device.https { "https" } else { "http" };
    format!("{scheme}://{}:{}", device.ip, device.port)
}

pub async fn fetch_info(device: &Device) -> Result<RegisterDto, ClientError> {
    let url = format!("{}/api/localsend/v2/info", base_url(device));
    let client = http_client(device.https);
    let resp = client
        .get(&url)
        .send()
        .await
        .map_err(|e| ClientError::Network(std::io::Error::new(std::io::ErrorKind::Other, e)))?;
    resp.json::<RegisterDto>()
        .await
        .map_err(|e| ClientError::Network(std::io::Error::new(std::io::ErrorKind::Other, e)))
}

pub async fn request_upload(
    device: &Device,
    self_info: RegisterDto,
    files: HashMap<String, FileDto>,
    pin: Option<&str>,
) -> Result<PrepareUploadResponseDto, ClientError> {
    let mut url = format!("{}/api/localsend/v2/prepare-upload", base_url(device));
    if let Some(pin) = pin {
        url.push_str(&format!("?pin={pin}"));
    }

    let body = PrepareUploadRequestDto {
        info: self_info,
        files,
    };
    let client = http_client(device.https);
    let resp = client
        .post(&url)
        .json(&body)
        .send()
        .await
        .map_err(|e| ClientError::Network(std::io::Error::new(std::io::ErrorKind::Other, e)))?;

    match resp.status().as_u16() {
        200 => resp
            .json::<PrepareUploadResponseDto>()
            .await
            .map_err(|e| ClientError::Network(std::io::Error::new(std::io::ErrorKind::Other, e))),
        401 => Err(ClientError::PinRequired),
        code => Err(ClientError::Rejected(code)),
    }
}

pub async fn upload_file_bytes(
    device: &Device,
    session_id: &str,
    file_id: &str,
    token: &str,
    bytes: Vec<u8>,
) -> Result<(), ClientError> {
    let url = format!(
        "{}/api/localsend/v2/upload?sessionId={session_id}&fileId={file_id}&token={token}",
        base_url(device)
    );
    let client = http_client(device.https);
    let resp = client
        .post(&url)
        .body(bytes)
        .send()
        .await
        .map_err(|e| ClientError::Network(std::io::Error::new(std::io::ErrorKind::Other, e)))?;

    if resp.status().is_success() {
        Ok(())
    } else {
        Err(ClientError::Rejected(resp.status().as_u16()))
    }
}

/// Peers use self-signed certs, so the client must not do standard CA
/// validation. Real fingerprint pinning against `device.fingerprint` is
/// added in Phase 3; today this just disables cert validation like
/// LocalSend's own client does prior to pinning being wired up.
fn http_client(_https: bool) -> reqwest::Client {
    reqwest::Client::builder()
        .danger_accept_invalid_certs(true)
        .build()
        .expect("client builds")
}

/// Real fingerprint-pinned client (Phase 3). Only completes a TLS handshake
/// if the peer presents a certificate matching `device.fingerprint` exactly
/// — see `crypto::PinnedFingerprintVerifier`. Gated behind the `tls` feature
/// for the sandbox-toolchain reason documented on that feature in Cargo.toml.
#[cfg(feature = "tls")]
pub fn pinned_http_client(device: &crate::models::Device) -> reqwest::Client {
    let tls_config = crate::crypto::pinned_client_config(device.fingerprint.clone());
    reqwest::Client::builder()
        .use_preconfigured_tls(tls_config)
        .build()
        .expect("pinned client builds")
}
