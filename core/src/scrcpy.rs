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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScrcpyConfig {
    pub device_serial: String,
    pub bit_rate_mbps: u32,
    pub max_fps: u32,
    pub max_size: u32,
    pub video_codec: VideoCodec,
    pub audio_codec: AudioCodec,
    pub audio_source: AudioSource,
    pub camera_mode: bool,
    pub camera_facing: CameraFacing,
    pub camera_high_fps: bool,
    pub stay_awake: bool,
    pub turn_screen_off: bool,
    pub show_touches: bool,
    pub otg_mode: bool,
    pub record_format: RecordFormat,
}

impl Default for ScrcpyConfig {
    fn default() -> Self {
        Self {
            device_serial: String::new(),
            bit_rate_mbps: 16,
            max_fps: 60,
            max_size: 1080,
            video_codec: VideoCodec::H264,
            audio_codec: AudioCodec::Opus,
            audio_source: AudioSource::Output,
            camera_mode: false,
            camera_facing: CameraFacing::Back,
            camera_high_fps: false,
            stay_awake: true,
            turn_screen_off: false,
            show_touches: false,
            otg_mode: false,
            record_format: RecordFormat::Off,
        }
    }
}

impl ScrcpyConfig {
    /// Generates CLI argument vector for launching scrcpy binary
    pub fn build_cli_args(&self) -> Vec<String> {
        let mut args = Vec::new();

        if !self.device_serial.is_empty() {
            args.push("-s".to_string());
            args.push(self.device_serial.clone());
        }

        // Video Options
        args.push(format!("--video-codec={}", self.video_codec.as_str()));
        args.push(format!("--video-bit-rate={}M", self.bit_rate_mbps));

        if self.max_fps > 0 {
            args.push(format!("--max-fps={}", self.max_fps));
        }

        if self.max_size > 0 {
            args.push(format!("--max-size={}", self.max_size));
        }

        // Audio Options
        if self.audio_codec == AudioCodec::Disabled || self.audio_source == AudioSource::Disabled {
            args.push("--no-audio".to_string());
        } else {
            args.push(format!("--audio-codec={}", self.audio_codec.as_str()));
            args.push(format!("--audio-source={}", self.audio_source.as_str()));
        }

        // Pro Camera Mode (Webcam)
        if self.camera_mode {
            args.push("--video-source=camera".to_string());
            args.push(format!("--camera-facing={}", self.camera_facing.as_str()));
        }

        // Display / Control Toggles
        if self.stay_awake {
            args.push("--stay-awake".to_string());
        }

        if self.turn_screen_off {
            args.push("--turn-screen-off".to_string());
        }

        if self.show_touches {
            args.push("--show-touches".to_string());
        }

        if self.otg_mode {
            args.push("--otg".to_string());
        }

        // Recording
        match self.record_format {
            RecordFormat::Mp4 => args.push("--record=scrcpy_recording.mp4".to_string()),
            RecordFormat::Mkv => args.push("--record=scrcpy_recording.mkv".to_string()),
            RecordFormat::Off => {}
        }

        args
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AdbWirelessPairing {
    pub ip_address: String,
    pub port: u16,
    pub pairing_code: String,
}
