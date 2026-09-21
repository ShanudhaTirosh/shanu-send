import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/shanu_connect_service.dart';

class ShanuConnectView extends StatefulWidget {
  final String deviceName;
  final String? targetIp;
  const ShanuConnectView({super.key, this.deviceName = 'Desktop PC', this.targetIp});

  @override
  State<ShanuConnectView> createState() => _ShanuConnectViewState();
}

typedef KdeConnectView = ShanuConnectView;

class _ShanuConnectViewState extends State<ShanuConnectView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ShanuConnectService _shanuService = ShanuConnectService();
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _shanuService.startDiscovery('Mobile Remote Controller', 'mobile-remote-id');
  }

  @override
  void dispose() {
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
        backgroundColor: const Color(0xFF1E293B),
      ),
    );
  }

  void _requestPairing() {
    _shanuService.sendPairing(pair: true, targetIp: widget.targetIp);
    setState(() => _isPairingRequested = true);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161E2E),
        title: const Text('Connect & Pair Device', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pairing request sent. Please enter the 6-digit SAS PIN shown on target Desktop PC:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(color: Colors.white, fontSize: 18, letterSpacing: 4),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                hintText: '123456',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF090B11),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
            onPressed: () {
              if (_pinController.text.length == 6) {
                setState(() {
                  _isPaired = true;
                  _isPairingRequested = false;
                });
                Navigator.pop(ctx);
                _showToast('Device Paired & Connected Successfully!');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8)),
            child: const Text('Approve & Connect'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090B11),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090B11),
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  widget.deviceName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _isPaired ? const Color(0xFF10B981).withValues(alpha: 0.2) : Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _isPaired ? 'CONNECTED' : (_isPairingRequested ? 'PAIRING...' : 'UNPAIRED'),
                    style: TextStyle(
                      color: _isPaired ? const Color(0xFF10B981) : (_isPairingRequested ? const Color(0xFF38BDF8) : Colors.amber),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              _isPaired ? 'ShanuConnect Authenticated Session' : (_isPairingRequested ? 'PIN confirmation pending...' : 'Device not paired'),
              style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11),
            ),
          ],
        ),
        actions: [
          if (!_isPaired)
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: ElevatedButton.icon(
                onPressed: _requestPairing,
                icon: const Icon(Icons.link_rounded, size: 16),
                label: const Text('Connect & Pair'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF38BDF8),
                  foregroundColor: const Color(0xFF090B11),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: const Color(0xFF38BDF8),
          labelColor: const Color(0xFF38BDF8),
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.mouse_rounded), text: 'Touchpad'),
            Tab(icon: Icon(Icons.play_circle_fill_rounded), text: 'Media'),
            Tab(icon: Icon(Icons.terminal_rounded), text: 'Commands'),
            Tab(icon: Icon(Icons.assignment_rounded), text: 'Clipboard'),
            Tab(icon: Icon(Icons.slideshow_rounded), text: 'Presenter'),
            Tab(icon: Icon(Icons.notifications_rounded), text: 'Notifications'),
            Tab(icon: Icon(Icons.phone_in_talk_rounded), text: 'Calls'),
          ],
        ),
      ),
      body: TabBarView(
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
                      _shanuService.sendMousepad(details.delta.dx, details.delta.dy, targetIp: widget.targetIp);
                    },
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _shanuService.sendMousepad(0, 0, click: 'singleclick', targetIp: widget.targetIp);
                    },
                    onDoubleTap: () {
                      HapticFeedback.mediumImpact();
                      _shanuService.sendMousepad(0, 0, click: 'doubleclick', targetIp: widget.targetIp);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF161E2E),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.2)),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.touch_app_rounded, size: 64, color: Color(0xFF38BDF8)),
                            SizedBox(height: 12),
                            Text('Multi-Touch Trackpad Surface', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            SizedBox(height: 4),
                            Text('Drag to move Desktop cursor • Tap to Click', style: TextStyle(color: Colors.white54, fontSize: 12)),
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
                          _shanuService.sendMousepad(0, 0, click: 'singleclick', targetIp: widget.targetIp);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Left Click', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _shanuService.sendMousepad(0, 0, click: 'rightclick', targetIp: widget.targetIp);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E293B),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Right Click', style: TextStyle(color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 2. Media Remote
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
                const Text('Desktop MPRIS Stream', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const Text('Connected Host Media Player', style: TextStyle(color: Colors.white54, fontSize: 14)),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 40,
                      icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                      onPressed: () {
                        _shanuService.sendMprisCommand('previous', targetIp: widget.targetIp);
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
                        _shanuService.sendMprisCommand(_isPlaying ? 'play' : 'pause', targetIp: widget.targetIp);
                      },
                    ),
                    IconButton(
                      iconSize: 40,
                      icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                      onPressed: () {
                        _shanuService.sendMprisCommand('next', targetIp: widget.targetIp);
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
                          _shanuService.sendMprisCommand('volume', volume: v, targetIp: widget.targetIp);
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
                          hintText: 'Execute remote command...',
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
                          _shanuService.sendRunCommand(_commandController.text, widget.targetIp);
                          _showToast('Command Sent: ${_commandController.text}');
                          _commandController.clear();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Workstation System Volume', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                Slider(
                  value: _systemVolume,
                  min: 0,
                  max: 100,
                  activeColor: const Color(0xFF38BDF8),
                  onChanged: (v) {
                    setState(() => _systemVolume = v);
                    _shanuService.sendSystemVolume(v, widget.targetIp);
                  },
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    children: [
                      ListTile(
                        tileColor: const Color(0xFF161E2E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        title: Text(_isLocked ? 'Unlock Desktop Workstation' : 'Lock Desktop Workstation', style: const TextStyle(color: Colors.white)),
                        trailing: Icon(Icons.lock_rounded, color: _isLocked ? Colors.redAccent : const Color(0xFF38BDF8)),
                        onTap: () {
                          setState(() => _isLocked = !_isLocked);
                          _shanuService.sendLockDevice(lock: _isLocked, targetIp: widget.targetIp);
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
                          _shanuService.sendRunCommand('ping', widget.targetIp);
                          _showToast('Ping Signal Broadcast');
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
                const Text('Type or paste content to sync with Host desktop clipboard.', style: TextStyle(color: Colors.white54, fontSize: 12)),
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
                        _shanuService.sendClipboardText(_clipboardController.text, widget.targetIp);
                        setState(() => _clipboardFeedback = 'Clipboard content synced to host!');
                        _showToast('Clipboard synced!');
                      }
                    },
                    icon: const Icon(Icons.assignment_turned_in_rounded),
                    label: const Text('Sync to Host Clipboard'),
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
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    _shanuService.sendPresenterSlide(next: false, targetIp: widget.targetIp);
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
                    _shanuService.sendPresenterSlide(next: true, targetIp: widget.targetIp);
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
                          Text('Active app alerts from your phone will stream here automatically.', style: TextStyle(color: Colors.white38, fontSize: 12), textAlign: TextAlign.center),
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
                                  _shanuService.sendTelephonyCallAction('reject_sms', _quickSmsController.text, widget.targetIp);
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
    );
  }
}
