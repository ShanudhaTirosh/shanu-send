import 'package:flutter/material.dart';

class KdeConnectView extends StatefulWidget {
  final String deviceName;
  const KdeConnectView({super.key, this.deviceName = 'Desktop PC'});

  @override
  State<KdeConnectView> createState() => _KdeConnectViewState();
}

class _KdeConnectViewState extends State<KdeConnectView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isPlaying = true;
  double _volume = 75.0;
  final TextEditingController _commandController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
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
        title: Text(
          widget.deviceName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                          Text('Multi-Touch Trackpad', style: TextStyle(color: Colors.white, fontSize: 16)),
                          Text('Drag to move • Tap to click', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E293B)),
                        child: const Text('Left Click'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {},
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
                const Text('Starlight Odyssey', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                const Text('Neon Eclipse', style: TextStyle(color: Colors.white54, fontSize: 14)),
                const SizedBox(height: 32),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      iconSize: 40,
                      icon: const Icon(Icons.skip_previous_rounded, color: Colors.white),
                      onPressed: () {},
                    ),
                    IconButton(
                      iconSize: 64,
                      icon: Icon(
                        _isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                        color: const Color(0xFF38BDF8),
                      ),
                      onPressed: () => setState(() => _isPlaying = !_isPlaying),
                    ),
                    IconButton(
                      iconSize: 40,
                      icon: const Icon(Icons.skip_next_rounded, color: Colors.white),
                      onPressed: () {},
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Slider(
                  value: _volume,
                  min: 0,
                  max: 100,
                  activeColor: const Color(0xFF38BDF8),
                  onChanged: (v) => setState(() => _volume = v),
                ),
              ],
            ),
          ),

          // 3. Remote Commands
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _commandController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Execute remote terminal command...',
                    hintStyle: const TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: const Color(0xFF161E2E),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    children: [
                      ListTile(
                        tileColor: const Color(0xFF161E2E),
                        title: const Text('Lock Computer', style: TextStyle(color: Colors.white)),
                        trailing: const Icon(Icons.lock_rounded, color: Color(0xFF38BDF8)),
                        onTap: () {},
                      ),
                      const SizedBox(height: 8),
                      ListTile(
                        tileColor: const Color(0xFF161E2E),
                        title: const Text('Mute System Audio', style: TextStyle(color: Colors.white)),
                        trailing: const Icon(Icons.volume_off_rounded, color: Color(0xFF38BDF8)),
                        onTap: () {},
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
                  onPressed: () {},
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Previous Slide'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E293B),
                    minimumSize: const Size.fromHeight(60),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () {},
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
