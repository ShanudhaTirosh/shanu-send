import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/device_dto.dart';
import '../services/shanu_connect_service.dart';

enum RemoteControlMode {
  touchpad,
  directTouch,
  pcDesktop,
}

class RemoteDesktopView extends StatefulWidget {
  final DeviceDto? targetDevice;
  final String? targetIp;
  final String deviceName;

  const RemoteDesktopView({
    super.key,
    this.targetDevice,
    this.targetIp,
    this.deviceName = 'Remote Host PC',
  });

  @override
  State<RemoteDesktopView> createState() => _RemoteDesktopViewState();
}

class _RemoteDesktopViewState extends State<RemoteDesktopView> {
  final ShanuConnectService _shanuService = ShanuConnectService();
  RemoteControlMode _controlMode = RemoteControlMode.touchpad;
  bool _isStreamingActive = false;
  bool _showVirtualKeyboard = false;
  bool _showToolbar = true;
  int _selectedDisplayIndex = 0;
  final int _fpsCounter = 60;
  final int _latencyMs = 18;


  final List<String> _displays = ['Display 1 (1920x1080)', 'Display 2 (2560x1440)'];
  final List<String> _shortcutKeys = ['Ctrl+Alt+Del', 'Alt+Tab', 'Win+D', 'Ctrl+C', 'Ctrl+V', 'Esc', 'Tab', 'Win'];

  String get _activeIp => widget.targetDevice?.ip ?? widget.targetIp ?? '127.0.0.1';
  String get _activeName => widget.targetDevice?.alias ?? widget.deviceName;

  @override
  void initState() {
    super.initState();
    _startRemoteDesktopStream();
  }

  void _startRemoteDesktopStream() {
    setState(() {
      _isStreamingActive = true;
    });
    _shanuService.sendRunCommand('start_remote_desktop', _activeIp);
  }

  @override
  void dispose() {
    _shanuService.sendRunCommand('stop_remote_desktop', _activeIp);
    super.dispose();
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  void _sendShortcut(String shortcut) {
    HapticFeedback.mediumImpact();
    switch (shortcut) {
      case 'Ctrl+Alt+Del':
        _shanuService.sendRunCommand('shortcut_ctrl_alt_del', _activeIp);
        break;
      case 'Alt+Tab':
        _shanuService.sendRunCommand('shortcut_alt_tab', _activeIp);
        break;
      case 'Win+D':
        _shanuService.sendRunCommand('shortcut_win_d', _activeIp);
        break;
      case 'Esc':
        _shanuService.sendMousepad(0, 0, targetIp: _activeIp);
        break;
      default:
        _shanuService.sendRunCommand('key_$shortcut', _activeIp);
        break;
    }
    _showToast('Triggered Remote Shortcut: $shortcut');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.desktop_windows_rounded, color: theme.colorScheme.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_activeName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                Text(
                  'Remote Desktop Session • $_activeIp • $_fpsCounter FPS (${_latencyMs}ms)',
                  style: TextStyle(color: theme.colorScheme.primary, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_showToolbar ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: theme.colorScheme.primary),
            tooltip: 'Toggle Remote Control Bar',
            onPressed: () => setState(() => _showToolbar = !_showToolbar),
          ),
          IconButton(
            icon: Icon(Icons.keyboard_rounded, color: _showVirtualKeyboard ? theme.colorScheme.primary : Colors.white70),
            tooltip: 'Toggle Virtual Key Drawer',
            onPressed: () => setState(() => _showVirtualKeyboard = !_showVirtualKeyboard),
          ),
          PopupMenuButton<int>(
            icon: const Icon(Icons.monitor_rounded, color: Colors.white70),
            tooltip: 'Select Target Display',
            onSelected: (idx) {
              setState(() => _selectedDisplayIndex = idx);
              _showToast('Switched to ${_displays[idx]}');
            },
            itemBuilder: (ctx) => _displays.asMap().entries.map((entry) {
              return PopupMenuItem<int>(
                value: entry.key,
                child: Row(
                  children: [
                    Icon(
                      entry.key == _selectedDisplayIndex ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                      color: theme.colorScheme.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(entry.value, style: const TextStyle(fontSize: 13)),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Screen Stream Canvas & Touch Surface
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 4.0,
              child: GestureDetector(
                onPanUpdate: (details) {
                  if (_controlMode == RemoteControlMode.touchpad) {
                    _shanuService.sendMousepad(details.delta.dx, details.delta.dy, targetIp: _activeIp);
                  }
                },
                onTapDown: (details) {
                  HapticFeedback.lightImpact();
                  if (_controlMode == RemoteControlMode.directTouch) {
                    // Send absolute cursor click event
                    _shanuService.sendMousepad(details.localPosition.dx, details.localPosition.dy, click: 'left', targetIp: _activeIp);
                  } else {
                    _shanuService.sendMousepad(0, 0, click: 'left', targetIp: _activeIp);
                  }
                },
                onSecondaryTap: () {
                  HapticFeedback.mediumImpact();
                  _shanuService.sendMousepad(0, 0, click: 'right', targetIp: _activeIp);
                },
                child: Container(
                  color: Colors.black,
                  child: Center(
                    child: _isStreamingActive
                        ? AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                                image: const DecorationImage(
                                  image: AssetImage('logo.png'), // Placeholder wallpaper until live frames
                                  fit: BoxFit.cover,
                                ),
                              ),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.5)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F2FE)),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Streaming ${_displays[_selectedDisplayIndex]} over LAN (Low Latency)...',
                                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          )
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.desktop_access_disabled_rounded, size: 64, color: Colors.white38),
                              SizedBox(height: 12),
                              Text('Remote Desktop Stream Disconnected', style: TextStyle(color: Colors.white70, fontSize: 16)),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),

          // Floating Control Toolbar
          if (_showToolbar)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white10),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.touch_app_rounded, color: Color(0xFF00F2FE), size: 18),
                    const SizedBox(width: 8),
                    const Text('Mode:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    SegmentedButton<RemoteControlMode>(
                      segments: const [
                        ButtonSegment(value: RemoteControlMode.touchpad, label: Text('Trackpad', style: TextStyle(fontSize: 11))),
                        ButtonSegment(value: RemoteControlMode.directTouch, label: Text('Direct Touch', style: TextStyle(fontSize: 11))),
                      ],
                      selected: {_controlMode},
                      onSelectionChanged: (selected) {
                        setState(() => _controlMode = selected.first);
                      },
                      style: SegmentedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        selectedBackgroundColor: theme.colorScheme.primary,
                        selectedForegroundColor: Colors.black,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.mouse_rounded, color: Colors.white),
                      tooltip: 'Left Click',
                      onPressed: () => _shanuService.sendMousepad(0, 0, click: 'left', targetIp: _activeIp),
                    ),
                    IconButton(
                      icon: const Icon(Icons.mouse_outlined, color: Colors.white),
                      tooltip: 'Right Click',
                      onPressed: () => _shanuService.sendMousepad(0, 0, click: 'right', targetIp: _activeIp),
                    ),
                  ],
                ),
              ),
            ),

          // Bottom Shortcut Key Drawer
          if (_showVirtualKeyboard)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.95),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Quick Remote Shortcuts', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                          onPressed: () => setState(() => _showVirtualKeyboard = false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _shortcutKeys.map((key) {
                        return ActionChip(
                          backgroundColor: const Color(0xFF334155),
                          label: Text(key, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                          onPressed: () => _sendShortcut(key),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
