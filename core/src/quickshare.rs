/// Quick Share / Nearby Share native protocol implementation.
/// Reference: google/nearby & open-quickshare
use serde::{Deserialize, Serialize};

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

use sha2::Digest;
