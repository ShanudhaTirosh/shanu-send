import 'package:flutter/material.dart';

class SettingsTab extends StatefulWidget {
  final String deviceAlias;
  final ValueChanged<String> onAliasChanged;
  final VoidCallback onOpenWebDrop;

  const SettingsTab({
    super.key,
    required this.deviceAlias,
    required this.onAliasChanged,
    required this.onOpenWebDrop,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  late TextEditingController _aliasController;

  @override
  void initState() {
    super.initState();
    _aliasController = TextEditingController(text: widget.deviceAlias);
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
            'Settings',
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

          // Network & Port Config Card
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.numbers_rounded),
                  title: const Text('Default Port', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('53317 (Standard LocalSend Port)'),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.radar_rounded),
                  title: const Text('Multicast Address', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('224.0.0.167'),
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

          const SizedBox(height: 16),

          // Storage Directory Card
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder_special_rounded),
              title: const Text('Downloads Folder', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: const Text('Documents/ShanuSendDownloads'),
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
                      'ShanuSend v2.1',
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
