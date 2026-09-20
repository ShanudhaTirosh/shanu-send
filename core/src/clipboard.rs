use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SharedClipboardPayload {
    pub content: String,
    pub timestamp: u64,
    pub sender_alias: String,
    pub sender_device_id: String,
}

impl SharedClipboardPayload {
    pub fn new(
        content: impl Into<String>,
        sender_alias: impl Into<String>,
        sender_device_id: impl Into<String>,
    ) -> Self {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);

        Self {
            content: content.into(),
            timestamp,
            sender_alias: sender_alias.into(),
            sender_device_id: sender_device_id.into(),
        }
    }
}
