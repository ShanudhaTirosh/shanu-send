import 'dart:io' show Platform;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/device_dto.dart';
import '../models/file_dto.dart';
import '../services/discovery_service.dart';
import '../services/transfer_service.dart';
import '../services/unified_http_server.dart';
import '../services/notification_service.dart';
import '../widgets/speed_badge.dart';
import '../widgets/webdrop_modal.dart';

import 'shanu_connect_view.dart';
import 'desktop_phone_link_view.dart';
import 'scrcpy_gui_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final DiscoveryService _discoveryService = DiscoveryService();
  final TransferService _transferService = TransferService();
  final UnifiedHttpServer _httpServer = UnifiedHttpServer();

  int _currentNavIndex = 0;
  String? _localIp;
  List<FileDto> _selectedFiles = [];
  TransferStatus? _activeTransfer;
  DeviceDto? _selectedDevice;

  bool get _isDesktop => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    _initServices();
  }

  Future<void> _initServices() async {
    final ip = await _discoveryService.getLocalIp();
    setState(() {
      _localIp = ip;
    });

    // Start Unified HTTP Server on port 53317 (handles LocalSend API AND WebDrop Browser HTML)
    await _httpServer.startServer();
    await NotificationService().initialize();

    // Continuous LAN Discovery
    _discoveryService.scanSubnet();

    _httpServer.eventStream.listen((event) {
      if (event.type == 'incoming-request') {
        final data = event.data;
        final senderAlias = data['senderAlias'] as String? ?? 'Device';
        final files = data['files'] as Map<String, dynamic>? ?? {};
        final sessionId = data['sessionId'] as String? ?? 'session';

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
              backgroundColor: const Color(0xFF059669),
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

  @override
  void dispose() {
    _discoveryService.dispose();
    _transferService.dispose();
    _httpServer.dispose();
    super.dispose();
  }

  /// Shows an Accept/Decline dialog for an incoming transfer and reports the
  /// decision back to the server, which is now blocked waiting on it (see
  /// UnifiedHttpServer._handlePrepareUpload). Previously nothing called
  /// respondToRequest at all, so every incoming transfer was written to disk
  /// automatically regardless of what this dialog showed.
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

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFiles = result.files
            .where((f) => f.path != null)
            .map((f) => FileDto(
                  id: const Uuid().v4(),
                  fileName: f.name,
                  size: f.size,
                  fileType: 'other',
                  path: f.path,
                ))
            .toList();
      });
    }
  }

  void _openWebDropModal() {
    if (_localIp == null) return;
    showDialog(
      context: context,
      builder: (_) => WebDropModal(localIp: _localIp!),
    );
  }

  void _openRemoteController([String deviceName = 'Desktop PC']) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShanuConnectView(deviceName: deviceName),
      ),
    );
  }

  String _getPlatformLabel() {
    if (kIsWeb) return 'Web';
    if (Platform.isWindows) return 'Windows Desktop';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return 'Native App';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F19),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: Color(0xFF38BDF8), size: 28),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ShanuSend',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  _getPlatformLabel(),
                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        actions: [
          StreamBuilder<List<DeviceDto>>(
            stream: _discoveryService.deviceStream,
            initialData: _discoveryService.devices,
            builder: (context, snapshot) {
              final devices = snapshot.data ?? [];
              if (devices.isEmpty) return const SizedBox.shrink();

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF161E2E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF283548)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<DeviceDto>(
                    value: _selectedDevice,
                    dropdownColor: const Color(0xFF161E2E),
                    icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF38BDF8)),
                    hint: const Text('Select Target Device', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    items: devices.map((d) {
                      return DropdownMenuItem<DeviceDto>(
                        value: d,
                        child: Text(
                          d.alias,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      );
                    }).toList(),
                    onChanged: (dev) {
                      if (dev != null) {
                        setState(() => _selectedDevice = dev);
                      }
                    },
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.radar_rounded, color: Color(0xFF38BDF8)),
            tooltip: 'AirDrop / WebDrop Portal',
            onPressed: _openWebDropModal,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Color(0xFF94A3B8)),
            tooltip: 'Rescan LAN',
            onPressed: () => _discoveryService.scanSubnet(),
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentNavIndex,
        children: _isDesktop
            ? [
                _buildTransfersTab(),
                StreamBuilder<List<DeviceDto>>(
                  stream: _discoveryService.deviceStream,
                  initialData: _discoveryService.devices,
                  builder: (context, snapshot) {
                    final devices = snapshot.data ?? [];
                    return DesktopPhoneLinkView(
                      devices: devices,
                      initialSelectedDevice: _selectedDevice,
                      onDeviceSelected: (d) => setState(() => _selectedDevice = d),
                      onPairRequested: () => _openRemoteController(_selectedDevice?.alias ?? 'Desktop PC'),
                    );
                  },
                ),
                const ScrcpyGuiView(),
                _buildWebDropTab(),
              ]
            : [
                _buildTransfersTab(),
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
                _buildWebDropTab(),
              ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentNavIndex,
        onTap: (idx) => setState(() => _currentNavIndex = idx),
        backgroundColor: const Color(0xFF090B11),
        selectedItemColor: const Color(0xFF38BDF8),
        unselectedItemColor: const Color(0xFF64748B),
        type: BottomNavigationBarType.fixed,
        items: _isDesktop
            ? const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.swap_horiz_rounded),
                  label: 'Transfers',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.smartphone_rounded),
                  label: 'Phone Link',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.aspect_ratio_rounded),
                  label: 'Scrcpy GUI',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.language_rounded),
                  label: 'WebDrop',
                ),
              ]
            : const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.swap_horiz_rounded),
                  label: 'Transfers',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.mouse_rounded),
                  label: 'Remote & Hub',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.language_rounded),
                  label: 'WebDrop',
                ),
              ],
      ),
    );
  }

  Widget _buildTransfersTab() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_activeTransfer != null) ...[
            SpeedBadge(status: _activeTransfer!),
            const SizedBox(height: 20),
          ],

          // Quick Actions Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF161E2E), Color(0xFF1E1B4B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF283548)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedFiles.isEmpty
                            ? 'Select files to send'
                            : '${_selectedFiles.length} file(s) ready for sending',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _localIp != null ? 'Your IP: $_localIp' : 'Detecting network...',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(_selectedFiles.isEmpty ? 'Select Files' : 'Change Files'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Nearby Discovered Endpoints',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              StreamBuilder<List<DeviceDto>>(
                stream: _discoveryService.deviceStream,
                builder: (context, snapshot) {
                  final isScanning = _discoveryService.isScanning;
                  return Row(
                    children: [
                      if (isScanning)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF38BDF8)),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        '${snapshot.data?.length ?? 0} found',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Discovered Devices List
          Expanded(
            child: StreamBuilder<List<DeviceDto>>(
              stream: _discoveryService.deviceStream,
              initialData: _discoveryService.devices,
              builder: (context, snapshot) {
                final devices = snapshot.data ?? [];
                if (devices.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.radar_rounded, size: 64, color: Colors.white.withValues(alpha: 0.2)),
                        const SizedBox(height: 12),
                        const Text(
                          'Scanning local network continuously...',
                          style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Supports LocalSend, Quick Share, AirDrop & ShanuSend P2P',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final isSelected = _selectedDevice?.ip == device.ip;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF1E293B) : const Color(0xFF161E2E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF283548)),
                      ),
                      child: ListTile(
                        onTap: () => setState(() => _selectedDevice = device),
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                          child: Icon(
                            _getDeviceIcon(device.deviceType),
                            color: const Color(0xFF38BDF8),
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              device.alias,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF38BDF8).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'LocalSend v2.1',
                                style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'ShanuSend P2P',
                                style: TextStyle(color: Color(0xFFA5B4FC), fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          '${device.ip} • ${device.deviceModel}',
                          style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.mouse_rounded, color: Color(0xFF38BDF8)),
                              tooltip: 'Remote Control ${device.alias}',
                              onPressed: () => _openRemoteController(device.alias),
                            ),
                            ElevatedButton(
                              onPressed: _selectedFiles.isEmpty
                                  ? null
                                  : () => _transferService.sendFiles(
                                        targetDevice: device,
                                        files: _selectedFiles,
                                      ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF38BDF8),
                                foregroundColor: const Color(0xFF0B0F19),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              child: const Text('Send', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWebDropTab() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.language_rounded, size: 72, color: Color(0xFF38BDF8)),
          const SizedBox(height: 16),
          const Text(
            'WebDrop Browser Sharing Portal',
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Share files with any web browser on iOS Safari, Android Chrome, Windows, Mac, or Linux without installing software.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF161E2E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF283548)),
            ),
            child: Column(
              children: [
                const Text('Web Browser Address:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                SelectableText(
                  _localIp != null ? 'http://$_localIp:53317' : 'http://192.168.1.x:53317',
                  style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 22, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _openWebDropModal,
                  icon: const Icon(Icons.qr_code_rounded),
                  label: const Text('Show QR Code & Link Modal'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF38BDF8),
                    foregroundColor: const Color(0xFF0B0F19),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getDeviceIcon(String type) {
    switch (type.toLowerCase()) {
      case 'mobile':
      case 'phone':
      case 'ios':
      case 'android':
        return Icons.smartphone_rounded;
      case 'desktop':
      case 'windows':
      case 'mac':
      case 'linux':
        return Icons.laptop_rounded;
      default:
        return Icons.devices_rounded;
    }
  }
}
