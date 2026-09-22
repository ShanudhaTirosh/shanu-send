import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/device_dto.dart';
import '../services/device_identity_service.dart';
import '../services/native_input_service.dart';
import '../services/shanu_connect_service.dart';
import '../services/trusted_device_store.dart';

class DesktopPhoneLinkView extends StatefulWidget {
  final List<DeviceDto> devices;
  final DeviceDto? initialSelectedDevice;
  final Function(DeviceDto device)? onDeviceSelected;
  final VoidCallback? onPairRequested;

  const DesktopPhoneLinkView({
    super.key,
    this.devices = const [],
    this.initialSelectedDevice,
    this.onDeviceSelected,
    this.onPairRequested,
  });

  @override
  State<DesktopPhoneLinkView> createState() => _DesktopPhoneLinkViewState();
}

class _DesktopPhoneLinkViewState extends State<DesktopPhoneLinkView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ShanuConnectService _shanuService = ShanuConnectService();
  final TrustedDeviceStore _trustStore = TrustedDeviceStore();
  final NativeInputService _inputService = NativeInputService();
  StreamSubscription<Map<String, dynamic>>? _packetSubscription;

  String? _myDeviceId;
  // Set while we're waiting for the peer to confirm/reject the code we sent.
  String? _pendingSasCode;

  DeviceDto? _activeDevice;
  bool _isPaired = false;
  String? _pairedPeerId;
  bool _isCharging = false;
  int? _batteryLevel;
  double _mediaVolume = 70.0;
  bool _isPlaying = false;
  String? _nowPlayingTitle;
  String? _nowPlayingArtist;

  final TextEditingController _smsController = TextEditingController();
  final TextEditingController _smsPhoneController = TextEditingController();
  final TextEditingController _replyController = TextEditingController();

  final List<Map<String, String>> _notifications = [];
  final List<Map<String, String>> _smsMessages = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    if (widget.initialSelectedDevice != null) {
      _activeDevice = widget.initialSelectedDevice;
    } else if (widget.devices.isNotEmpty) {
      _activeDevice = widget.devices.first;
    }

    _startDiscovery();
  }

  Future<void> _startDiscovery() async {
    _myDeviceId = await DeviceIdentityService().getOrCreateDeviceId();
    await _shanuService.startDiscovery('Desktop Host Hub', _myDeviceId!);
    _listenForPackets();
  }

  void _listenForPackets() {
    _packetSubscription = _shanuService.packetStream.listen((packet) async {
      final type = packet['type'] as String? ?? '';
      final body = packet['body'] as Map<String, dynamic>? ?? {};
      final senderIp = packet['_senderIp'] as String?;

      if (type == 'shanuconnect.pair') {
        await _handlePairPacket(body, senderIp);
        return;
      }

      if (type == 'shanuconnect.mousepad') {
        final senderId = _activeDevice?.alias; // best-effort peer label for logs only
        final trusted = _pairedPeerId != null && await _trustStore.isTrusted(_pairedPeerId!);
        if (!trusted) {
          debugPrint('Ignored mousepad packet from untrusted/unpaired sender ($senderId)');
          return;
        }
        final dx = (body['dx'] as num?)?.toDouble() ?? 0;
        final dy = (body['dy'] as num?)?.toDouble() ?? 0;
        final click = body['click'] as String?;
        await _inputService.moveAndClick(dx: dx, dy: dy, click: click);
        return;
      }

      if (type == 'shanuconnect.presenter') {
        final next = body['next'] as bool? ?? false;
        await _inputService.sendKeyPress(next ? 'right' : 'left');
        return;
      }

      if (type == 'shanuconnect.lockdevice') {
        final trusted = _pairedPeerId != null && await _trustStore.isTrusted(_pairedPeerId!);
        if (!trusted) return;
        await _inputService.lockWorkstation();
        return;
      }

      if (type == 'shanuconnect.clipboard') {
        final content = body['content'] as String? ?? '';
        if (content.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: content));
          _showToast('Copied to Desktop Clipboard from Phone!');
        }
        return;
      }

      if (type == 'shanuconnect.findmyphone') {
        _showToast('🔔 Phone Ring Alert Triggered!');
        return;
      }

      if (type == 'shanuconnect.runcommand') {
        final trusted = _pairedPeerId != null && await _trustStore.isTrusted(_pairedPeerId!);
        if (!trusted) return;
        final key = body['key'] as String? ?? '';
        if (key == 'lock') {
          await _inputService.lockWorkstation();
        } else if (key == 'ping') {
          _showToast('Ping received from paired phone');
        }
        return;
      }

      if (type == 'shanuconnect.notifications') {
        setState(() {
          _notifications.insert(0, {
            'id': body['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString(),
            'appName': body['appName']?.toString() ?? 'Phone Alert',
            'title': body['title']?.toString() ?? body['ticker']?.toString() ?? 'Notification',
            'text': body['text']?.toString() ?? '',
            'time': 'Just now',
          });
        });
      } else if (type == 'shanuconnect.sms') {
        setState(() {
          _smsMessages.add({
            'sender': body['sender']?.toString() ?? body['phone']?.toString() ?? 'Contact',
            'text': body['body']?.toString() ?? body['text']?.toString() ?? '',
            'time': 'Just now',
          });
        });
      } else if (type == 'shanuconnect.battery') {
        setState(() {
          if (body.containsKey('currentCharge')) {
            _batteryLevel = body['currentCharge'] as int?;
          }
          if (body.containsKey('isCharging')) {
            _isCharging = body['isCharging'] as bool? ?? false;
          }
        });
      } else if (type == 'shanuconnect.mpris') {
        setState(() {
          if (body.containsKey('title')) {
            _nowPlayingTitle = body['title'] as String?;
            _nowPlayingArtist = body['artist'] as String?;
          }
          if (body.containsKey('isPlaying')) {
            _isPlaying = body['isPlaying'] as bool? ?? false;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _packetSubscription?.cancel();
    _shanuService.stop();
    _tabController.dispose();
    _smsController.dispose();
    _smsPhoneController.dispose();
    _replyController.dispose();
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

  void _requestPairing() {
    if (_myDeviceId == null) {
      _showToast('Still starting up — try again in a moment');
      return;
    }
    final targetIp = _activeDevice?.ip;
    final code = (100000 + Random.secure().nextInt(900000)).toString();
    _pendingSasCode = code;

    _shanuService.sendPairing(
      pair: true,
      deviceId: _myDeviceId!,
      sasCode: code,
      targetIp: targetIp,
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161E2E),
        title: Text('Pairing: ${_activeDevice?.alias ?? "Mobile Device"}', style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "This code was sent to the phone. Only approve there if it matches — don't type a code in, compare it:",
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                code,
                style: const TextStyle(color: Colors.white, fontSize: 32, letterSpacing: 8, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Waiting for the phone to respond…', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _pendingSasCode = null;
              Navigator.pop(ctx);
            },
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  /// Handles both directions of the pairing exchange:
  ///  - an incoming *request* from a peer (ack == false): show the code we
  ///    were sent and require an explicit compare-and-approve before trusting.
  ///  - the *reply* to a request we initiated (ack == true): only completes
  ///    pairing if the code matches what we sent — anything else is dropped.
  ///
  /// This is a mutual on-screen comparison, not a cryptographic handshake —
  /// it stops "type any 6 digits" bypasses, but a device on the LAN could
  /// still spoof UDP packets. Binding this to a real key exchange is tracked
  /// as follow-up work once the Rust core (which already has crypto
  /// primitives) is bridged in.
  Future<void> _handlePairPacket(Map<String, dynamic> body, String? senderIp) async {
    final peerId = body['deviceId'] as String?;
    final sasCode = body['sasCode'] as String?;
    final pair = body['pair'] as bool? ?? false;
    final ack = body['ack'] as bool? ?? false;
    if (peerId == null || peerId == _myDeviceId) return;

    if (ack) {
      if (_pendingSasCode == null || sasCode != _pendingSasCode) return;
      _pendingSasCode = null;
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (pair) {
        await _trustStore.trust(peerId, alias: _activeDevice?.alias);
        if (mounted) {
          setState(() {
            _isPaired = true;
            _pairedPeerId = peerId;
          });
          _showToast('Mobile Device Paired & Authenticated Successfully!');
        }
      } else if (mounted) {
        _showToast('Pairing was declined on the phone.');
      }
      return;
    }

    if (pair && sasCode != null && mounted) {
      final approved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF161E2E),
          title: const Text('Pairing request', style: TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('A device wants to pair. Confirm this code matches what it shows:',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 16),
              Center(
                child: Text(sasCode,
                    style: const TextStyle(color: Colors.white, fontSize: 32, letterSpacing: 8, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Reject', style: TextStyle(color: Colors.redAccent)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8)),
              child: const Text('Codes Match — Approve'),
            ),
          ],
        ),
      );

      final replyIp = senderIp ?? _activeDevice?.ip;
      if (approved == true) {
        await _trustStore.trust(peerId);
        _shanuService.sendPairing(pair: true, deviceId: _myDeviceId!, sasCode: sasCode, ack: true, targetIp: replyIp);
        if (mounted) {
          setState(() {
            _isPaired = true;
            _pairedPeerId = peerId;
          });
          _showToast('Paired & Authenticated Successfully!');
        }
      } else {
        _shanuService.sendPairing(pair: false, deviceId: _myDeviceId!, sasCode: sasCode, ack: true, targetIp: replyIp);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Device Selection Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF161E2E),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF283548)),
            ),
            child: Row(
              children: [
                const Icon(Icons.smartphone_rounded, color: Color(0xFF38BDF8), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          DropdownButtonHideUnderline(
                            child: DropdownButton<DeviceDto>(
                              value: _activeDevice,
                              dropdownColor: const Color(0xFF161E2E),
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white70),
                              items: widget.devices.map((d) {
                                return DropdownMenuItem<DeviceDto>(
                                  value: d,
                                  child: Text(
                                    d.alias,
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _activeDevice = val);
                                  widget.onDeviceSelected?.call(val);
                                }
                              },
                              hint: const Text('Select Device', style: TextStyle(color: Colors.white)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _isPaired ? const Color(0xFF10B981).withValues(alpha: 0.2) : Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _isPaired ? 'CONNECTED' : 'UNPAIRED',
                              style: TextStyle(
                                color: _isPaired ? const Color(0xFF10B981) : Colors.amber,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _activeDevice != null ? '${_activeDevice!.ip} • ${_activeDevice!.deviceModel}' : 'No target device selected',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    if (_isPaired) {
                      if (_pairedPeerId != null) _trustStore.revoke(_pairedPeerId!);
                      setState(() {
                        _isPaired = false;
                        _pairedPeerId = null;
                      });
                      _showToast('Device Unpaired');
                    } else {
                      _requestPairing();
                    }
                  },
                  icon: Icon(_isPaired ? Icons.check_circle_rounded : Icons.add_rounded, size: 18),
                  label: Text(_isPaired ? 'Paired' : '+ Pair New Device'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isPaired ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                    foregroundColor: const Color(0xFF090B11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Real Phone Status Mini Cards
          Row(
            children: [
              Expanded(
                child: _buildStatusMiniCard(
                  icon: Icons.battery_charging_full_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: 'Battery',
                  subtitle: _batteryLevel != null
                      ? '$_batteryLevel% • ${_isCharging ? "Charging" : "Discharging"}'
                      : (_isPaired ? 'Battery Sync Active' : 'Unpaired'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatusMiniCard(
                  icon: Icons.wifi_rounded,
                  iconColor: const Color(0xFF38BDF8),
                  title: 'Wi-Fi Signal',
                  subtitle: _activeDevice != null ? 'Connected LAN' : 'Disconnected',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatusMiniCard(
                  icon: Icons.phonelink_ring_rounded,
                  iconColor: const Color(0xFF6366F1),
                  title: 'Find Phone',
                  subtitle: 'Ring Alert',
                  onTap: () {
                    if (_activeDevice != null) {
                      _shanuService.sendPacket({'type': 'shanuconnect.findmyphone', 'body': {}}, _activeDevice!.ip);
                      _showToast('Ringing phone sound alert...');
                    } else {
                      _showToast('Select a device first to ring.');
                    }
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Tab Selector Header
          TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFF38BDF8),
            labelColor: const Color(0xFF38BDF8),
            unselectedLabelColor: Colors.white54,
            tabs: const [
              Tab(icon: Icon(Icons.notifications_rounded), text: 'Notifications'),
              Tab(icon: Icon(Icons.music_note_rounded), text: 'Media Stream'),
              Tab(icon: Icon(Icons.sms_rounded), text: 'SMS Messages'),
              Tab(icon: Icon(Icons.assignment_rounded), text: 'Clipboard Sync'),
            ],
          ),

          const SizedBox(height: 12),

          // Tab Contents
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildNotificationsTab(),
                _buildMediaTab(),
                _buildSmsTab(),
                _buildClipboardTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusMiniCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF161E2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF283548)),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  Text(subtitle, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsTab() {
    if (_notifications.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF161E2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF283548)),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.notifications_paused_rounded, size: 56, color: Colors.white24),
              SizedBox(height: 16),
              Text('No Notifications Synced Yet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              SizedBox(height: 6),
              Text(
                'Pair your mobile device and enable notification access in ShanuSend to stream live alerts here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _notifications.length,
      itemBuilder: (context, index) {
        final item = _notifications[index];
        return Card(
          color: const Color(0xFF161E2E),
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(item['appName']!, style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
                    Text(item['time']!, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(item['title']!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                Text(item['text']!, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _replyController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Type reply...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          filled: true,
                          fillColor: const Color(0xFF090B11),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.send_rounded, color: Color(0xFF38BDF8)),
                      onPressed: () {
                        if (_replyController.text.isNotEmpty) {
                          _shanuService.sendNotificationReply(item['id']!, _replyController.text, _activeDevice?.ip);
                          _showToast('Reply sent to ${item['title']}');
                          _replyController.clear();
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMediaTab() {
    final hasMedia = _nowPlayingTitle != null && _nowPlayingTitle!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF161E2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF283548)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.music_note_rounded, size: 50, color: Color(0xFF38BDF8)),
          ),
          const SizedBox(height: 16),
          Text(
            hasMedia ? _nowPlayingTitle! : 'No Active Media Stream',
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            hasMedia ? (_nowPlayingArtist ?? 'Unknown Artist') : 'Play audio or video on target phone to control MPRIS media stream.',
            style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 36,
                icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                onPressed: () => _shanuService.sendMprisCommand('previous', targetIp: _activeDevice?.ip),
              ),
              const SizedBox(width: 16),
              IconButton(
                iconSize: 48,
                icon: Icon(_isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: const Color(0xFF38BDF8)),
                onPressed: () {
                  setState(() => _isPlaying = !_isPlaying);
                  _shanuService.sendMprisCommand(_isPlaying ? 'play' : 'pause', targetIp: _activeDevice?.ip);
                },
              ),
              const SizedBox(width: 16),
              IconButton(
                iconSize: 36,
                icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                onPressed: () => _shanuService.sendMprisCommand('next', targetIp: _activeDevice?.ip),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.volume_down_rounded, color: Colors.white54),
              Expanded(
                child: Slider(
                  value: _mediaVolume,
                  min: 0,
                  max: 100,
                  activeColor: const Color(0xFF38BDF8),
                  onChanged: (v) {
                    setState(() => _mediaVolume = v);
                    _shanuService.sendSystemVolume(v, _activeDevice?.ip);
                  },
                ),
              ),
              const Icon(Icons.volume_up_rounded, color: Colors.white54),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSmsTab() {
    return Column(
      children: [
        Expanded(
          child: _smsMessages.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(24),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF161E2E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF283548)),
                  ),
                  child: const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mark_chat_read_rounded, size: 56, color: Colors.white24),
                        SizedBox(height: 16),
                        Text('No Active SMS Messages', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        SizedBox(height: 6),
                        Text(
                          'Type a message below to send via paired phone, or wait for incoming SMS alerts.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: _smsMessages.length,
                  itemBuilder: (context, index) {
                    final msg = _smsMessages[index];
                    final isMe = msg['sender'] == 'Me';
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? const Color(0xFF6366F1) : const Color(0xFF161E2E),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(msg['text']!, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF161E2E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _smsController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Type SMS message to send via phone...',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send_rounded, color: Color(0xFF38BDF8)),
                onPressed: () {
                  if (_smsController.text.isNotEmpty) {
                    setState(() {
                      _smsMessages.add({
                        'sender': 'Me',
                        'text': _smsController.text,
                        'time': 'Now',
                      });
                    });
                    _shanuService.sendTelephonyCallAction('sendSms', _smsController.text, _activeDevice?.ip);
                    _showToast('SMS sent via ${_activeDevice?.alias ?? "Phone"}');
                    _smsController.clear();
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClipboardTab() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF161E2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF283548)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Bidirectional Clipboard Auto-Sync', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('Text copied on your phone instantly syncs to Windows clipboard.', style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              _shanuService.sendClipboardText('Text copied from Desktop', _activeDevice?.ip);
              _showToast('Synced desktop clipboard to phone!');
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Push Desktop Clipboard to Phone'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF38BDF8),
              foregroundColor: const Color(0xFF090B11),
            ),
          ),
        ],
      ),
    );
  }
}
