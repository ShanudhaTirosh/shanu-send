//! DTOs that mirror LocalSend's protocol v2.1 JSON schema field-for-field.
//! Field names/casing here are load-bearing: real LocalSend apps parse these
//! exact keys. Do not "clean up" the naming without checking PROTOCOL.md.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// `DeviceType` as used by upstream LocalSend.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum DeviceType {
    Mobile,
    #[default]
    Desktop,
    Web,
    Headless,
    Server,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum ProtocolType {
    Http,
    #[default]
    Https,
}

/// Sent as the UDP multicast payload (and as the HTTP /register body).
/// This is the "who am I" announcement of a device.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegisterDto {
    pub alias: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub version: Option<String>,
    #[serde(rename = "deviceModel", skip_serializing_if = "Option::is_none")]
    pub device_model: Option<String>,
    #[serde(rename = "deviceType", skip_serializing_if = "Option::is_none")]
    pub device_type: Option<DeviceType>,
    pub fingerprint: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub port: Option<u16>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub protocol: Option<ProtocolType>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub download: Option<bool>,
}

/// UDP multicast variant: same fields as [RegisterDto] plus announce flags.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MulticastDto {
    pub alias: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub version: Option<String>,
    #[serde(rename = "deviceModel", skip_serializing_if = "Option::is_none")]
    pub device_model: Option<String>,
    #[serde(rename = "deviceType", skip_serializing_if = "Option::is_none")]
    pub device_type: Option<DeviceType>,
    pub fingerprint: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub port: Option<u16>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub protocol: Option<ProtocolType>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub download: Option<bool>,
    /// v1 field, kept for backwards interop with old LocalSend clients.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub announcement: Option<bool>,
    /// v2 field.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub announce: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum FileType {
    Image,
    Video,
    Pdf,
    Text,
    Apk,
    Other,
}

pub fn file_type_from_mime(mime: &str) -> FileType {
    if mime.starts_with("image/") {
        FileType::Image
    } else if mime.starts_with("video/") {
        FileType::Video
    } else if mime == "application/pdf" {
        FileType::Pdf
    } else if mime.starts_with("text/") {
        FileType::Text
    } else if mime == "application/vnd.android.package-archive" {
        FileType::Apk
    } else {
        FileType::Other
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FileDto {
    /// Unique within the transfer session only, not globally.
    pub id: String,
    #[serde(rename = "fileName")]
    pub file_name: String,
    pub size: u64,
    #[serde(rename = "fileType")]
    pub file_type: String, // MIME string on the wire, mapped via file_type_from_mime()
    #[serde(skip_serializing_if = "Option::is_none")]
    pub hash: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preview: Option<String>,
}

/// Body of POST /api/localsend/v2/prepare-upload
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrepareUploadRequestDto {
    pub info: RegisterDto,
    pub files: HashMap<String, FileDto>,
}

/// Response of POST /api/localsend/v2/prepare-upload
/// `files` maps fileId -> single-use upload token, consumed by
/// POST /api/localsend/v2/upload?sessionId=..&fileId=..&token=..
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrepareUploadResponseDto {
    #[serde(rename = "sessionId")]
    pub session_id: String,
    pub files: HashMap<String, String>,
}

/// Internal (non-wire) representation of a discovered peer, used by the UI layer.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Device {
    pub ip: String,
    pub port: u16,
    pub https: bool,
    pub alias: String,
    pub version: String,
    pub device_model: Option<String>,
    pub device_type: DeviceType,
    pub fingerprint: String,
    pub download: bool,
    /// ShanuSend addition: has the user marked this device as trusted
    /// (enables auto-accept). Not part of the wire protocol.
    #[serde(default)]
    pub trusted: bool,
}
