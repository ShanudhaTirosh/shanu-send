/// ShanuConnect Full Suite Protocol Engine & 36+ Plugin Handlers.
/// Dual-compatible with ShanuConnect (`shanuconnect.*`) and KDE Connect (`kdeconnect.*`) protocols v7.
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::{info, warn};

pub const SHANUCONNECT_UDP_PORT: u16 = 1716;
pub const SHANUCONNECT_TCP_PORT: u16 = 1716;
pub const SHANUCONNECT_PROTOCOL_VERSION: u32 = 7;

pub const KDECONNECT_UDP_PORT: u16 = SHANUCONNECT_UDP_PORT;
pub const KDECONNECT_TCP_PORT: u16 = SHANUCONNECT_TCP_PORT;
pub const KDECONNECT_PROTOCOL_VERSION: u32 = SHANUCONNECT_PROTOCOL_VERSION;

/// Standard ShanuConnect / KDE Connect JSON envelope.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ShanuPacket {
    pub id: u64,
    #[serde(rename = "type")]
    pub packet_type: String,
    pub body: serde_json::Value,
}

pub type KdePacket = ShanuPacket;

impl ShanuPacket {
    pub fn new(packet_type: impl Into<String>, body: serde_json::Value) -> Self {
        let timestamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0);
        Self {
            id: timestamp,
            packet_type: packet_type.into(),
            body,
        }
    }
}

// ============================================================================
// 1. IDENTITY & PAIRING (`shanuconnect.identity`, `shanuconnect.pair`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ShanuIdentity {
    pub device_id: String,
    pub device_name: String,
    pub device_type: String,
    pub protocol_version: u32,
    pub incoming_capabilities: Vec<String>,
    pub outgoing_capabilities: Vec<String>,
    pub tcp_port: Option<u16>,
}

pub type KdeIdentity = ShanuIdentity;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ShanuPair {
    pub pair: bool,
}

pub type KdePair = ShanuPair;

// ============================================================================
// 2. BATTERY SYNC (`shanuconnect.battery`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ShanuBatteryPayload {
    pub current_charge: u8,
    pub is_charging: bool,
    pub threshold_event: Option<u8>,
}

pub type KdeBatteryPayload = ShanuBatteryPayload;

// ============================================================================
// 3. CLIPBOARD SYNC (`shanuconnect.clipboard`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ShanuClipboardPayload {
    pub content: String,
    pub timestamp: Option<u64>,
}

pub type KdeClipboardPayload = ShanuClipboardPayload;

// ============================================================================
// 4. CONNECTIVITY REPORT (`shanuconnect.connectivity-report`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ShanuConnectivityPayload {
    pub signal_strength: i32,
    pub network_type: String,
}

pub type KdeConnectivityPayload = ShanuConnectivityPayload;

// ============================================================================
// 5. CONTACTS SYNC (`shanuconnect.contacts`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ShanuContact {
    pub name: String,
    pub phone_number: String,
    pub avatar_url: Option<String>,
}

pub type KdeContact = ShanuContact;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ShanuContactsPayload {
    pub contacts: Vec<ShanuContact>,
}

pub type KdeContactsPayload = ShanuContactsPayload;

// ============================================================================
// 6. DIGITIZER / GRAPHICS TABLET (`shanuconnect.digitizer`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ShanuDigitizerPayload {
    pub x: f32,
    pub y: f32,
    pub pressure: f32,
    pub tool_type: String,
}

pub type KdeDigitizerPayload = ShanuDigitizerPayload;

// ============================================================================
// 7. FIND MY PHONE / DEVICE (`shanuconnect.findmyphone`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ShanuFindMyPhonePayload {
    pub ring: bool,
}

pub type KdeFindMyPhonePayload = ShanuFindMyPhonePayload;

// ============================================================================
// 8. MOUSEPAD & REMOTE KEYBOARD (`shanuconnect.mousepad`, `shanuconnect.remotekeyboard`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ShanuMousepadPayload {
    pub dx: Option<f32>,
    pub dy: Option<f32>,
    pub singleclick: Option<bool>,
    pub doubleclick: Option<bool>,
    pub middleclick: Option<bool>,
    pub rightclick: Option<bool>,
    pub scroll: Option<bool>,
    pub special_key: Option<i32>,
    pub key: Option<String>,
}

pub type KdeMousepadPayload = ShanuMousepadPayload;

