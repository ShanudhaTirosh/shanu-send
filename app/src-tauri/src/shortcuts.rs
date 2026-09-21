//! Cross-platform global OS shortcuts. `tauri_plugin_global_shortcut` only
//! supports one plugin instance (and so one dispatch handler) per app.

use tauri::plugin::TauriPlugin;
use tauri::{AppHandle, Manager, Runtime};
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};

use crate::commands::ScrcpyState;

fn recenter_shortcut() -> Shortcut {
    Shortcut::new(
        Some(Modifiers::CONTROL | Modifiers::ALT | Modifiers::SHIFT),
        Code::KeyC,
    )
}

pub fn plugin<R: Runtime>() -> TauriPlugin<R> {
    tauri_plugin_global_shortcut::Builder::new()
        .with_handler(|app, shortcut, event| {
            if event.state() != ShortcutState::Pressed {
                return;
            }
            if shortcut == &recenter_shortcut() {
                recenter_active_device(app);
            }
            #[cfg(target_os = "windows")]
            if shortcut == &crate::grab::toggle_shortcut() {
                crate::grab::toggle();
            }
        })
        .build()
}

pub fn register<R: Runtime>(app: &AppHandle<R>) -> Result<(), Box<dyn std::error::Error>> {
    app.global_shortcut().register(recenter_shortcut())?;
    #[cfg(target_os = "windows")]
    app.global_shortcut().register(crate::grab::toggle_shortcut())?;
    Ok(())
}

fn recenter_active_device<R: Runtime>(app: &AppHandle<R>) {
    let state = app.state::<ScrcpyState>();
    let device_opt = state.active_device.lock().unwrap().clone();
    if let Some(device) = device_opt {
        crate::commands::recenter_device(&state, &device);
    }
}
