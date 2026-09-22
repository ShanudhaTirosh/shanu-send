import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../models/file_dto.dart';
import '../../widgets/speed_badge.dart';

class ReceiveTab extends StatelessWidget {
  final String? localIp;
  final String deviceAlias;
  final bool autoAccept;
  final ValueChanged<bool> onAutoAcceptChanged;
  final VoidCallback onOpenWebDrop;
  final TransferStatus? activeTransfer;

  const ReceiveTab({
    super.key,
    required this.localIp,
    required this.deviceAlias,
    required this.autoAccept,
    required this.onAutoAcceptChanged,
    required this.onOpenWebDrop,
    this.activeTransfer,
  });

  String _getPlatformName() {
    if (kIsWeb) return 'Web Browser';
    if (Platform.isWindows) return 'Windows PC';
    if (Platform.isMacOS) return 'macOS Workstation';
    if (Platform.isLinux) return 'Linux Workstation';
    if (Platform.isAndroid) return 'Android Phone';
    if (Platform.isIOS) return 'iPhone';
    return 'Local Device';
  }

  IconData _getPlatformIcon() {
    if (kIsWeb) return Icons.language_rounded;
    if (Platform.isAndroid || Platform.isIOS) return Icons.smartphone_rounded;
    return Icons.laptop_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 12),

          // Central Device Avatar & Alias Card
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 36.0, horizontal: 24.0),
              child: Column(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary.withValues(alpha: 0.12),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(alpha: 0.3),
                            width: 2,
                          ),
                        ),
                      ),
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary,
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(alpha: 0.35),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          _getPlatformIcon(),
                          size: 42,
                          color: isDark ? const Color(0xFF07090E) : Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    deviceAlias,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_getPlatformName()} • ${localIp ?? "Detecting IP..."}',
                        style: TextStyle(
                          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Quick Controls & Status Bar
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Quick Auto-Accept',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          'Automatically receive files without prompting',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: autoAccept,
                    activeColor: theme.colorScheme.primary,
                    onChanged: onAutoAcceptChanged,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // WebDrop Portal Button Card
          InkWell(
            onTap: onOpenWebDrop,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.15),
                    const Color(0xFF38BDF8).withValues(alpha: 0.15),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.qr_code_2_rounded,
                      color: Color(0xFF07090E),
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'AirDrop & WebDrop Portal',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Open in Safari / Chrome for instant transfer',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                ],
              ),
            ),
          ),

          if (activeTransfer != null) ...[
            const SizedBox(height: 24),
            SpeedBadge(status: activeTransfer!),
          ],
        ],
      ),
    );
  }
}
