import 'dart:async';
import 'package:flutter/services.dart';

class ClipboardSyncService {
  static final ClipboardSyncService _instance = ClipboardSyncService._internal();
  factory ClipboardSyncService() => _instance;
  ClipboardSyncService._internal();

  Timer? _pollTimer;
  String _lastText = '';
  bool _enabled = false;

  void startAutoSync({
    required Function(String text) onClipboardChanged,
    Duration pollInterval = const Duration(milliseconds: 1500),
  }) {
    _enabled = true;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) async {
      if (!_enabled) return;
      try {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final currentText = data?.text ?? '';
        if (currentText.isNotEmpty && currentText != _lastText) {
          _lastText = currentText;
          onClipboardChanged(currentText);
        }
      } catch (_) {
        // Platform access ignore
      }
    });
  }

  void stopAutoSync() {
    _enabled = false;
    _pollTimer?.cancel();
  }

  Future<void> updateLocalClipboard(String newText) async {
    if (newText.isEmpty || newText == _lastText) return;
    _lastText = newText;
    await Clipboard.setData(ClipboardData(text: newText));
  }

  void dispose() {
    stopAutoSync();
  }
}
