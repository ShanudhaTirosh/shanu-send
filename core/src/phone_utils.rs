use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RingPhonePayload {
    pub sender_alias: String,
    pub message: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BatteryTelemetry {
    pub percentage: u8,
    pub is_charging: bool,
    pub device_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NotificationPayload {
    pub id: String,
    pub app_name: String,
    pub title: String,
    pub body: String,
    pub timestamp: u64,
}