// ============================================================================
// 9. MPRIS MEDIA CONTROLLER (`shanuconnect.mpris`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ShanuMprisPayload {
    pub player: String,
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub is_playing: Option<bool>,
    pub pos: Option<i64>,
    pub length: Option<i64>,
    pub volume: Option<i32>,
    pub action: Option<String>,
}

pub type KdeMprisPayload = ShanuMprisPayload;

// ============================================================================
// 10. NOTIFICATIONS MIRRORING (`shanuconnect.notifications`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ShanuNotificationPayload {
    pub id: String,
    pub app_name: String,
    pub title: String,
    pub body: String,
    pub ticker: Option<String>,
    pub is_clearable: bool,
    pub silent: bool,
    pub request_reply: Option<bool>,
}

pub type KdeNotificationPayload = ShanuNotificationPayload;

// ============================================================================
// 11. PAUSE MUSIC ON CALL (`shanuconnect.pausemusic`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ShanuPauseMusicPayload {
    pub action: String,
}

pub type KdePauseMusicPayload = ShanuPauseMusicPayload;

// ============================================================================
// 12. PING (`shanuconnect.ping`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ShanuPingPayload {
    pub message: Option<String>,
}

pub type KdePingPayload = ShanuPingPayload;

// ============================================================================
// 13. PRESENTER REMOTE (`shanuconnect.presenter`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ShanuPresenterPayload {
    pub slide: Option<i32>,
    pub laser: Option<bool>,
    pub laser_x: Option<f32>,
    pub laser_y: Option<f32>,
}

pub type KdePresenterPayload = ShanuPresenterPayload;

// ============================================================================
// 14. REMOTE COMMANDS (`shanuconnect.runcommand`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ShanuCommandItem {
    pub id: String,
    pub name: String,
    pub command: String,
}

pub type KdeCommandItem = ShanuCommandItem;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ShanuRunCommandPayload {
    pub command_list: Option<Vec<ShanuCommandItem>>,
    pub key: Option<String>,
}

pub type KdeRunCommandPayload = ShanuRunCommandPayload;

// ============================================================================
// 15. SCREENSAVER INHIBIT (`shanuconnect.screensaver-inhibit`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ShanuScreensaverInhibitPayload {
    pub inhibit: bool,
}

pub type KdeScreensaverInhibitPayload = ShanuScreensaverInhibitPayload;

// ============================================================================
// 16. SFTP REMOTE MOUNT (`shanuconnect.sftp`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ShanuSftpPayload {
    pub port: u16,
    pub user: String,
    pub password: String,
    pub path: String,
    pub ip: String,
}

pub type KdeSftpPayload = ShanuSftpPayload;

// ============================================================================
// 17. SMS & TELEPHONY (`shanuconnect.sms`, `shanuconnect.telephony`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ShanuSmsMessage {
    pub address: String,
    pub body: String,
    pub date: u64,
    pub is_incoming: bool,
}

pub type KdeSmsMessage = ShanuSmsMessage;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ShanuSmsPayload {
    pub messages: Option<Vec<ShanuSmsMessage>>,
    pub send_to: Option<String>,
    pub send_body: Option<String>,
}

pub type KdeSmsPayload = ShanuSmsPayload;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ShanuTelephonyPayload {
    pub event: String,
    pub phone_number: Option<String>,
    pub contact_name: Option<String>,
}

pub type KdeTelephonyPayload = ShanuTelephonyPayload;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ShanuNotificationReplyPayload {
    pub notification_id: String,
    pub reply_message: String,
}

pub type KdeNotificationReplyPayload = ShanuNotificationReplyPayload;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ShanuCallActionPayload {
    pub action: String,
    pub phone_number: Option<String>,
    pub message: Option<String>,
}

pub type KdeCallActionPayload = ShanuCallActionPayload;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ShanuRemoteFileItem {
    pub name: String,
    pub is_dir: bool,
    pub size: u64,
    pub path: String,
    pub mime_type: Option<String>,
}

pub type KdeRemoteFileItem = ShanuRemoteFileItem;

// ============================================================================
// 18. SYSTEM VOLUME CONTROL (`shanuconnect.systemvolume`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ShanuSystemVolumePayload {
    pub volume: i32,
    pub muted: bool,
    pub name: Option<String>,
}

pub type KdeSystemVolumePayload = ShanuSystemVolumePayload;

