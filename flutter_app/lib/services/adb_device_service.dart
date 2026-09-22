// Real `adb devices -l` polling — replaces the previous static, single-entry
// device dropdown in the Scrcpy panel with the devices actually attached.
import 'dart:async';
import 'dart:io';

class AdbDevice {
  final String serial;
  final String state; // device | unauthorized | offline
  final String? model;
  final String? product;

  const AdbDevice({
    required this.serial,
    required this.state,
    this.model,
    this.product,
  });

  /// Wireless-debugging serials look like `192.168.1.23:5555`; USB serials
  /// are opaque device IDs with no colon.
  bool get isWireless => serial.contains(':');

  String get label {
    final name = (model ?? product ?? 'Android device').replaceAll('_', ' ');
    final via = isWireless ? 'Wi-Fi' : 'USB';
    return '$name  ·  $via  ·  $serial';
  }
}

class AdbPairResult {
  final bool success;
  final String message;
  const AdbPairResult({required this.success, required this.message});
}

class AdbDeviceService {
  final String adbPath;
  const AdbDeviceService(this.adbPath);

  Future<List<AdbDevice>> listDevices() async {
    final result = await Process.run(adbPath, ['devices', '-l']);
    if (result.exitCode != 0) return const [];

    final lines = (result.stdout as String).split('\n');
    final devices = <AdbDevice>[];
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('List of devices')) continue;

      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      final serial = parts[0];
      final state = parts[1];

      String? model;
      String? product;
      for (final field in parts.skip(2)) {
        if (field.startsWith('model:')) model = field.substring(6);
        if (field.startsWith('product:')) product = field.substring(8);
      }

      devices.add(AdbDevice(
        serial: serial,
        state: state,
        model: model,
        product: product,
      ));
    }
    return devices;
  }

  /// Emits the current device list every [interval], stopping when the
  /// returned subscription is cancelled. Failures (e.g. adb server briefly
  /// restarting) are swallowed as an empty tick rather than killing the
  /// stream, since this drives a live UI panel.
  Stream<List<AdbDevice>> watch({Duration interval = const Duration(seconds: 2)}) async* {
    while (true) {
      try {
        yield await listDevices();
      } catch (_) {
        yield const [];
      }
      await Future.delayed(interval);
    }
  }

  /// Android 11+ wireless debugging: pairs with the code shown in
  /// Settings > Developer options > Wireless debugging > Pair with pairing code.
  Future<AdbPairResult> pairWireless(String hostAndPort, String pairingCode) async {
    final result = await Process.run(adbPath, ['pair', hostAndPort, pairingCode]);
    final output = '${result.stdout}${result.stderr}'.trim();
    return AdbPairResult(success: result.exitCode == 0, message: output);
  }

  /// After pairing, the device must also be `connect`-ed (usually on a
  /// different port than the pairing port — the one shown on the main
  /// Wireless debugging screen).
  Future<AdbPairResult> connectWireless(String hostAndPort) async {
    final result = await Process.run(adbPath, ['connect', hostAndPort]);
    final output = '${result.stdout}${result.stderr}'.trim();
    final success = output.toLowerCase().contains('connected to');
    return AdbPairResult(success: success, message: output);
  }
}
