// Persisted allow-list of ShanuConnect peers that have completed pairing.
// Every handler for a capability that can affect the local machine
// (mousepad, keyboard, runcommand, systemvolume, lockdevice, clipboard) must
// check isTrusted() before acting — today, before this fix, nothing did.
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class TrustedDeviceStore {
  Future<File> _file() async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, 'trusted_devices.json'));
  }

  Future<Map<String, dynamic>> _readAll() async {
    final file = await _file();
    if (!await file.exists()) return {};
    try {
      final content = await file.readAsString();
      if (content.trim().isEmpty) return {};
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> _writeAll(Map<String, dynamic> data) async {
    final file = await _file();
    await file.create(recursive: true);
    await file.writeAsString(jsonEncode(data));
  }

  Future<bool> isTrusted(String deviceId) async {
    final all = await _readAll();
    return all.containsKey(deviceId);
  }

  Future<void> trust(String deviceId, {String? alias}) async {
    final all = await _readAll();
    all[deviceId] = {
      'alias': alias ?? deviceId,
      'pairedAt': DateTime.now().toIso8601String(),
    };
    await _writeAll(all);
  }

  Future<void> revoke(String deviceId) async {
    final all = await _readAll();
    all.remove(deviceId);
    await _writeAll(all);
  }

  Future<void> revokeAll() async {
    await _writeAll({});
  }

  Future<Map<String, dynamic>> listTrusted() => _readAll();
}
