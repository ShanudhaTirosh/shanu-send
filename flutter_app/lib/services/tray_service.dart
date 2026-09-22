import 'dart:io' show Platform, exit;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class TrayService with TrayListener, WindowListener {
  static final TrayService _instance = TrayService._internal();
  factory TrayService() => _instance;
  TrayService._internal();

  bool _initialized = false;
  VoidCallback? _onOpenWebDrop;
  VoidCallback? _onToggleAutoAccept;
  bool _autoAccept = false;

  bool get isDesktop => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  Future<void> initialize({
    VoidCallback? onOpenWebDrop,
    VoidCallback? onToggleAutoAccept,
    bool autoAccept = false,
  }) async {
    if (!isDesktop || _initialized) return;

    _onOpenWebDrop = onOpenWebDrop;
    _onToggleAutoAccept = onToggleAutoAccept;
    _autoAccept = autoAccept;
    _initialized = true;

    await windowManager.ensureInitialized();
    windowManager.addListener(this);

    // Set window close behavior to prevent default close and hide to tray
    await windowManager.setPreventClose(true);

    try {
      await trayManager.setIcon(
        Platform.isWindows
            ? 'assets/images/app_icon.ico'
            : 'assets/images/app_icon.png',
      );
    } catch (_) {
      // Fallback if asset missing
    }

    await trayManager.setToolTip('ShanuSend - High-Speed P2P & WebDrop');
    await updateContextMenu();
    trayManager.addListener(this);
  }

  Future<void> updateContextMenu([bool? autoAcceptState]) async {
    if (!isDesktop) return;
    if (autoAcceptState != null) {
      _autoAccept = autoAcceptState;
    }

    List<MenuItem> items = [
      MenuItem(
        key: 'open_app',
        label: 'Open ShanuSend',
      ),
      MenuItem(
        key: 'open_webdrop',
        label: 'AirDrop / WebDrop Portal',
      ),
      MenuItem.separator(),
      MenuItem.checkbox(
        key: 'toggle_auto_accept',
        label: 'Auto-Accept Files',
        checked: _autoAccept,
      ),
      MenuItem.separator(),
      MenuItem(
        key: 'exit_app',
        label: 'Exit ShanuSend',
      ),
    ];

    await trayManager.setContextMenu(Menu(items: items));
  }

  @override
  void onTrayIconMouseDown() {
    restoreWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'open_app') {
      restoreWindow();
    } else if (menuItem.key == 'open_webdrop') {
      restoreWindow();
      _onOpenWebDrop?.call();
    } else if (menuItem.key == 'toggle_auto_accept') {
      _autoAccept = !_autoAccept;
      _onToggleAutoAccept?.call();
      updateContextMenu();
    } else if (menuItem.key == 'exit_app') {
      exitApp();
    }
  }

  @override
  void onWindowClose() async {
    if (isDesktop) {
      bool isPrevent = await windowManager.isPreventClose();
      if (isPrevent) {
        await windowManager.hide();
      }
    }
  }

  Future<void> restoreWindow() async {
    if (!isDesktop) return;
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> exitApp() async {
    if (isDesktop) {
      await windowManager.setPreventClose(false);
      await windowManager.destroy();
    }
    exit(0);
  }

  void dispose() {
    if (!isDesktop) return;
    trayManager.removeListener(this);
    windowManager.removeListener(this);
  }
}