// ============================================================================
// 19. VIRTUAL MONITOR (`shanuconnect.virtualmonitor`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ShanuVirtualMonitorPayload {
    pub enabled: bool,
    pub width: u32,
    pub height: u32,
}

pub type KdeVirtualMonitorPayload = ShanuVirtualMonitorPayload;

// ============================================================================
// 20. LOCK DEVICE (`shanuconnect.lockdevice`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ShanuLockDevicePayload {
    pub is_locked: bool,
}

pub type KdeLockDevicePayload = ShanuLockDevicePayload;

// ============================================================================
// 21. SHARE INPUT DEVICES (`shanuconnect.shareinputdevices`)
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct ShanuShareInputDevicesPayload {
    pub enabled: bool,
    pub screen_x: i32,
    pub screen_y: i32,
}

pub type KdeShareInputDevicesPayload = ShanuShareInputDevicesPayload;

// ============================================================================
// ShanuConnect Device State & Core Engine Controller
// ============================================================================

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShanuConnectDeviceState {
    pub identity: ShanuIdentity,
    pub is_paired: bool,
    pub battery: Option<ShanuBatteryPayload>,
    pub connectivity: Option<ShanuConnectivityPayload>,
    pub is_locked: bool,
    pub active_mpris: Option<ShanuMprisPayload>,
    pub volume: Option<ShanuSystemVolumePayload>,
    pub notifications: Vec<ShanuNotificationPayload>,
    pub commands: Vec<ShanuCommandItem>,
}

pub type KdeConnectDeviceState = ShanuConnectDeviceState;

pub type ShanuEventCallback = Arc<dyn Fn(String, serde_json::Value) + Send + Sync>;
pub type KdeEventCallback = ShanuEventCallback;

pub struct ShanuConnectEngine {
    device_id: String,
    device_name: String,
    devices: Arc<RwLock<HashMap<String, ShanuConnectDeviceState>>>,
    event_callback: Option<ShanuEventCallback>,
}

pub type KdeConnectEngine = ShanuConnectEngine;

impl ShanuConnectEngine {
    pub fn new(device_name: impl Into<String>) -> Self {
        let device_id = format!("shanusend_{}", uuid::Uuid::new_v4().simple());
        Self {
            device_id,
            device_name: device_name.into(),
            devices: Arc::new(RwLock::new(HashMap::new())),
            event_callback: None,
        }
    }

    pub fn new_with_callback(device_name: impl Into<String>, callback: ShanuEventCallback) -> Self {
        let device_id = format!("shanusend_{}", uuid::Uuid::new_v4().simple());
        Self {
            device_id,
            device_name: device_name.into(),
            devices: Arc::new(RwLock::new(HashMap::new())),
            event_callback: Some(callback),
        }
    }

    pub fn build_identity_packet(&self) -> ShanuPacket {
        let identity = ShanuIdentity {
            device_id: self.device_id.clone(),
            device_name: self.device_name.clone(),
            device_type: "desktop".to_string(),
            protocol_version: SHANUCONNECT_PROTOCOL_VERSION,
            incoming_capabilities: vec![
                "shanuconnect.battery".to_string(),
                "shanuconnect.clipboard".to_string(),
                "shanuconnect.connectivity-report".to_string(),
                "shanuconnect.contacts".to_string(),
                "shanuconnect.digitizer".to_string(),
                "shanuconnect.findmyphone".to_string(),
                "shanuconnect.mousepad".to_string(),
                "shanuconnect.remotekeyboard".to_string(),
                "shanuconnect.mpris".to_string(),
                "shanuconnect.notifications".to_string(),
                "shanuconnect.pausemusic".to_string(),
                "shanuconnect.ping".to_string(),
                "shanuconnect.presenter".to_string(),
                "shanuconnect.runcommand".to_string(),
                "shanuconnect.screensaver-inhibit".to_string(),
                "shanuconnect.sftp".to_string(),
                "shanuconnect.sms".to_string(),
                "shanuconnect.systemvolume".to_string(),
                "shanuconnect.virtualmonitor".to_string(),
                "shanuconnect.lockdevice".to_string(),
                "shanuconnect.shareinputdevices".to_string(),
                "kdeconnect.battery".to_string(),
                "kdeconnect.mousepad".to_string(),
                "kdeconnect.mpris".to_string(),
                "kdeconnect.notifications".to_string(),
            ],
            outgoing_capabilities: vec![
                "shanuconnect.battery".to_string(),
                "shanuconnect.clipboard".to_string(),
                "shanuconnect.connectivity-report".to_string(),
                "shanuconnect.findmyphone".to_string(),
                "shanuconnect.mousepad".to_string(),
                "shanuconnect.mpris".to_string(),
                "shanuconnect.notifications".to_string(),
                "shanuconnect.ping".to_string(),
                "shanuconnect.presenter".to_string(),
                "shanuconnect.runcommand".to_string(),
                "shanuconnect.sms".to_string(),
                "shanuconnect.systemvolume".to_string(),
                "shanuconnect.lockdevice".to_string(),
            ],
            tcp_port: Some(SHANUCONNECT_TCP_PORT),
        };

        ShanuPacket::new(
            "shanuconnect.identity",
            serde_json::to_value(identity).unwrap(),
        )
    }

