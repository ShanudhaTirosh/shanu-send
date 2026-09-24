import 'dart:io' show Platform, File;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/device_dto.dart';
import '../models/file_dto.dart';
import '../services/discovery_service.dart';
import '../services/transfer_service.dart';
import '../services/unified_http_server.dart';
import '../services/notification_service.dart';
import '../services/tray_service.dart';
import '../services/clipboard_sync_service.dart';
import '../widgets/webdrop_modal.dart';

import 'tabs/receive_tab.dart';
import 'tabs/send_tab.dart';
import 'tabs/settings_tab.dart';
import 'shanu_connect_view.dart';
import 'desktop_phone_link_view.dart';
import 'scrcpy_gui_view.dart';
import 'remote_desktop_view.dart';

class HomeView extends StatefulWidget {
  final List<String> initialFiles;

  const HomeView({
    super.key,
    this.initialFiles = const [],
  });

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final DiscoveryService _discoveryService = DiscoveryService();
  final TransferService _transferService = TransferService();
  final UnifiedHttpServer _httpServer = UnifiedHttpServer();
  final TrayService _trayService = TrayService();
  final ClipboardSyncService _clipboardSyncService = ClipboardSyncService();

  int _currentNavIndex = 0;
  String? _localIp;
  String _deviceAlias = 'ShanuSend Device';
  bool _autoAccept = false;
  bool _autoSyncClipboard = false;
  TransferStatus? _activeTransfer;
  DeviceDto? _selectedDevice;
  final List<FileDto> _prepopulatedFiles = [];

