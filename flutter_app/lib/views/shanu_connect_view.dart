import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/device_dto.dart';
import '../services/device_identity_service.dart';
import '../services/discovery_service.dart';
import '../services/shanu_connect_service.dart';
import '../services/trusted_device_store.dart';

class ShanuConnectView extends StatefulWidget {
  final String deviceName;
  final String? targetIp;
  final List<DeviceDto> devices;

  const ShanuConnectView({
    super.key,
    this.deviceName = 'Desktop PC',
    this.targetIp,
    this.devices = const [],
  });

  @override
  State<ShanuConnectView> createState() => _ShanuConnectViewState();
}

typedef KdeConnectView = ShanuConnectView;

class _ShanuConnectViewState extends State<ShanuConnectView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ShanuConnectService _shanuService = ShanuConnectService();
  final DiscoveryService _discoveryService = DiscoveryService();
  final TrustedDeviceStore _trustStore = TrustedDeviceStore();
  StreamSubscription<Map<String, dynamic>>? _packetSubscription;

  String? _myDeviceId;
  String? _pendingSasCode;
  String? _pairedPeerId;

  DeviceDto? _selectedDevice;
  bool _isPlaying = true;
  bool _isLocked = false;
  bool _isPaired = false;
  bool _isPairingRequested = false;
  String? _clipboardFeedback;
  double _mprisVolume = 75.0;
  double _systemVolume = 80.0;
  final TextEditingController _commandController = TextEditingController();
  final TextEditingController _clipboardController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _notificationReplyController = TextEditingController();
  final TextEditingController _quickSmsController = TextEditingController();

  String? get _activeTargetIp => _selectedDevice?.ip ?? widget.targetIp;
  String get _activeDeviceName => _selectedDevice?.alias ?? widget.deviceName;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _startDiscovery();

    if (widget.devices.isNotEmpty) {
      _selectedDevice = widget.devices.first;
    }
    _checkPairingStatus();
  }

  Future<void> _checkPairingStatus() async {
    final trustedMap = await _trustStore.listTrusted();
    if (trustedMap.isEmpty) {
      if (mounted) {
        setState(() {
          _isPaired = false;
          _pairedPeerId = null;
        });
      }
      return;
    }

    String? foundId;
    if (_selectedDevice != null) {
      for (var entry in trustedMap.entries) {
        if (entry.key == _selectedDevice!.fingerprint ||
            entry.key == _selectedDevice!.alias ||
            entry.key == _selectedDevice!.ip) {
          foundId = entry.key;
          break;
        }
      }
    }
    foundId ??= trustedMap.keys.first;

    if (mounted) {
      setState(() {
        _isPaired = true;
        _pairedPeerId = foundId;
      });
    }
  }

  Future<void> _startDiscovery() async {
    _myDeviceId = await DeviceIdentityService().getOrCreateDeviceId();
    await _shanuService.startDiscovery('Mobile Remote Controller', _myDeviceId!);
    _packetSubscription = _shanuService.packetStream.listen((packet) {
      if (packet['type'] == 'shanuconnect.pair') {
        final body = packet['body'] as Map<String, dynamic>? ?? {};
        final senderIp = packet['_senderIp'] as String?;
        _handlePairPacket(body, senderIp);
      }
    });
    await _checkPairingStatus();
  }

  @override
  void dispose() {
    _packetSubscription?.cancel();
    _shanuService.stop();
    _tabController.dispose();
    _commandController.dispose();
    _clipboardController.dispose();
    _pinController.dispose();
    _notificationReplyController.dispose();
    _quickSmsController.dispose();
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

  void _requestPairing([DeviceDto? dev]) {
    if (_myDeviceId == null) {
      _showToast('Still starting up — try again in a moment');
      return;
    }
    final targetDev = dev ?? _selectedDevice;
    final ip = targetDev?.ip ?? widget.targetIp;
    final code = (100000 + Random.secure().nextInt(900000)).toString();
    _pendingSasCode = code;

    _shanuService.sendPairing(pair: true, deviceId: _myDeviceId!, sasCode: code, targetIp: ip);
    setState(() => _isPairingRequested = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).cardTheme.color,
        title: Text('Pairing: ${targetDev?.alias ?? _activeDeviceName}', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "This code was sent to the target device. Only approve there if it matches — don't type a code in, compare it:",
              style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.7), fontSize: 13),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                code,
                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 32, letterSpacing: 8, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Text('Waiting for a response…', style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withValues(alpha: 0.4), fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _pendingSasCode = null;
              setState(() => _isPairingRequested = false);
              Navigator.pop(ctx);
            },
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Mirrors DesktopPhoneLinkView._handlePairPacket — see that file for the
  /// full protocol explanation. This side only ever *initiates* pairing
  /// today (the UI doesn't yet surface an incoming request banner), but it
  /// still needs to accept the ack so `_requestPairing` doesn't lie about
  /// being paired the instant any packet arrives.
  void _handlePairPacket(Map<String, dynamic> body, String? senderIp) {
    final peerId = body['deviceId'] as String?;
    final sasCode = body['sasCode'] as String?;
    final pair = body['pair'] as bool? ?? false;
    final ack = body['ack'] as bool? ?? false;
    if (peerId == null || peerId == _myDeviceId || !ack) return;
    if (_pendingSasCode == null || sasCode != _pendingSasCode) return;

    _pendingSasCode = null;
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);

    if (pair) {
      _trustStore.trust(peerId, alias: _selectedDevice?.alias);
      if (mounted) {
        setState(() {
          _isPaired = true;
          _isPairingRequested = false;
          _pairedPeerId = peerId;
        });
        _showToast('Device $_activeDeviceName Paired & Authenticated Successfully!');
      }
    } else if (mounted) {
      setState(() => _isPairingRequested = false);
      _showToast('Pairing was declined on the target device.');
    }
  }

  void _showPairingHelpDialog() {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: theme.cardTheme.color,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.help_outline_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('Device Hub & Pairing Guide', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Step 1: Discover & Select Device', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              const Text('Use the top Device Hub selector to pick any available device on your local Wi-Fi/LAN network.', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              Text('Step 2: Initiate SAS Pairing', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              const Text('Tap the "+ Pair Device" button to trigger the 6-digit Short Authentication String (SAS) prompt.', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              Text('Step 3: Enter 6-Digit PIN', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              const Text('Check the target device for the 6-digit Security PIN code shown on screen or in system notifications.', style: TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
              Text('Step 4: Control & Switch Devices', style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 4),
              const Text('Once approved, remote touchpad, media control, presenter clicker, and commands are active! You can switch target devices at any time.', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got It!'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  _activeDeviceName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _isPaired ? const Color(0xFF00D285).withValues(alpha: 0.2) : Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _isPaired ? 'CONNECTED' : (_isPairingRequested ? 'PAIRING...' : 'UNPAIRED'),
                    style: TextStyle(
                      color: _isPaired ? const Color(0xFF00D285) : (_isPairingRequested ? theme.colorScheme.primary : Colors.amber),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              _isPaired ? 'ShanuConnect Authenticated Session' : (_isPairingRequested ? 'PIN confirmation pending...' : 'Select or pair target device'),
              style: TextStyle(color: theme.colorScheme.primary, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.help_outline_rounded, color: theme.colorScheme.primary),
            tooltip: 'Pairing Instructions',
            onPressed: _showPairingHelpDialog,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: ElevatedButton.icon(
              onPressed: () => _requestPairing(),
              icon: Icon(_isPaired ? Icons.verified_rounded : Icons.link_rounded, size: 16),
              label: Text(_isPaired ? 'Paired' : 'Connect & Pair'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isPaired ? const Color(0xFF00D285) : theme.colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: theme.colorScheme.primary,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
          tabs: const [
            Tab(icon: Icon(Icons.touch_app_rounded), text: 'Touchpad'),
            Tab(icon: Icon(Icons.slideshow_rounded), text: 'Presenter'),
            Tab(icon: Icon(Icons.play_circle_fill_rounded), text: 'Media'),
            Tab(icon: Icon(Icons.assignment_rounded), text: 'Clipboard'),
            Tab(icon: Icon(Icons.volume_up_rounded), text: 'Volume'),
            Tab(icon: Icon(Icons.ring_volume_rounded), text: 'Find Phone'),
            Tab(icon: Icon(Icons.terminal_rounded), text: 'Commands'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Integrated Device Hub Bar & Switcher
          StreamBuilder<List<DeviceDto>>(
            stream: _discoveryService.deviceStream,
            initialData: _discoveryService.devices,
            builder: (context, snapshot) {
              final devices = snapshot.data ?? widget.devices;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.cardTheme.color,
                  border: Border(bottom: BorderSide(color: theme.colorScheme.surfaceContainerHighest)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.devices_rounded, color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 8),
                    const Text('Target Device:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<DeviceDto>(
                          value: _selectedDevice,
                          dropdownColor: theme.cardTheme.color,
                          isExpanded: true,
                          icon: Icon(Icons.arrow_drop_down_rounded, color: theme.colorScheme.primary),
                          hint: Text(_activeDeviceName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          items: devices.map((d) {
                            return DropdownMenuItem<DeviceDto>(
                              value: d,
                              child: Text(
                                '${d.alias} (${d.ip})',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            );
                          }).toList(),
                          onChanged: (dev) {
                            if (dev != null) {
                              setState(() {
                                _selectedDevice = dev;
                                _isPaired = false;
                                _pairedPeerId = null;
                              });
                              _showToast('Switched control target to ${dev.alias}');
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.refresh_rounded, color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5), size: 20),
                      tooltip: 'Scan Discovered Devices',
                      onPressed: () => _discoveryService.scanSubnet(),
                    ),
                  ],
                ),
              );
            },
          ),

          // Main Control Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 1. Touchpad & Gestures
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            _shanuService.sendMousepad(details.delta.dx, details.delta.dy, targetIp: _activeTargetIp);
                          },
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _shanuService.sendMousepad(0, 0, click: 'left', targetIp: _activeTargetIp);
                          },
                          onDoubleTap: () {
                            HapticFeedback.mediumImpact();
                            _shanuService.sendMousepad(0, 0, click: 'double', targetIp: _activeTargetIp);
                          },
                          child: Card(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                            ),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.touch_app_rounded, size: 64, color: theme.colorScheme.primary),
                                  const SizedBox(height: 12),
                                  Text('Trackpad Surface for $_activeDeviceName', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text('Drag to move Desktop cursor • Tap to Click', style: TextStyle(color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6), fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                _shanuService.sendMousepad(0, 0, click: 'left', targetIp: _activeTargetIp);
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Left Click'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                _shanuService.sendMousepad(0, 0, click: 'right', targetIp: _activeTargetIp);
                              },
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Right Click'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 2. Presenter
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.slideshow_rounded, size: 64, color: theme.colorScheme.primary),
                      const SizedBox(height: 16),
                      Text('Presenter Mode for $_activeDeviceName', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      const Text('Use volume buttons or gestures to control slides.', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),

                // 3. Media Remote
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: const Color(0xFF38BDF8).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                        ),
                        child: const Icon(Icons.music_note_rounded, size: 64, color: Color(0xFF38BDF8)),
                      ),
                      const SizedBox(height: 16),
                      Text('Media Player on $_activeDeviceName', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      const Text('Connected Host MPRIS Stream', style: TextStyle(color: Colors.white54, fontSize: 14)),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            iconSize: 40,
                            icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                            onPressed: () {
                              _shanuService.sendMprisCommand('previous', targetIp: _activeTargetIp);
                            },
                          ),
                          IconButton(
                            iconSize: 64,
                            icon: Icon(
                              _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                              color: const Color(0xFF38BDF8),
                            ),
                            onPressed: () {
                              setState(() => _isPlaying = !_isPlaying);
                              _shanuService.sendMprisCommand(_isPlaying ? 'play' : 'pause', targetIp: _activeTargetIp);
                            },
                          ),
                          IconButton(
                            iconSize: 40,
                            icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                            onPressed: () {
                              _shanuService.sendMprisCommand('next', targetIp: _activeTargetIp);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          const Icon(Icons.volume_down_rounded, color: Colors.white54),
                          Expanded(
                            child: Slider(
                              value: _mprisVolume,
                              min: 0,
                              max: 100,
                              activeColor: const Color(0xFF38BDF8),
                              onChanged: (v) {
                                setState(() => _mprisVolume = v);
                                _shanuService.sendMprisCommand('volume', volume: v, targetIp: _activeTargetIp);
                              },
                            ),
                          ),
                          const Icon(Icons.volume_up_rounded, color: Colors.white54),
                        ],
                      ),
                    ],
                  ),
                ),

                // 3. Remote Commands & Workstation Control
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _commandController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Execute remote command on $_activeDeviceName...',
                                hintStyle: const TextStyle(color: Colors.white38),
                                filled: true,
                                fillColor: const Color(0xFF161E2E),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.send_rounded, color: Color(0xFF38BDF8)),
                            onPressed: () {
                              if (_commandController.text.isNotEmpty) {
                                _shanuService.sendRunCommand(_commandController.text, _activeTargetIp);
                                _showToast('Command Sent: ${_commandController.text}');
                                _commandController.clear();
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text('$_activeDeviceName System Volume', style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                      Slider(
                        value: _systemVolume,
                        min: 0,
                        max: 100,
                        activeColor: const Color(0xFF38BDF8),
                        onChanged: (v) {
                          setState(() => _systemVolume = v);
                          _shanuService.sendSystemVolume(v, _activeTargetIp);
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView(
                          children: [
                            ListTile(
                              tileColor: const Color(0xFF161E2E),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              title: Text(_isLocked ? 'Unlock Workstation' : 'Lock Workstation', style: const TextStyle(color: Colors.white)),
                              trailing: Icon(Icons.lock_rounded, color: _isLocked ? Colors.redAccent : const Color(0xFF38BDF8)),
                              onTap: () {
                                setState(() => _isLocked = !_isLocked);
                                _shanuService.sendLockDevice(lock: _isLocked, targetIp: _activeTargetIp);
                                _showToast(_isLocked ? 'Workstation Lock Triggered' : 'Workstation Unlock Triggered');
                              },
                            ),
                            const SizedBox(height: 8),
                            ListTile(
                              tileColor: const Color(0xFF161E2E),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              title: const Text('Send Ping Signal', style: TextStyle(color: Colors.white)),
                              trailing: const Icon(Icons.notifications_active_rounded, color: Color(0xFF38BDF8)),
                              onTap: () {
                                _shanuService.sendRunCommand('ping', _activeTargetIp);
                                _showToast('Ping Signal Broadcast to $_activeDeviceName');
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // 4. Clipboard Sync
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Shared Clipboard Sync', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Type or paste content to sync with $_activeDeviceName clipboard.', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _clipboardController,
                        maxLines: 6,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Enter text to send to host clipboard...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF161E2E),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (_clipboardController.text.isNotEmpty) {
                              _shanuService.sendClipboardText(_clipboardController.text, _activeTargetIp);
                              setState(() => _clipboardFeedback = 'Clipboard content synced to $_activeDeviceName!');
                              _showToast('Clipboard synced!');
                            }
                          },
                          icon: const Icon(Icons.assignment_turned_in_rounded),
                          label: Text('Sync to $_activeDeviceName Clipboard'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF38BDF8),
                            foregroundColor: const Color(0xFF090B11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      if (_clipboardFeedback != null) ...[
                        const SizedBox(height: 12),
                        Text(_clipboardFeedback!, style: const TextStyle(color: Color(0xFF34D399), fontSize: 13)),
                      ],
                    ],
                  ),
                ),

                // 5. Presenter Clicker
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.slideshow_rounded, size: 64, color: Color(0xFF6366F1)),
                      const SizedBox(height: 12),
                      const Text('Presentation Remote Clicker', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Target: $_activeDeviceName', style: const TextStyle(color: Colors.white54, fontSize: 13)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () {
                          _shanuService.sendPresenterSlide(next: false, targetIp: _activeTargetIp);
                        },
                        icon: const Icon(Icons.arrow_back_rounded),
                        label: const Text('Previous Slide'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          minimumSize: const Size.fromHeight(60),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: () {
                          _shanuService.sendPresenterSlide(next: true, targetIp: _activeTargetIp);
                        },
                        icon: const Icon(Icons.arrow_forward_rounded),
                        label: const Text('Next Slide'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          minimumSize: const Size.fromHeight(60),
                        ),
                      ),
                    ],
                  ),
                ),

                // 6. Mirrored Notifications & Inline Replies
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Mirrored App Notifications', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('Reply directly to mirrored WhatsApp, Telegram, or SMS alerts.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF161E2E),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.notifications_paused_rounded, size: 48, color: Colors.white24),
                                SizedBox(height: 12),
                                Text('No incoming notifications', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                                SizedBox(height: 4),
                                Text('Active app alerts from target device will stream here automatically.', style: TextStyle(color: Colors.white38, fontSize: 12), textAlign: TextAlign.center),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 7. Telephony Calls Manager
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Telephony & Call Control', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      const Text('Manage incoming/outgoing call signals and quick SMS responses.', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF161E2E),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.phone_missed_rounded, size: 48, color: Colors.white24),
                            const SizedBox(height: 12),
                            const Text('No active call in progress', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            const Text('Incoming call alerts pop up with live answer/reject actions.', style: TextStyle(color: Colors.white38, fontSize: 12), textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _quickSmsController,
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Quick SMS reply message...',
                                hintStyle: const TextStyle(color: Colors.white38),
                                filled: true,
                                fillColor: const Color(0xFF090B11),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      if (_quickSmsController.text.isNotEmpty) {
                                        _shanuService.sendTelephonyCallAction('reject_sms', _quickSmsController.text, _activeTargetIp);
                                        _showToast('Quick SMS reply sent');
                                        _quickSmsController.clear();
                                      }
                                    },
                                    icon: const Icon(Icons.send_rounded, size: 16),
                                    label: const Text('Reject with SMS'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF38BDF8),
                                      foregroundColor: const Color(0xFF090B11),
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