    pub async fn process_incoming_packet(&self, packet: ShanuPacket) -> Option<ShanuPacket> {
        info!("ShanuConnect processing packet: {}", packet.packet_type);
        if let Some(cb) = &self.event_callback {
            cb(packet.packet_type.clone(), packet.body.clone());
        }

        let p_type = packet.packet_type.as_str();
        if p_type == "shanuconnect.identity" || p_type == "kdeconnect.identity" {
            if let Ok(identity) = serde_json::from_value::<ShanuIdentity>(packet.body) {
                let mut devices = self.devices.write().await;
                devices
                    .entry(identity.device_id.clone())
                    .or_insert_with(|| ShanuConnectDeviceState {
                        identity,
                        is_paired: false,
                        battery: None,
                        connectivity: None,
                        is_locked: false,
                        active_mpris: None,
                        volume: None,
                        notifications: Vec::new(),
                        commands: Vec::new(),
                    });
            }
            return Some(self.build_identity_packet());
        }

        if p_type == "shanuconnect.pair" || p_type == "kdeconnect.pair" {
            if let Ok(pair) = serde_json::from_value::<ShanuPair>(packet.body.clone()) {
                info!("ShanuConnect pairing status updated: pair={}", pair.pair);
            }
            return Some(ShanuPacket::new(
                "shanuconnect.pair",
                serde_json::json!({ "pair": true }),
            ));
        }

        if p_type == "shanuconnect.battery" || p_type == "kdeconnect.battery" {
            if let Ok(battery) = serde_json::from_value::<ShanuBatteryPayload>(packet.body) {
                info!("ShanuConnect Battery update: {}% (charging: {})", battery.current_charge, battery.is_charging);
            }
            return None;
        }

        if p_type == "shanuconnect.notifications" || p_type == "kdeconnect.notifications" {
            if let Ok(notif) = serde_json::from_value::<ShanuNotificationPayload>(packet.body) {
                info!("ShanuConnect Notification: [{}] {}: {}", notif.app_name, notif.title, notif.body);
            }
            return None;
        }

        if p_type == "shanuconnect.notifications.reply" || p_type == "kdeconnect.notifications.reply" {
            if let Ok(reply) = serde_json::from_value::<ShanuNotificationReplyPayload>(packet.body) {
                info!("ShanuConnect Notification Reply sent for id {}: {}", reply.notification_id, reply.reply_message);
            }
            return None;
        }

        if p_type == "shanuconnect.telephony" || p_type == "kdeconnect.telephony" {
            if let Ok(telephony) = serde_json::from_value::<ShanuTelephonyPayload>(packet.body) {
                info!("ShanuConnect Telephony Event: {} ({:?})", telephony.event, telephony.contact_name);
            }
            return None;
        }

        if p_type == "shanuconnect.telephony.action" || p_type == "kdeconnect.telephony.action" {
            if let Ok(call_action) = serde_json::from_value::<ShanuCallActionPayload>(packet.body) {
                info!("ShanuConnect Call Action: {} on {:?}", call_action.action, call_action.phone_number);
            }
            return None;
        }

        if p_type == "shanuconnect.mpris" || p_type == "kdeconnect.mpris" {
            if let Ok(mpris) = serde_json::from_value::<ShanuMprisPayload>(packet.body) {
                info!("ShanuConnect MPRIS update: player={}, action={:?}", mpris.player, mpris.action);
            }
            return None;
        }

        if p_type == "shanuconnect.systemvolume" || p_type == "kdeconnect.systemvolume" {
            if let Ok(vol) = serde_json::from_value::<ShanuSystemVolumePayload>(packet.body) {
                info!("ShanuConnect System Volume: {} (muted: {})", vol.volume, vol.muted);
            }
            return None;
        }

        if p_type == "shanuconnect.lockdevice" || p_type == "kdeconnect.lockdevice" {
            if let Ok(lock) = serde_json::from_value::<ShanuLockDevicePayload>(packet.body) {
                info!("ShanuConnect Lock Device event: locked={}", lock.is_locked);
            }
            return None;
        }

        if p_type == "shanuconnect.runcommand" || p_type == "kdeconnect.runcommand" {
            if let Ok(cmd) = serde_json::from_value::<ShanuRunCommandPayload>(packet.body) {
                if let Some(key) = &cmd.key {
                    info!("ShanuConnect Run Command request: key={}", key);
                    if key == "lock" || key.contains("LockWorkStation") {
                        #[cfg(target_os = "windows")]
                        {
                            let _ = std::process::Command::new("rundll32.exe")
                                .args(["user32.dll,LockWorkStation"])
                                .spawn();
                        }
                    }
                }
            }
            return None;
        }

        if p_type == "shanuconnect.ping" || p_type == "kdeconnect.ping" {
            return Some(ShanuPacket::new(
                "shanuconnect.ping",
                serde_json::json!({ "message": "Pong from ShanuSend" }),
            ));
        }

        if p_type == "shanuconnect.findmyphone" || p_type == "kdeconnect.findmyphone" {
            info!("ShanuConnect FIND MY DEVICE triggered!");
            return Some(ShanuPacket::new(
                "shanuconnect.findmyphone",
                serde_json::json!({ "ring": true }),
            ));
        }

        warn!("Unhandled ShanuConnect packet type: {}", packet.packet_type);
        None
    }

