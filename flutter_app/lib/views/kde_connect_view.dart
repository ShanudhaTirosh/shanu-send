import 'package:flutter/material.dart';
import '../services/kde_connect_service.dart';

class KdeConnectView extends StatefulWidget {
  final String deviceName;
  final String? targetIp;
  const KdeConnectView({super.key, this.deviceName = 'Desktop PC', this.targetIp});

  @override
  State<KdeConnectView> createState() => _KdeConnectViewState();
}

class _KdeConnectViewState extends State<KdeConnectView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final KdeConnectService _kdeService = KdeConnectService();
  bool _isPlaying = true;
  double _volume = 75.0;
  final TextEditingController _commandController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _kdeService.startDiscovery('Mobile Remote Controller', 'mobile-remote-id');
  }

  @override
  void dispose() {
    _kdeService.stop();
    _tabController.dispose();
    _commandController.dispose();
    super.dispose();
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
            Text(
              widget.deviceName,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Text(
              'Mobile Remote Controller Active',
              style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF38BDF8),
          labelColor: const Color(0xFF38BDF8),
          unselectedLabelColor: Colors.white54,
          tabs: const [
            Tab(icon: Icon(Icons.mouse_rounded), text: 'Touchpad'),
            Tab(icon: Icon(Icons.play_circle_fill_rounded), text: 'Media'),
            Tab(icon: Icon(Icons.terminal_rounded), text: 'Commands'),
            Tab(icon: Icon(Icons.slideshow_rounded), text: 'Presenter'),
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
                      _kdeService.sendMousepad(details.delta.dx, details.delta.dy, targetIp: widget.targetIp);
                    },
                    onTap: () {
                      _kdeService.sendMousepad(0, 0, click: 'singleclick', targetIp: widget.targetIp);
                    },
                    onDoubleTap: () {
                      _kdeService.sendMousepad(0, 0, click: 'doubleclick', targetIp: widget.targetIp);
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
                          _kdeService.sendMousepad(0, 0, click: 'singleclick', targetIp: widget.targetIp);
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
                        child: const Text('Left Click'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          _kdeService.sendMousepad(0, 0, click: 'rightclick', targetIp: widget.targetIp);
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
                        child: const Text('Right Click'),
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
                        _kdeService.sendMprisCommand('previous', targetIp: widget.targetIp);
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
                        _kdeService.sendMprisCommand(_isPlaying ? 'play' : 'pause', targetIp: widget.targetIp);
                      },
                    ),
                    IconButton(
                      iconSize: 40,
                      icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                      onPressed: () {
                        _kdeService.sendMprisCommand('next', targetIp: widget.targetIp);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Slider(
                  value: _volume,
                  min: 0,
                  max: 100,
                  activeColor: const Color(0xFF38BDF8),
                  onChanged: (v) {
                    setState(() => _volume = v);
                    _kdeService.sendMprisCommand('volume', volume: v, targetIp: widget.targetIp);
                  },
                ),
              ],
            ),
          ),

          // 3. Remote Commands
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
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
                          _kdeService.sendRunCommand(_commandController.text, widget.targetIp);
                          _commandController.clear();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: [
                      ListTile(
                        tileColor: const Color(0xFF161E2E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        title: const Text('Lock Desktop Workstation', style: TextStyle(color: Colors.white)),
                        trailing: const Icon(Icons.lock_rounded, color: Color(0xFF38BDF8)),
                        onTap: () {
                          _kdeService.sendRunCommand('lock', widget.targetIp);
                        },
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        tileColor: const Color(0xFF161E2E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        title: const Text('Send Ping Signal', style: TextStyle(color: Colors.white)),
                        trailing: const Icon(Icons.notifications_active_rounded, color: Color(0xFF38BDF8)),
                        onTap: () {
                          _kdeService.sendRunCommand('ping', widget.targetIp);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 4. Presenter Clicker
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    _kdeService.sendPresenterSlide(next: false, targetIp: widget.targetIp);
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
                    _kdeService.sendPresenterSlide(next: true, targetIp: widget.targetIp);
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
        ],
      ),
    );
  }
}

