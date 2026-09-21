import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class ScrcpyGuiView extends StatefulWidget {
  const ScrcpyGuiView({super.key});

  @override
  State<ScrcpyGuiView> createState() => _ScrcpyGuiViewState();
}

class _ScrcpyGuiViewState extends State<ScrcpyGuiView> {
  Process? _scrcpyProcess;

  String _selectedResolution = '1080p';
  String _selectedFps = '60';
  String _selectedBitrate = '8M';
  String _selectedCodec = 'h264';
  
  bool _stayAwake = true;
  bool _turnScreenOff = false;
  bool _alwaysOnTop = false;
  bool _borderless = false;
  bool _recordSession = false;

  final List<String> _devices = ['Android Device (USB / Wireless ADB)'];
  String? _selectedDevice;

  @override
  void initState() {
    super.initState();
    _selectedDevice = _devices.first;
  }

  @override
  void dispose() {
    _scrcpyProcess?.kill();
    super.dispose();
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFF161E2E),
      ),
    );
  }

  Future<void> _startScrcpy() async {
    if (_scrcpyProcess != null) {
      _showToast('Scrcpy session is already running');
      return;
    }

    final args = <String>[];
    
    // Resolution
    if (_selectedResolution == '720p') {
      args.addAll(['--max-size', '1280']);
    } else if (_selectedResolution == '1080p') {
      args.addAll(['--max-size', '1920']);
    }

    // FPS & Bitrate
    args.addAll(['--max-fps', _selectedFps]);
    args.addAll(['--video-bit-rate', _selectedBitrate]);
    args.addAll(['--video-codec', _selectedCodec]);

    // Flags
    if (_stayAwake) args.add('--stay-awake');
    if (_turnScreenOff) args.add('--turn-screen-off');
    if (_alwaysOnTop) args.add('--always-on-top');
    if (_borderless) args.add('--window-borderless');

    if (_recordSession) {
      final docs = await getApplicationDocumentsDirectory();
      final recDir = Directory('${docs.path}/ShanuSendDownloads/Recordings');
      await recDir.create(recursive: true);
      final filename = 'scrcpy_rec_${DateTime.now().millisecondsSinceEpoch}.mp4';
      args.addAll(['--record', '${recDir.path}/$filename']);
    }

    try {
      _scrcpyProcess = await Process.start('scrcpy', args);
      _showToast('Scrcpy Screen Mirroring started!');
      _scrcpyProcess?.exitCode.then((code) {
        setState(() => _scrcpyProcess = null);
        debugPrint('Scrcpy exited with code $code');
      });
    } catch (e) {
      _showToast('Failed to launch scrcpy binary. Ensure scrcpy is installed on system PATH.');
      debugPrint('Scrcpy launch error: $e');
    }
  }

  void _stopScrcpy() {
    _scrcpyProcess?.kill();
    setState(() => _scrcpyProcess = null);
    _showToast('Scrcpy session stopped');
  }

  @override
  Widget build(BuildContext context) {
    final isRunning = _scrcpyProcess != null;

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: ListView(
        children: [
          Row(
            children: const [
              Icon(Icons.aspect_ratio_rounded, color: Color(0xFF38BDF8), size: 28),
              SizedBox(width: 10),
              Text(
                'Scrcpy Pro Screen Mirroring & Control Suite',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'High-performance, low-latency Android screen mirroring over USB & Wireless ADB for Windows Desktop.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          const SizedBox(height: 20),

          // Control & Launch Panel Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF161E2E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF283548)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ADB Target Device:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF090B11),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF283548)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedDevice,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF161E2E),
                      items: _devices.map((d) {
                        return DropdownMenuItem<String>(
                          value: d,
                          child: Text(d, style: const TextStyle(color: Colors.white)),
                        );
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedDevice = val),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                const Text('Video & Quality Settings:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _buildSettingDropdown(
                        label: 'Resolution',
                        value: _selectedResolution,
                        items: ['720p', '1080p', 'Original (1440p)'],
                        onChanged: (v) => setState(() => _selectedResolution = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSettingDropdown(
                        label: 'Max FPS',
                        value: _selectedFps,
                        items: ['30', '60'],
                        onChanged: (v) => setState(() => _selectedFps = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSettingDropdown(
                        label: 'Bitrate',
                        value: _selectedBitrate,
                        items: ['4M', '8M', '16M'],
                        onChanged: (v) => setState(() => _selectedBitrate = v!),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSettingDropdown(
                        label: 'Video Codec',
                        value: _selectedCodec,
                        items: ['h264', 'h265', 'av1'],
                        onChanged: (v) => setState(() => _selectedCodec = v!),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                const Text('Window & Display Toggles:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 12),

                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    _buildToggleChip('Stay Awake', _stayAwake, (v) => setState(() => _stayAwake = v)),
                    _buildToggleChip('Turn Phone Screen Off', _turnScreenOff, (v) => setState(() => _turnScreenOff = v)),
                    _buildToggleChip('Always on Top', _alwaysOnTop, (v) => setState(() => _alwaysOnTop = v)),
                    _buildToggleChip('Borderless Window', _borderless, (v) => setState(() => _borderless = v)),
                    _buildToggleChip('Record Session (MP4)', _recordSession, (v) => setState(() => _recordSession = v)),
                  ],
                ),

                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isRunning ? _stopScrcpy : _startScrcpy,
                        icon: Icon(isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded),
                        label: Text(isRunning ? 'Stop Mirroring' : 'Start Mirroring Session'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isRunning ? const Color(0xFFEF4444) : const Color(0xFF38BDF8),
                          foregroundColor: isRunning ? Colors.white : const Color(0xFF090B11),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF090B11),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF283548)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF161E2E),
              items: items.map((i) {
                return DropdownMenuItem<String>(
                  value: i,
                  child: Text(i, style: const TextStyle(color: Colors.white, fontSize: 13)),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildToggleChip(String label, bool value, ValueChanged<bool> onChanged) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
      selectedColor: const Color(0xFF38BDF8).withValues(alpha: 0.2),
      checkmarkColor: const Color(0xFF38BDF8),
      backgroundColor: const Color(0xFF090B11),
      labelStyle: TextStyle(
        color: value ? const Color(0xFF38BDF8) : Colors.white70,
        fontSize: 13,
        fontWeight: value ? FontWeight.bold : FontWeight.normal,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: value ? const Color(0xFF38BDF8) : const Color(0xFF283548)),
      ),
    );
  }
}
