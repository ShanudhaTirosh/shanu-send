//! Windows-only: drag the borderless scrcpy mirror window with the mouse.
//!
//! scrcpy's `--window-borderless` window has no title bar, and Windows, unlike
//! GNOME/KDE, which provide Super/Meta+drag, has no built-in way to move such a
//! window. (A title bar can't simply be added from the outside either: scrcpy's
//! SDL window owns its non-client area, so an externally-set WS_CAPTION never
//! renders.) This registers a global shortcut (Ctrl+Alt+Shift+W) that "grabs"
//! the focused scrcpy window: the cursor jumps to the window's centre and the
//! window then follows the mouse. Drop it with a left click or by pressing the
//! shortcut again. The window is moved from the outside via Win32 `SetWindowPos`;
//! scrcpy itself is never touched.

use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use tauri::{AppHandle, Manager, Runtime};
use tauri_plugin_global_shortcut::{Code, Modifiers, Shortcut};

use windows::Win32::Foundation::{HINSTANCE, HWND, LPARAM, LRESULT, POINT, RECT, WPARAM};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::UI::WindowsAndMessaging::{
    CallNextHookEx, GetCursorPos, GetForegroundWindow, GetWindowRect, GetWindowThreadProcessId,
    IsZoomed, PeekMessageW, SetCursorPos, SetWindowsHookExW, SetWindowPos, UnhookWindowsHookEx,
    HC_ACTION, HHOOK, MSG, PM_REMOVE, SWP_NOACTIVATE, SWP_NOSIZE, SWP_NOZORDER, WH_MOUSE_LL,
    WM_LBUTTONDOWN,
};

use crate::commands::ScrcpyState;

/// Whether a grab is in progress. Flipped by the shortcut handler, ended by the
/// mouse hook on a left click, and polled by the follow thread.
static GRAB_ACTIVE: AtomicBool = AtomicBool::new(false);

pub fn toggle_shortcut() -> Shortcut {
    Shortcut::new(
        Some(Modifiers::CONTROL | Modifiers::ALT | Modifiers::SHIFT),
        Code::KeyW,
    )
}

pub fn toggle() {
    GRAB_ACTIVE.fetch_xor(true, Ordering::SeqCst);
}

pub fn register<R: Runtime>(app: &AppHandle<R>) {
    let handle = app.clone();
    std::thread::spawn(move || follow_loop(handle));
}

fn follow_loop<R: Runtime>(app: AppHandle<R>) {
    let mut grabbed: Option<GrabbedWindow> = None;
    let mut hook: Option<HHOOK> = None;

    loop {
        if !GRAB_ACTIVE.load(Ordering::SeqCst) {
            release_hook(&mut hook);
            grabbed = None;
            std::thread::sleep(Duration::from_millis(40));
            continue;
        }

        if grabbed.is_none() {
            match GrabbedWindow::arm(&app) {
                Some(g) => {
                    grabbed = Some(g);
                    hook = install_hook();
                }
                None => {
                    GRAB_ACTIVE.store(false, Ordering::SeqCst);
                    continue;
                }
            }
        }

        pump_messages();
        if let Some(g) = &grabbed {
            if !g.follow_cursor() {
                GRAB_ACTIVE.store(false, Ordering::SeqCst);
                release_hook(&mut hook);
                grabbed = None;
                continue;
            }
        }
        std::thread::sleep(Duration::from_millis(6));
    }
}

struct GrabbedWindow {
    hwnd: HWND,
    offset: (i32, i32),
}

impl GrabbedWindow {
    fn arm<R: Runtime>(app: &AppHandle<R>) -> Option<GrabbedWindow> {
        let fg = unsafe { GetForegroundWindow() };
        if fg.0.is_null() {
            return None;
        }
        let mut pid: u32 = 0;
        unsafe { GetWindowThreadProcessId(fg, Some(&mut pid)) };
        if pid == 0 || !pid_is_ours(app, pid) {
            return None;
        }
        if unsafe { IsZoomed(fg) }.as_bool() {
            return None;
        }
        let mut rect = RECT::default();
        if unsafe { GetWindowRect(fg, &mut rect) }.is_err() {
            return None;
        }
        let centre = ((rect.left + rect.right) / 2, (rect.top + rect.bottom) / 2);
        let _ = unsafe { SetCursorPos(centre.0, centre.1) };
        Some(GrabbedWindow {
            hwnd: fg,
            offset: (centre.0 - rect.left, centre.1 - rect.top),
        })
    }

    fn follow_cursor(&self) -> bool {
        let Some((cx, cy)) = cursor_pos() else {
            return true;
        };
        unsafe {
            SetWindowPos(
                self.hwnd,
                None,
                cx - self.offset.0,
                cy - self.offset.1,
                0,
                0,
                SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE,
            )
        }
        .is_ok()
    }
}

unsafe extern "system" fn mouse_hook(code: i32, wparam: WPARAM, lparam: LPARAM) -> LRESULT {
    if code == HC_ACTION as i32
        && wparam.0 as u32 == WM_LBUTTONDOWN
        && GRAB_ACTIVE.load(Ordering::SeqCst)
    {
        GRAB_ACTIVE.store(false, Ordering::SeqCst);
        return LRESULT(1);
    }
    CallNextHookEx(None, code, wparam, lparam)
}

fn install_hook() -> Option<HHOOK> {
    let hmod = unsafe { GetModuleHandleW(None) }.ok()?;
    unsafe { SetWindowsHookExW(WH_MOUSE_LL, Some(mouse_hook), Some(HINSTANCE(hmod.0)), 0) }.ok()
}

fn release_hook(hook: &mut Option<HHOOK>) {
    if let Some(h) = hook.take() {
        let _ = unsafe { UnhookWindowsHookEx(h) };
    }
}

fn pump_messages() {
    let mut msg = MSG::default();
    while unsafe { PeekMessageW(&mut msg, None, 0, 0, PM_REMOVE) }.as_bool() {}
}

fn pid_is_ours<R: Runtime>(app: &AppHandle<R>, pid: u32) -> bool {
    app.state::<ScrcpyState>()
        .processes
        .lock()
        .unwrap()
        .values()
        .any(|child| child.id() == Some(pid))
}

fn cursor_pos() -> Option<(i32, i32)> {
    let mut p = POINT::default();
    if unsafe { GetCursorPos(&mut p) }.is_ok() {
        Some((p.x, p.y))
    } else {
        None
    }
}
