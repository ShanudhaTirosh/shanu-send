import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../../services/shell_integration_service.dart';

class SettingsTab extends StatefulWidget {
  final String deviceAlias;
  final ValueChanged<String> onAliasChanged;
  final bool autoSyncClipboard;
  final ValueChanged<bool> onAutoSyncClipboardChanged;
  final VoidCallback onOpenWebDrop;

  const SettingsTab({
    super.key,
    required this.deviceAlias,
    required this.onAliasChanged,
    required this.autoSyncClipboard,
    required this.onAutoSyncClipboardChanged,
    required this.onOpenWebDrop,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late TextEditingController _aliasController;
  bool _contextMenuRegistered = false;

  @override
  void initState() {
    super.initState();
    _aliasController = TextEditingController(text: widget.deviceAlias);
    _checkContextMenuStatus();
  }

  Future<void> _checkContextMenuStatus() async {
    if (ShellIntegrationService.isWindows) {
      final reg = await ShellIntegrationService.isContextMenuRegistered();
      if (mounted) setState(() => _contextMenuRegistered = reg);
    }
  }

  Future<void> _toggleContextMenu(bool enable) async {
    if (!ShellIntegrationService.isWindows) return;
    bool success;
    if (enable) {
      success = await ShellIntegrationService.registerContextMenu();
    } else {
      success = await ShellIntegrationService.unregisterContextMenu();
    }
    if (success) {
      setState(() => _contextMenuRegistered = enable);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enable
                  ? 'Added "Send with ShanuSend" to Windows Right-Click Menu!'
                  : 'Removed from Windows Right-Click Menu',
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _aliasController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Settings & OS Integration',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 20),

          // Device Identification Card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Device Name / Alias',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Name visible to nearby LocalSend & ShanuSend devices',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _aliasController,
                    decoration: InputDecoration(
                      hintText: 'Enter device name...',
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.check_rounded),
                        onPressed: () {
                          widget.onAliasChanged(_aliasController.text.trim());
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Device alias updated!')),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Day-to-Day Native Features Card
          Card(
            child: Column(
              children: [
                if (Platform.isWindows) ...[
                  SwitchListTile(
                    secondary: const Icon(Icons.mouse_rounded),
                    title: const Text('Windows Explorer Right-Click Menu', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    subtitle: const Text('Add "Send with ShanuSend" to right-click shell menu'),
                    value: _contextMenuRegistered,
                    onChanged: _toggleContextMenu,
                  ),
                  const Divider(height: 1, indent: 56),
                ],
                SwitchListTile(
                  secondary: const Icon(Icons.assignment_rounded),
                  title: const Text('Automatic Real-Time Clipboard Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Sync desktop & mobile clipboard automatically'),
                  value: widget.autoSyncClipboard,
                  onChanged: widget.onAutoSyncClipboardChanged,
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.screen_lock_portrait_rounded),
                  title: const Text('Minimize to System Tray on Close', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Keep server & connection running in background'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Active', style: TextStyle(color: theme.colorScheme.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Network & Port Config Card
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.numbers_rounded),
                  title: Text('Default Port', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text('53317 (Standard LocalSend Port)'),
                ),
                const Divider(height: 1, indent: 56),
                const ListTile(
                  leading: Icon(Icons.radar_rounded),
                  title: Text('Multicast Address', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text('224.0.0.167'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.language_rounded),
                  title: const Text('WebDrop Sharing Portal', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('Share files with mobile web browsers'),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: widget.onOpenWebDrop,
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // About Card
          Center(
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, color: theme.colorScheme.primary, size: 24),
                    const SizedBox(width: 6),
                    const Text(
                      'ShanuSend v2.1 Pro',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Fully compatible with LocalSend v2.1 open protocol',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
