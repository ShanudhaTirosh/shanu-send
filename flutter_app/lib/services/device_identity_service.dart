// Every install of ShanuSend used to broadcast a literal, hardcoded string
// ('mobile-remote-id' on the phone build, 'desktop-host-id' on the desktop
// build) as its ShanuConnect device ID. That means trust/pairing decisions
// keyed on deviceId were meaningless — every phone looked identical to every
// other phone, and likewise for desktops. This gives each install a real,
// persistent, randomly generated ID the first time it runs.
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class DeviceIdentityService {
  static String? _cached;

  Future<String> getOrCreateDeviceId() async {
    if (_cached != null) return _cached!;

    final support = await getApplicationSupportDirectory();
    final file = File(p.join(support.path, 'device_id.txt'));

    if (await file.exists()) {
      final existing = (await file.readAsString()).trim();
      if (existing.isNotEmpty) {
        _cached = existing;
        return existing;
      }
    }

    final id = const Uuid().v4();
    await file.create(recursive: true);
    await file.writeAsString(id);
    _cached = id;
    return id;
  }
}
