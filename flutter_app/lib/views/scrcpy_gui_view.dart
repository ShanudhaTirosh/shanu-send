import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../services/adb_device_service.dart';
import '../services/tool_bootstrap_service.dart';

class ScrcpyGuiView extends StatefulWidget {
  const ScrcpyGuiView({super.key});

  @override
  State<ScrcpyGuiView> createState() => _ScrcpyGuiViewState();
}

class _ScrcpyGuiViewState extends State<ScrcpyGuiView> {
  final ToolBootstrapService _bootstrap = ToolBootstrapService();

  Process? _scrcpyProcess;
  final List<String> _sessionLog = [];

  String _selectedResolution = '1080p';
  String _selectedFps = '60';
  String _selectedBitrate = '8M';
  String _selectedCodec = 'h264';

  bool _stayAwake = true;
  bool _turnScreenOff = false;
  bool _alwaysOnTop = false;
  bool _borderless = false;
  bool _recordSession = false;

  // Tool state
  String? _adbPath;
  String? _scrcpyPath;
  bool _adbBusy = false;
  bool _scrcpyBusy = false;
  double? _downloadProgress; // null = not downloading
  String? _scrcpyManualInstallMessage;

  // Devices
  StreamSubscription<List<AdbDevice>>? _deviceSub;
  List<AdbDevice> _devices = const [];
  String? _selectedSerial;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final resolved = await _bootstrap.resolve();
    if (!mounted) return;
    setState(() {
      _adbPath = resolved.adbPath;
      _scrcpyPath = resolved.scrcpyPath;
    });
    if (_adbPath != null) _startWatchingDevices();
  }

  void _startWatchingDevices() {
    _deviceSub?.cancel();
    _deviceSub = AdbDeviceService(_adbPath!).watch().listen((devices) {
      if (!mounted) return;
      setState(() {
        _devices = devices;
        // Drop selection if the device disappeared; otherwise keep it so a
        // brief disconnect/reconnect doesn't reset the user's choice.
        if (_selectedSerial != null &&
            !devices.any((d) => d.serial == _selectedSerial)) {
          _selectedSerial = devices.isNotEmpty ? devices.first.serial : null;
        } else if (_selectedSerial == null && devices.isNotEmpty) {
          _selectedSerial = devices.first.serial;
        }
      });
    });
  }

  @override
  void dispose() {
    _deviceSub?.cancel();
    _scrcpyProcess?.kill();
    super.dispose();
  }

  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 3),
        backgroundColor: const Color(0xFF161E2E),
      ),
    );
  }

  Future<bool> _confirmLicense(String toolName, String detail) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161E2E),
        title: Text('Download $toolName?', style: const TextStyle(color: Colors.white)),
        content: Text(detail, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8)),
            child: const Text('Accept & Download'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _setupAdb() async {
    setState(() {
      _adbBusy = true;
      _downloadProgress = 0;
    });
    try {
      final path = await _bootstrap.ensureAdb(
        onLicenseConsent: () => _confirmLicense(
          'Android Platform-Tools (adb)',
          'Downloaded once from Google\'s official repository under the '
          'Android SDK license, then cached locally for future sessions.',
        ),
        onProgress: (p) => setState(() => _downloadProgress = p),
      );
      if (!mounted) return;
      setState(() => _adbPath = path);
      _startWatchingDevices();
      _showToast('adb is ready');
    } catch (e) {
      _showToast('Could not set up adb: $e');
    } finally {
      if (mounted) setState(() { _adbBusy = false; _downloadProgress = null; });
    }
  }

  Future<void> _setupScrcpy() async {
    setState(() {
      _scrcpyBusy = true;
      _downloadProgress = 0;
      _scrcpyManualInstallMessage = null;
    });
    try {
      final path = await _bootstrap.ensureScrcpy(
        onLicenseConsent: () => _confirmLicense(
          'scrcpy',
          'Downloaded once from the official Genymobile GitHub releases '
          '(Apache-2.0), then cached locally for future sessions.',
        ),
        onProgress: (p) => setState(() => _downloadProgress = p),
      );
      if (!mounted) return;
      setState(() => _scrcpyPath = path);
      _showToast('scrcpy is ready');
    } on ToolBootstrapNeedsManualInstall catch (e) {
      setState(() => _scrcpyManualInstallMessage = e.instructions);
    } catch (e) {
      _showToast('Could not set up scrcpy: $e');
    } finally {
      if (mounted) setState(() { _scrcpyBusy = false; _downloadProgress = null; });
    }
  }

  Future<void> _pairWireless() async {
    if (_adbPath == null) return;
    final hostController = TextEditingController();
    final codeController = TextEditingController();
    final connectController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161E2E),
        title: const Text('Pair over Wi-Fi', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'On the phone: Settings > Developer options > Wireless debugging '
              '> Pair device with pairing code. Enter the IP:port and code shown there.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: hostController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: 'Pairing IP:Port (e.g. 192.168.1.23:41235)'),
            ),
            TextField(
              controller: codeController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(labelText: '6-digit pairing code'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: connectController,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Connect IP:Port (from the main Wireless debugging screen)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final service = AdbDeviceService(_adbPath!);
              final pairResult = await service.pairWireless(
                hostController.text.trim(),
                codeController.text.trim(),
              );
              if (!pairResult.success) {
                _showToast('Pairing failed: ${pairResult.message}');
                return;
              }
              if (connectController.text.trim().isNotEmpty) {
                final connectResult =
                    await service.connectWireless(connectController.text.trim());
                _showToast(connectResult.success
                    ? 'Paired and connected'
                    : 'Paired, but connect failed: ${connectResult.message}');
              } else {
                _showToast('Paired. Now enter the Connect IP:Port to finish.');
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8)),
            child: const Text('Pair'),
          ),
        ],
      ),
    );
  }

  Future<void> _startScrcpy() async {
    if (_scrcpyProcess != null) {
      _showToast('Scrcpy session is already running');
      return;
    }
    if (_scrcpyPath == null) {
      _showToast('Set up scrcpy first');
      return;
    }
    if (_selectedSerial == null) {
      _showToast('No device selected — connect a device or pair over Wi-Fi first');
      return;
    }
    final device = _devices.firstWhere((d) => d.serial == _selectedSerial);
    if (device.state == 'unauthorized') {
      _showToast('Device is unauthorized — tap "Allow USB debugging" on the phone');
      return;
    }

    final args = <String>['-s', _selectedSerial!];

    if (_selectedResolution == '720p') {
      args.addAll(['--max-size', '1280']);
    } else if (_selectedResolution == '1080p') {
      args.addAll(['--max-size', '1920']);
    }

    args.addAll(['--max-fps', _selectedFps]);
    args.addAll(['--video-bit-rate', _selectedBitrate]);
    args.addAll(['--video-codec', _selectedCodec]);

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

    setState(() => _sessionLog.clear());

    try {
      // Make adb discoverable to the spawned scrcpy process even when it's
      // our bundled copy rather than a system install.
      final env = Map<String, String>.from(Platform.environment);
      if (_adbPath != null) env['ADB'] = _adbPath!;

      _scrcpyProcess = await Process.start(_scrcpyPath!, args, environment: env);
      setState(() {});
      _showToast('Scrcpy Screen Mirroring started!');

      _scrcpyProcess!.stderr
          .transform(const SystemEncoding().decoder)
          .listen((line) {
        if (!mounted) return;
        setState(() => _sessionLog.add(line.trimRight()));
      });
      _scrcpyProcess!.stdout
          .transform(const SystemEncoding().decoder)
          .listen((line) {
        if (!mounted) return;
        setState(() => _sessionLog.add(line.trimRight()));
      });

      _scrcpyProcess!.exitCode.then((code) {
        if (!mounted) return;
        setState(() {
          _scrcpyProcess = null;
          if (code != 0) _sessionLog.add('[scrcpy exited with code $code]');
        });
        if (code != 0) {
          _showToast('scrcpy exited with an error — see the session log below');
        }
      });
    } catch (e) {
      _showToast('Failed to launch scrcpy: $e');
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
    final toolsReady = _adbPath != null && _scrcpyPath != null;

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
            'High-performance, low-latency Android screen mirroring over USB & Wireless ADB.',
            style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
          ),
          const SizedBox(height: 20),

          if (!toolsReady) _buildToolSetupCard(),
          if (!toolsReady) const SizedBox(height: 16),

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
                Row(
                  children: [
                    const Expanded(
                      child: Text('ADB Target Device:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ),
                    TextButton.icon(
                      onPressed: _adbPath == null ? null : _pairWireless,
                      icon: const Icon(Icons.wifi_rounded, size: 16, color: Color(0xFF38BDF8)),
                      label: const Text('Pair over Wi-Fi', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
                    ),
                  ],
                ),
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
                      value: _selectedSerial,
                      isExpanded: true,
                      hint: Text(
                        _adbPath == null ? 'Set up adb first' : 'No devices detected',
                        style: const TextStyle(color: Colors.white38),
                      ),
                      dropdownColor: const Color(0xFF161E2E),
                      items: _devices.map((d) {
                        final unauthorized = d.state == 'unauthorized';
                        return DropdownMenuItem<String>(
                          value: d.serial,
                          child: Text(
                            unauthorized ? '${d.label}  (tap Allow on phone)' : d.label,
                            style: TextStyle(color: unauthorized ? Colors.orangeAccent : Colors.white),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) => setState(() => _selectedSerial = val),
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
                        onPressed: !toolsReady ? null : (isRunning ? _stopScrcpy : _startScrcpy),
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

                if (_sessionLog.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Session log:', style: TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 160),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF090B11),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF283548)),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        _sessionLog.join('\n'),
                        style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolSetupCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161E2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEAB308).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.download_rounded, color: Color(0xFFEAB308), size: 20),
              SizedBox(width: 8),
              Text('One-time setup required', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'adb and scrcpy are external tools this panel needs. They are not bundled with '
            'the app — set them up once and they\'re cached for every future session.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 12),
          if (_downloadProgress != null) ...[
            LinearProgressIndicator(
              value: _downloadProgress! > 0 ? _downloadProgress : null,
              backgroundColor: const Color(0xFF283548),
              color: const Color(0xFF38BDF8),
            ),
            const SizedBox(height: 12),
          ],
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (_adbPath == null)
                ElevatedButton.icon(
                  onPressed: _adbBusy ? null : _setupAdb,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: Text(_adbBusy ? 'Setting up adb…' : 'Set up adb'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8), foregroundColor: const Color(0xFF090B11)),
                )
              else
                const Chip(label: Text('adb ready'), avatar: Icon(Icons.check_circle, size: 16, color: Colors.green)),
              if (_scrcpyPath == null)
                ElevatedButton.icon(
                  onPressed: _scrcpyBusy ? null : _setupScrcpy,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: Text(_scrcpyBusy ? 'Setting up scrcpy…' : 'Set up scrcpy'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8), foregroundColor: const Color(0xFF090B11)),
                )
              else
                const Chip(label: Text('scrcpy ready'), avatar: Icon(Icons.check_circle, size: 16, color: Colors.green)),
            ],
          ),
          if (_scrcpyManualInstallMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF090B11),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _scrcpyManualInstallMessage!,
                style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () async {
                final resolved = await _bootstrap.resolve();
                if (!mounted) return;
                setState(() {
                  _adbPath = resolved.adbPath;
                  _scrcpyPath = resolved.scrcpyPath;
                });
                if (_scrcpyPath != null) _showToast('scrcpy found!');
              },
              child: const Text('I installed it — recheck', style: TextStyle(color: Color(0xFF38BDF8))),
            ),
          ],
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
