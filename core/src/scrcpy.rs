/// Scrcpy Pro Suite configuration, argument builder, and Wireless ADB manager.
/// Reference: Genymobile/scrcpy & kil0bit-kb/scrcpy-gui
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum VideoCodec {
    H264,
    H265,
    AV1,
}

impl VideoCodec {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::H264 => "h264",
            Self::H265 => "h265",
            Self::AV1 => "av1",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum AudioCodec {
    Opus,
    Aac,
    Flac,
    Raw,
    Disabled,
}

impl AudioCodec {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Opus => "opus",
            Self::Aac => "aac",
            Self::Flac => "flac",
            Self::Raw => "raw",
            Self::Disabled => "disabled",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum AudioSource {
    Output,
    Mic,
    Disabled,
}

impl AudioSource {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Output => "output",
            Self::Mic => "mic",
            Self::Disabled => "disabled",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum CameraFacing {
    Front,
    Back,
}

impl CameraFacing {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Front => "front",
            Self::Back => "back",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum RecordFormat {
    Off,
    Mp4,
    Mkv,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
#[serde(rename_all = "camelCase")]
pub struct ScrcpyConfig {
    pub device: String,
    pub session_mode: String,
    pub bitrate: Option<u32>,
    pub fps: Option<u32>,
    pub stay_awake: Option<bool>,
    pub turn_off: Option<bool>,
    pub audio_enabled: Option<bool>,
    pub audio_codec: Option<String>,
    pub always_on_top: Option<bool>,
    pub fullscreen: Option<bool>,
    pub borderless: Option<bool>,
    pub record: Option<bool>,
    pub record_path: Option<String>,
    pub scrcpy_path: Option<String>,
    pub otg_pure: Option<bool>,
    pub camera_facing: Option<String>,
    pub camera_id: Option<String>,
    pub codec: Option<String>,
    pub camera_ar: Option<String>,
    pub camera_high_speed: Option<bool>,
    pub vd_width: Option<u32>,
    pub vd_height: Option<u32>,
    pub vd_dpi: Option<u32>,
    pub rotation: Option<String>,
    pub res: Option<String>,
    pub hid_keyboard: Option<bool>,
    pub hid_mouse: Option<bool>,
    pub render_driver: Option<String>,
    pub show_touches: Option<bool>,
    // v4 features
    pub flex_display: Option<bool>,
    pub camera_torch: Option<bool>,
    pub camera_zoom: Option<f32>,
    pub background_color: Option<String>,
    pub keep_active: Option<bool>,
    pub vsync: Option<bool>,
    pub window_x: Option<i32>,
    pub window_y: Option<i32>,
    // v4.1 features
    pub ignore_video_encoder_constraints: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AdbWirelessPairing {
    pub ip_address: String,
    pub port: u16,
    pub pairing_code: String,
}

