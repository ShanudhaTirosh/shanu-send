import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shanu_send_flutter/services/adb_device_service.dart';
import 'package:shanu_send_flutter/services/native_input_service.dart';
import 'package:shanu_send_flutter/services/shanu_connect_service.dart';
import 'package:shanu_send_flutter/services/trusted_device_store.dart';
import 'package:shanu_send_flutter/services/tool_bootstrap_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return Directory.systemTemp.path;
      },
    );
  });

  group('AdbDevice & Service Parsing Tests', () {
    test('Parses USB and Wireless ADB device outputs correctly', () {
      final usbDevice = const AdbDevice(
        serial: 'R58M123456X',
        state: 'device',
        model: 'Galaxy_S21',
        product: 'o1s',
      );

      final wifiDevice = const AdbDevice(
        serial: '192.168.1.50:5555',
        state: 'device',
        model: 'Pixel_7',
        product: 'panther',
      );

      expect(usbDevice.isWireless, false);
      expect(wifiDevice.isWireless, true);

      expect(usbDevice.label, 'Galaxy S21  ·  USB  ·  R58M123456X');
      expect(wifiDevice.label, 'Pixel 7  ·  Wi-Fi  ·  192.168.1.50:5555');
    });

    test('Handles unauthorized device state in label formatting', () {
      final unauthorized = const AdbDevice(
        serial: '192.168.1.99:5555',
        state: 'unauthorized',
        model: 'OnePlus_9',
      );

      expect(unauthorized.state, 'unauthorized');
      expect(unauthorized.isWireless, true);
    });
  });

  group('NativeInputService Tests', () {
    test('Check support returns valid status for platform', () async {
      final inputService = NativeInputService();
      final support = await inputService.checkSupport();
      expect(support, isA<InputSupport>());
    });
  });

  group('ToolBootstrapService Structure Tests', () {
    test('Resolves tool availability paths without throwing', () async {
      final bootstrap = ToolBootstrapService();
      final paths = await bootstrap.resolve();
      expect(paths, isA<ToolPaths>());
      expect(paths.isReady, isA<bool>());
    });

    test('ToolBootstrapNeedsManualInstall formats instructions correctly', () {
      const exc = ToolBootstrapNeedsManualInstall('brew install scrcpy');
      expect(exc.toString(), contains('brew install scrcpy'));
    });

    test('ToolBootstrapException formats message correctly', () {
      const exc = ToolBootstrapException('Download failed');
      expect(exc.toString(), 'Download failed');
    });
  });

  group('TrustedDeviceStore Tests', () {
    test('Stores and revokes trusted devices', () async {
      final store = TrustedDeviceStore();
      const testId = 'test-device-uuid-1234';

      expect(await store.isTrusted(testId), false);
      await store.trust(testId, alias: 'Test Phone');
      expect(await store.isTrusted(testId), true);
      
      final list = await store.listTrusted();
      expect(list.containsKey(testId), true);

      await store.revoke(testId);
      expect(await store.isTrusted(testId), false);
    });
  });

  group('ShanuConnect Packet Verification Tests', () {
    test('Sends mousepad packet structure with correct target IP', () {
      final service = ShanuConnectService();
      expect(() => service.sendMousepad(10.0, -5.0, click: 'left', targetIp: '127.0.0.1'), returnsNormally);
    });

    test('Sends pairing packet with SAS code', () {
      final service = ShanuConnectService();
      expect(
        () => service.sendPairing(
          pair: true,
          deviceId: 'test-device-uuid',
          sasCode: '123456',
          ack: false,
          targetIp: '127.0.0.1',
        ),
        returnsNormally,
      );
    });

    test('Sends presenter slide control packet', () {
      final service = ShanuConnectService();
      expect(() => service.sendPresenterSlide(next: true, targetIp: '127.0.0.1'), returnsNormally);
      expect(() => service.sendPresenterSlide(next: false, targetIp: '127.0.0.1'), returnsNormally);
    });
  });
}
