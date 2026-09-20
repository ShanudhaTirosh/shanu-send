import 'package:flutter/material.dart';

class RemoteTrackpadView extends StatefulWidget {
  const RemoteTrackpadView({super.key});

  @override
  State<RemoteTrackpadView> createState() => _RemoteTrackpadViewState();
}

class _RemoteTrackpadViewState extends State<RemoteTrackpadView> {
  Offset? _lastPosition;
  String _statusMsg = 'Drag to move cursor';

  void _onPanStart(DragStartDetails details) {
    _lastPosition = details.localPosition;
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_lastPosition != null) {
      final dx = details.localPosition.dx - _lastPosition!.dx;
      final dy = details.localPosition.dy - _lastPosition!.dy;
      _lastPosition = details.localPosition;

      if (dx.abs() > 0.5 || dy.abs() > 0.5) {
        // Trackpad delta movement processed
      }
    }
  }

  void _onPanEnd(DragEndDetails details) {
    _lastPosition = null;
  }

  void _showFeedback(String msg) {
    setState(() {
      _statusMsg = msg;
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _statusMsg = 'Drag to move cursor';
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05060A),
      appBar: AppBar(
        title: const Text('Remote Trackpad & Controls', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0A0D16),
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Trackpad Canvas
            Expanded(
              child: GestureDetector(
                onPanStart: _onPanStart,
                onPanUpdate: _onPanUpdate,
                onPanEnd: _onPanEnd,
                onTap: () => _showFeedback('Left Click'),
                onDoubleTap: () => _showFeedback('Double Click'),
                onLongPress: () => _showFeedback('Right Click'),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF121622),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white10),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0F4DD9FF),
                        blurRadius: 20,
                      )
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.touch_app, size: 48, color: Color(0xFF4DD9FF)),
                        const SizedBox(height: 12),
                        Text(
                          _statusMsg,
                          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Tap = Click | Hold = Right Click',
                          style: TextStyle(color: Colors.white38, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Left & Right Mouse Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _showFeedback('Left Click'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF121622),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Colors.white10),
                      ),
                    ),
                    child: const Text('Left Click'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _showFeedback('Right Click'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF121622),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: const BorderSide(color: Colors.white10),
                      ),
                    ),
                    child: const Text('Right Click'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Presentation Remote Slide Controls
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF121622),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white70, size: 20),
                    onPressed: () => _showFeedback('Prev Slide'),
                    tooltip: 'Previous Slide',
                  ),
                  IconButton(
                    icon: const Icon(Icons.play_arrow, color: Color(0xFF4DD9FF), size: 24),
                    onPressed: () => _showFeedback('Play / Pause'),
                    tooltip: 'Play / Pause',
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 20),
                    onPressed: () => _showFeedback('Next Slide'),
                    tooltip: 'Next Slide',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