  bool get _isDesktop => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    _handleInitialFiles();
    _initServices();
  }

  void _handleInitialFiles() {
    if (widget.initialFiles.isNotEmpty) {
      for (final path in widget.initialFiles) {
        final f = File(path);
        if (f.existsSync()) {
          final stat = f.statSync();
          _prepopulatedFiles.add(
            FileDto(
              id: const Uuid().v4(),
              fileName: f.path.split(Platform.pathSeparator).last,
              size: stat.size,
              fileType: 'file',
              path: f.path,
            ),
          );
        }
      }
      if (_prepopulatedFiles.isNotEmpty) {
        _currentNavIndex = 1; // Switch directly to SendTab
      }
    }
  }

  Future<void> _initServices() async {
    final ip = await _discoveryService.getLocalIp();
    setState(() {
      _localIp = ip;
      _deviceAlias = '${_getPlatformPrefix()} (${ip ?? "Local"})';
    });

    // Start Unified HTTP Server on port 53317 (handles LocalSend API AND WebDrop Browser HTML)
    await _httpServer.startServer();
    await NotificationService().initialize();

    // Initialize System Tray for Desktop
    await _trayService.initialize(
      onOpenWebDrop: _openWebDropModal,
      onToggleAutoAccept: () {
        setState(() => _autoAccept = !_autoAccept);
      },
      autoAccept: _autoAccept,
    );

    // Continuous LAN Discovery
    _discoveryService.scanSubnet();

    _httpServer.eventStream.listen((event) {
      if (event.type == 'incoming-request') {
        final data = event.data;
        final senderAlias = data['senderAlias'] as String? ?? 'Device';
        final files = data['files'] as Map<String, dynamic>? ?? {};
        final sessionId = data['sessionId'] as String? ?? 'session';

        if (_autoAccept) {
          _httpServer.respondToRequest(sessionId, true);
          return;
        }

        NotificationService().showIncomingTransferAlert(
          senderAlias: senderAlias,
          fileCount: files.length,
          sessionId: sessionId,
        );

        _promptIncomingRequest(sessionId, senderAlias, files);
      } else if (event.type == 'upload-progress') {
        final data = event.data;
        final rec = data['receivedBytes'] as int? ?? 0;
        final tot = data['totalBytes'] as int? ?? 1;
        setState(() {
          _activeTransfer = TransferStatus(
            sessionId: data['sessionId'] as String? ?? 'recv',
            fileName: 'Receiving File...',
            receivedBytes: rec,
            totalBytes: tot,
            speedMBps: 12.5,
            etaSeconds: 1,
            isCompleted: rec >= tot,
          );
        });
      } else if (event.type == 'upload-complete') {
        final data = event.data;
        final fileName = data['fileName'] as String? ?? 'File';
        final savePath = data['savePath'] as String? ?? '';
        setState(() {
          _activeTransfer = TransferStatus(
            sessionId: data['sessionId'] as String? ?? 'complete',
            fileName: 'Received: $fileName',
            receivedBytes: 100,
            totalBytes: 100,
            speedMBps: 0.0,
            etaSeconds: 0,
            isCompleted: true,
          );
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(savePath.isNotEmpty ? 'File Saved: $fileName' : 'File Received: $fileName'),
              backgroundColor: const Color(0xFF00D285),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    });

    _transferService.statusStream.listen((status) {
      setState(() {
        _activeTransfer = status;
      });
    });

    // Auto-select first discovered device when available
    _discoveryService.deviceStream.listen((devices) {
      if (devices.isNotEmpty && _selectedDevice == null) {
        setState(() {
          _selectedDevice = devices.first;
        });
      }
    });
  }

  void _toggleAutoSyncClipboard(bool enable) {
    setState(() => _autoSyncClipboard = enable);
    if (enable) {
      _clipboardSyncService.startAutoSync(
        onClipboardChanged: (text) {
          // If a connected device exists, broadcast clipboard packet
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Clipboard text updated & synced across devices'),
              duration: Duration(seconds: 2),
            ),
          );
        },
      );
    } else {
      _clipboardSyncService.stopAutoSync();
    }
  }

  String _getPlatformPrefix() {
    if (kIsWeb) return 'Web Drop';
    if (Platform.isWindows) return 'Windows PC';
    if (Platform.isMacOS) return 'Mac Workstation';
    if (Platform.isLinux) return 'Linux PC';
    if (Platform.isAndroid) return 'Android Phone';
    if (Platform.isIOS) return 'iPhone';
    return 'ShanuSend Device';
  }

  @override
  void dispose() {
    _discoveryService.dispose();
    _transferService.dispose();
    _httpServer.dispose();
    _trayService.dispose();
    _clipboardSyncService.dispose();
    super.dispose();
  }

  Future<void> _promptIncomingRequest(
    String sessionId,
    String senderAlias,
    Map<String, dynamic> files,
  ) async {
    if (!mounted) {
      _httpServer.respondToRequest(sessionId, false);
      return;
    }

    final fileNames = files.values
        .map((f) => (f as Map<String, dynamic>?)?['fileName'] as String? ?? 'file')
        .toList();

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Incoming files from $senderAlias'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${files.length} file${files.length == 1 ? '' : 's'}:'),
              const SizedBox(height: 8),
              ...fileNames.take(5).map(
                    (n) => Text('•  $n', overflow: TextOverflow.ellipsis, maxLines: 1),
                  ),
              if (fileNames.length > 5) Text('…and ${fileNames.length - 5} more'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Decline'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Accept'),
          ),
        ],
      ),
    );

    _httpServer.respondToRequest(sessionId, accepted ?? false);
  }

  void _openWebDropModal() {
    if (_localIp == null) return;
    showDialog(
      context: context,
      builder: (_) => WebDropModal(localIp: _localIp!),
    );
  }

  void _openRemoteController([String deviceName = 'Host PC']) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShanuConnectView(deviceName: deviceName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWideScreen = MediaQuery.of(context).size.width >= 720;

    final pages = _isDesktop
        ? [
            ReceiveTab(
              localIp: _localIp,
              deviceAlias: _deviceAlias,
              autoAccept: _autoAccept,
              onAutoAcceptChanged: (v) {
                setState(() => _autoAccept = v);
                _trayService.updateContextMenu(v);
              },
              onOpenWebDrop: _openWebDropModal,
              activeTransfer: _activeTransfer,
            ),
            SendTab(
              discoveryService: _discoveryService,
              transferService: _transferService,
              selectedDevice: _selectedDevice,
              onDeviceSelected: (d) => setState(() => _selectedDevice = d),
              onOpenRemoteController: _openRemoteController,
            ),
            StreamBuilder<List<DeviceDto>>(
              stream: _discoveryService.deviceStream,
              initialData: _discoveryService.devices,
              builder: (context, snapshot) {
                final devices = snapshot.data ?? [];
                return DesktopPhoneLinkView(
                  devices: devices,
                  initialSelectedDevice: _selectedDevice,
                  onDeviceSelected: (d) => setState(() => _selectedDevice = d),
                  onPairRequested: () => _openRemoteController(_selectedDevice?.alias ?? 'Host PC'),
                );
              },
            ),
            RemoteDesktopView(
              targetDevice: _selectedDevice,
              targetIp: _selectedDevice?.ip,
              deviceName: _selectedDevice?.alias ?? 'Host PC',
            ),
            const ScrcpyGuiView(),
            SettingsTab(
              deviceAlias: _deviceAlias,
              onAliasChanged: (alias) => setState(() => _deviceAlias = alias),
              autoSyncClipboard: _autoSyncClipboard,
              onAutoSyncClipboardChanged: _toggleAutoSyncClipboard,
              onOpenWebDrop: _openWebDropModal,
            ),
          ]
        : [
            ReceiveTab(
              localIp: _localIp,
              deviceAlias: _deviceAlias,
              autoAccept: _autoAccept,
              onAutoAcceptChanged: (v) {
                setState(() => _autoAccept = v);
                _trayService.updateContextMenu(v);
              },
              onOpenWebDrop: _openWebDropModal,
              activeTransfer: _activeTransfer,
            ),
            SendTab(
              discoveryService: _discoveryService,
              transferService: _transferService,
              selectedDevice: _selectedDevice,
              onDeviceSelected: (d) => setState(() => _selectedDevice = d),
              onOpenRemoteController: _openRemoteController,
            ),
            StreamBuilder<List<DeviceDto>>(
              stream: _discoveryService.deviceStream,
              initialData: _discoveryService.devices,
              builder: (context, snapshot) {
                final devices = snapshot.data ?? [];
                return ShanuConnectView(
                  deviceName: _selectedDevice?.alias ?? 'Host PC',
                  targetIp: _selectedDevice?.ip,
                  devices: devices,
                );
              },
            ),
            RemoteDesktopView(
              targetDevice: _selectedDevice,
              targetIp: _selectedDevice?.ip,
              deviceName: _selectedDevice?.alias ?? 'Host PC',
            ),
            SettingsTab(
              deviceAlias: _deviceAlias,
              onAliasChanged: (alias) => setState(() => _deviceAlias = alias),
              autoSyncClipboard: _autoSyncClipboard,
              onAutoSyncClipboardChanged: _toggleAutoSyncClipboard,
              onOpenWebDrop: _openWebDropModal,
            ),
          ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            const Text(
              'ShanuSend Pro',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_rounded),
            tooltip: 'WebDrop QR Modal',
            onPressed: _openWebDropModal,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Scan LAN',
            onPressed: () => _discoveryService.scanSubnet(),
          ),
        ],
      ),
      body: isWideScreen
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _currentNavIndex,
                  onDestinationSelected: (idx) => setState(() => _currentNavIndex = idx),
                  labelType: NavigationRailLabelType.all,
                  selectedIconTheme: IconThemeData(color: theme.colorScheme.primary),
                  selectedLabelTextStyle: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                  destinations: _isDesktop
                      ? const [
                          NavigationRailDestination(
                            icon: Icon(Icons.download_rounded),
                            selectedIcon: Icon(Icons.download_done_rounded),
                            label: Text('Receive'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.send_rounded),
                            selectedIcon: Icon(Icons.send_rounded),
                            label: Text('Send'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.smartphone_rounded),
                            label: Text('Phone Link'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.desktop_windows_rounded),
                            label: Text('Remote PC'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.aspect_ratio_rounded),
                            label: Text('Scrcpy GUI'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.settings_rounded),
                            label: Text('Settings'),
                          ),
                        ]
                      : const [
                          NavigationRailDestination(
                            icon: Icon(Icons.download_rounded),
                            label: Text('Receive'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.send_rounded),
                            label: Text('Send'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.mouse_rounded),
                            label: Text('Remote'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.desktop_windows_rounded),
                            label: Text('Remote PC'),
                          ),
                          NavigationRailDestination(
                            icon: Icon(Icons.settings_rounded),
                            label: Text('Settings'),
                          ),
                        ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: pages[_currentNavIndex],
                  ),
                ),
              ],
            )
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: pages[_currentNavIndex],
            ),
      bottomNavigationBar: isWideScreen
          ? null
          : BottomNavigationBar(
              currentIndex: _currentNavIndex,
              onTap: (idx) => setState(() => _currentNavIndex = idx),
              selectedItemColor: theme.colorScheme.primary,
              unselectedItemColor: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
              type: BottomNavigationBarType.fixed,
              items: _isDesktop
                  ? const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.download_rounded),
                        label: 'Receive',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.send_rounded),
                        label: 'Send',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.smartphone_rounded),
                        label: 'Phone Link',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.desktop_windows_rounded),
                        label: 'Remote PC',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.aspect_ratio_rounded),
                        label: 'Scrcpy',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.settings_rounded),
                        label: 'Settings',
                      ),
                    ]
                  : const [
                      BottomNavigationBarItem(
                        icon: Icon(Icons.download_rounded),
                        label: 'Receive',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.send_rounded),
                        label: 'Send',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.mouse_rounded),
                        label: 'Remote',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.desktop_windows_rounded),
                        label: 'Remote PC',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(Icons.settings_rounded),
                        label: 'Settings',
                      ),
                    ],
            ),
    );

  }
}
