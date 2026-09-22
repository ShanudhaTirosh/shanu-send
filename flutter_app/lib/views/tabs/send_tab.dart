import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/device_dto.dart';
import '../../models/file_dto.dart';
import '../../services/discovery_service.dart';
import '../../services/transfer_service.dart';

class SendTab extends StatefulWidget {
  final DiscoveryService discoveryService;
  final TransferService transferService;
  final DeviceDto? selectedDevice;
  final ValueChanged<DeviceDto> onDeviceSelected;
  final Function(String deviceName) onOpenRemoteController;

  const SendTab({
    super.key,
    required this.discoveryService,
    required this.transferService,
    required this.selectedDevice,
    required this.onDeviceSelected,
    required this.onOpenRemoteController,
  });

  @override
  State<SendTab> createState() => _SendTabState();
}

class _SendTabState extends State<SendTab> {
  List<FileDto> _selectedFiles = [];

  Future<void> _pickFiles([FileType type = FileType.any]) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: type,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() {
        _selectedFiles = result.files
            .where((f) => f.path != null)
            .map((f) => FileDto(
                  id: const Uuid().v4(),
                  fileName: f.name,
                  size: f.size,
                  fileType: type == FileType.image || type == FileType.video ? 'media' : 'file',
                  path: f.path,
                ))
            .toList();
      });
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedFiles.clear();
    });
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

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = (bytes.toString().length - 1) ~/ 3;
    if (i >= suffixes.length) i = suffixes.length - 1;
    double num = bytes / (1 << (i * 10));
    return '${num.toStringAsFixed(1)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Selection Category Picker Buttons
          Row(
            children: [
              Expanded(
                child: _buildCategoryBtn(
                  context,
                  icon: Icons.folder_rounded,
                  label: 'Files',
                  color: theme.colorScheme.primary,
                  onTap: () => _pickFiles(FileType.any),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildCategoryBtn(
                  context,
                  icon: Icons.perm_media_rounded,
                  label: 'Media',
                  color: const Color(0xFF6366F1),
                  onTap: () => _pickFiles(FileType.media),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildCategoryBtn(
                  context,
                  icon: Icons.description_rounded,
                  label: 'Documents',
                  color: const Color(0xFF10B981),
                  onTap: () => _pickFiles(FileType.any),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Selection Summary Queue Tray
          if (_selectedFiles.isNotEmpty)
            Card(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_selectedFiles.length} item(s) selected',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Total size: ${_formatSize(_selectedFiles.fold(0, (sum, f) => sum + f.size))}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Clear selection',
                      onPressed: _clearSelection,
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 20),

          // Discovered Nearby Devices Section Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Nearby Devices',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              StreamBuilder<List<DeviceDto>>(
                stream: widget.discoveryService.deviceStream,
                builder: (context, snapshot) {
                  final count = snapshot.data?.length ?? 0;
                  return Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        tooltip: 'Refresh LAN Scan',
                        onPressed: () => widget.discoveryService.scanSubnet(),
                      ),
                      Text(
                        '$count found',
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Discovered Devices List View
          Expanded(
            child: StreamBuilder<List<DeviceDto>>(
              stream: widget.discoveryService.deviceStream,
              initialData: widget.discoveryService.devices,
              builder: (context, snapshot) {
                final devices = snapshot.data ?? [];

                if (devices.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.radar_rounded,
                          size: 60,
                          color: theme.colorScheme.primary.withValues(alpha: 0.25),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Searching for nearby devices on LAN...',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Ensure ShanuSend or LocalSend is open on target device',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: devices.length,
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final isSelected = widget.selectedDevice?.ip == device.ip;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.surfaceContainerHighest,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        onTap: () => widget.onDeviceSelected(device),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                          child: Icon(
                            _getDeviceIcon(device.deviceType),
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              device.alias,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'LocalSend',
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          '${device.ip} • ${device.deviceModel}',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.mouse_rounded),
                              tooltip: 'Remote Control',
                              onPressed: () => widget.onOpenRemoteController(device.alias),
                            ),
                            const SizedBox(width: 4),
                            ElevatedButton(
                              onPressed: _selectedFiles.isEmpty
                                  ? null
                                  : () => widget.transferService.sendFiles(
                                        targetDevice: device,
                                        files: _selectedFiles,
                                      ),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                              child: const Text('Send'),
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

  Widget _buildCategoryBtn(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.surfaceContainerHighest),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
