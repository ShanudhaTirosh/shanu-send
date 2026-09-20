use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum InputEventType {
    MouseMove { dx: f32, dy: f32 },
    MouseClick { button: String }, // "left", "right", "middle"
    MouseScroll { delta_x: f32, delta_y: f32 },
    KeyPress { key: String }, // "Enter", "Space", "ArrowLeft", "ArrowRight", etc.
    MediaControl { command: String }, // "play_pause", "next", "prev", "vol_up", "vol_down"
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RemoteInputPayload {
    pub event: InputEventType,
    pub sender_device_id: String,
}

impl RemoteInputPayload {
    pub fn mouse_move(dx: f32, dy: f32, sender_device_id: impl Into<String>) -> Self {
        Self {
            event: InputEventType::MouseMove { dx, dy },
            sender_device_id: sender_device_id.into(),
        }
    }

    pub fn mouse_click(button: impl Into<String>, sender_device_id: impl Into<String>) -> Self {
        Self {
            event: InputEventType::MouseClick {
                button: button.into(),
            },
            sender_device_id: sender_device_id.into(),
        }
    }

    pub fn key_press(key: impl Into<String>, sender_device_id: impl Into<String>) -> Self {
        Self {
            event: InputEventType::KeyPress { key: key.into() },
            sender_device_id: sender_device_id.into(),
        }
    }

    pub fn media_control(command: impl Into<String>, sender_device_id: impl Into<String>) -> Self {
        Self {
            event: InputEventType::MediaControl {
                command: command.into(),
            },
            sender_device_id: sender_device_id.into(),
        }
    }
}
