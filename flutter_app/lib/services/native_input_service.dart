// Turns a trusted, received `shanuconnect.mousepad` packet into an actual OS
// mouse action. Before this file, nothing in the app did this at all — the
// trackpad view only ever *sent* packets, and the desktop host only listened
// for notifications/sms/battery/mpris, silently dropping mousepad packets.
//
// Windows: bound directly to user32.dll via dart:ffi. Only flat-argument
// functions are used (SetCursorPos, GetCursorPos, mouse_event) — no complex
// struct marshalling beyond the simple two-field POINT struct, which keeps
// this safe to hand-write without a local Windows build to verify against.
//
// macOS/Linux: synthetic input requires either a signed/entitled native
// helper (macOS CGEvent) or a compositor-specific protocol (Wayland), which
// is real platform-integration work — not something to fake with placeholder
// FFI bindings. Instead this shells out to widely-available CLI tools
// (`cliclick` on macOS, `xdotool` on X11 Linux) when present, and returns a
// clear "not available" status when they aren't, rather than silently doing
// nothing the way the app did before.
import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart' as pkg_ffi;

enum InputSupport { supported, missingTool, unsupportedPlatform }

class NativeInputService {
  ffi.DynamicLibrary? _user32;
  bool _win32Checked = false;

  ffi.DynamicLibrary? get _user32Lib {
    if (!Platform.isWindows) return null;
    if (!_win32Checked) {
      _win32Checked = true;
      try {
        _user32 = ffi.DynamicLibrary.open('user32.dll');
      } catch (_) {
        _user32 = null;
      }
    }
    return _user32;
  }

  Future<InputSupport> checkSupport() async {
    if (Platform.isWindows) {
      return _user32Lib != null ? InputSupport.supported : InputSupport.unsupportedPlatform;
    }
    if (Platform.isMacOS) {
      return await _toolExists('cliclick') ? InputSupport.supported : InputSupport.missingTool;
    }
    if (Platform.isLinux) {
      return await _toolExists('xdotool') ? InputSupport.supported : InputSupport.missingTool;
    }
    return InputSupport.unsupportedPlatform;
  }

  Future<bool> _toolExists(String bin) async {
    try {
      final result = await Process.run(Platform.isWindows ? 'where' : 'which', [bin]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Moves the cursor by a relative (dx, dy) and optionally clicks.
  /// [click] is one of: 'left', 'right', 'double' (ShanuSend's own wire
  /// convention — see shanu_connect_service.dart's sendMousepad).
  Future<void> moveAndClick({required double dx, required double dy, String? click}) async {
    if (Platform.isWindows) {
      _moveWindows(dx, dy);
      if (click != null) _clickWindows(click);
      return;
    }
    if (Platform.isMacOS) {
      await _moveAndClickMac(dx, dy, click);
      return;
    }
    if (Platform.isLinux) {
      await _moveAndClickLinux(dx, dy, click);
      return;
    }
  }

  // ---- Windows (user32.dll via FFI) ----

  void _moveWindows(double dx, double dy) {
    final lib = _user32Lib;
    if (lib == null) return;

    final getCursorPos = lib
        .lookupFunction<ffi.Int32 Function(ffi.Pointer<_Win32Point>), int Function(ffi.Pointer<_Win32Point>)>(
            'GetCursorPos');
    final setCursorPos = lib
        .lookupFunction<ffi.Int32 Function(ffi.Int32, ffi.Int32), int Function(int, int)>('SetCursorPos');

    final point = pkg_ffi.calloc<_Win32Point>();
    try {
      getCursorPos(point);
      final newX = point.ref.x + dx.round();
      final newY = point.ref.y + dy.round();
      setCursorPos(newX, newY);
    } finally {
      pkg_ffi.calloc.free(point);
    }
  }

  void _clickWindows(String click) {
    final lib = _user32Lib;
    if (lib == null) return;
    final mouseEvent = lib.lookupFunction<
        ffi.Void Function(ffi.Uint32, ffi.Uint32, ffi.Uint32, ffi.Uint32, ffi.IntPtr),
        void Function(int, int, int, int, int)>('mouse_event');

    const mouseEventFLeftDown = 0x0002;
    const mouseEventFLeftUp = 0x0004;
    const mouseEventFRightDown = 0x0008;
    const mouseEventFRightUp = 0x0010;

    void singleLeftClick() {
      mouseEvent(mouseEventFLeftDown, 0, 0, 0, 0);
      mouseEvent(mouseEventFLeftUp, 0, 0, 0, 0);
    }

    switch (click) {
      case 'left':
        singleLeftClick();
        break;
      case 'right':
        mouseEvent(mouseEventFRightDown, 0, 0, 0, 0);
        mouseEvent(mouseEventFRightUp, 0, 0, 0, 0);
        break;
      case 'double':
        singleLeftClick();
        singleLeftClick();
        break;
    }
  }

  // ---- macOS (cliclick) ----

  Future<void> _moveAndClickMac(double dx, double dy, String? click) async {
    if (!await _toolExists('cliclick')) return;
    // cliclick's `m:+N,+M` moves relative to the current position.
    await Process.run('cliclick', ['m:+${dx.round()},+${dy.round()}']);
    switch (click) {
      case 'left':
        await Process.run('cliclick', ['c:.']);
        break;
      case 'right':
        await Process.run('cliclick', ['rc:.']);
        break;
      case 'double':
        await Process.run('cliclick', ['dc:.']);
        break;
    }
  }

  // ---- Linux (xdotool, X11 only — no Wayland support) ----

  Future<void> _moveAndClickLinux(double dx, double dy, String? click) async {
    if (!await _toolExists('xdotool')) return;
    await Process.run('xdotool', ['mousemove_relative', '--', dx.round().toString(), dy.round().toString()]);
    switch (click) {
      case 'left':
        await Process.run('xdotool', ['click', '1']);
        break;
      case 'right':
        await Process.run('xdotool', ['click', '3']);
        break;
      case 'double':
        await Process.run('xdotool', ['click', '--repeat', '2', '1']);
        break;
    }
  }
}

final class _Win32Point extends ffi.Struct {
  @ffi.Int32()
  external int x;
  @ffi.Int32()
  external int y;
}