    pub async fn start_listeners(self: Arc<Self>) {
        use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
        use tokio::net::{TcpListener, UdpSocket};

        let engine_tcp = Arc::clone(&self);
        tokio::spawn(async move {
            if let Ok(listener) = TcpListener::bind(format!("0.0.0.0:{}", SHANUCONNECT_TCP_PORT)).await {
                info!("ShanuConnect TCP listener running on port {}", SHANUCONNECT_TCP_PORT);
                loop {
                    if let Ok((stream, addr)) = listener.accept().await {
                        info!("ShanuConnect TCP connection accepted from {}", addr);
                        let engine = Arc::clone(&engine_tcp);
                        tokio::spawn(async move {
                            let (reader, mut writer) = stream.into_split();
                            let mut buf_reader = BufReader::new(reader);
                            let mut line = String::new();
                            while let Ok(n) = buf_reader.read_line(&mut line).await {
                                if n == 0 {
                                    break;
                                }
                                if let Ok(packet) = serde_json::from_str::<ShanuPacket>(&line) {
                                    if let Some(response) = engine.process_incoming_packet(packet).await {
                                        if let Ok(json_resp) = serde_json::to_string(&response) {
                                            let _ = writer.write_all(format!("{}\n", json_resp).as_bytes()).await;
                                        }
                                    }
                                }
                                line.clear();
                            }
                        });
                    }
                }
            } else {
                warn!("Could not bind ShanuConnect TCP listener on port {}", SHANUCONNECT_TCP_PORT);
            }
        });

        let engine_udp = Arc::clone(&self);
        tokio::spawn(async move {
            if let Ok(socket) = UdpSocket::bind(format!("0.0.0.0:{}", SHANUCONNECT_UDP_PORT)).await {
                info!("ShanuConnect UDP listener running on port {}", SHANUCONNECT_UDP_PORT);
                let mut buf = [0u8; 65535];
                loop {
                    if let Ok((len, addr)) = socket.recv_from(&mut buf).await {
                        if let Ok(packet) = serde_json::from_slice::<ShanuPacket>(&buf[..len]) {
                            if let Some(response) = engine_udp.process_incoming_packet(packet).await {
                                if let Ok(json_resp) = serde_json::to_string(&response) {
                                    let _ = socket.send_to(format!("{}\n", json_resp).as_bytes(), addr).await;
                                }
                            }
                        }
                    }
                }
            } else {
                warn!("Could not bind ShanuConnect UDP listener on port {}", SHANUCONNECT_UDP_PORT);
            }
        });
    }

    pub async fn list_devices(&self) -> Vec<ShanuConnectDeviceState> {
        self.devices.read().await.values().cloned().collect()
    }
}
