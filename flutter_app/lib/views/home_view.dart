import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/device_dto.dart';
import '../models/file_dto.dart';
import '../services/discovery_service.dart';
import '../services/transfer_service.dart';
import '../services/webdrop_server.dart';
import '../widgets/speed_badge.dart';
import '../widgets/webdrop_modal.dart';

import 'kde_connect_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final DiscoveryService _discoveryService = DiscoveryService();
  final TransferService _transferService = TransferService();
  final WebDropServer _webDropServer = WebDropServer();

  String? _localIp;
  List<FileDto> _selectedFiles = [];
  TransferStatus? _activeTransfer;

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
    await _webDropServer.startServer();
    _discoveryService.scanSubnet();

    _transferService.statusStream.listen((status) {
      setState(() {
        _activeTransfer = status;
      });
    });
  }

  @override
  void dispose() {
    _discoveryService.dispose();
    _transferService.dispose();
    _webDropServer.stopServer();
    super.dispose();
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
        builder: (_) => KdeConnectView(deviceName: deviceName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F19),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.bolt_rounded, color: Color(0xFF38BDF8), size: 28),
            SizedBox(width: 8),
            Text(
              'ShanuSend Mobile',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.mouse_rounded, color: Color(0xFF38BDF8)),
            tooltip: 'Mobile Remote Touchpad',
            onPressed: () => _openRemoteController(),
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
      body: Padding(
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
                              : '${_selectedFiles.length} file(s) ready',
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
                  'Nearby Devices',
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
                            'Scanning local network...',
                            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Make sure target devices are on the same Wi-Fi',
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
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161E2E),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFF283548)),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: const Color(0xFF38BDF8).withValues(alpha: 0.15),
                            child: Icon(
                              _getDeviceIcon(device.deviceType),
                              color: const Color(0xFF38BDF8),
                            ),
                          ),
                          title: Text(
                            device.alias,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
