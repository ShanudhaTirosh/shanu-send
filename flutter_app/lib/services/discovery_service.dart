import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../models/device_dto.dart';

class DiscoveryService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(milliseconds: 600),
    receiveTimeout: const Duration(milliseconds: 600),
  ));

  final NetworkInfo _networkInfo = NetworkInfo();
  final _deviceStreamController = StreamController<List<DeviceDto>>.broadcast();

  final List<DeviceDto> _discoveredDevices = [];
  RawDatagramSocket? _multicastSocket;
  Timer? _announcementTimer;
  bool _isScanning = false;

  Stream<List<DeviceDto>> get deviceStream => _deviceStreamController.stream;
  List<DeviceDto> get devices => List.unmodifiable(_discoveredDevices);
  bool get isScanning => _isScanning;

  Future<void> initMulticast({String deviceAlias = 'ShanuSend Phone'}) async {
    try {
      final group = InternetAddress('224.0.0.167');
      _multicastSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 53317, reuseAddress: true);
      _multicastSocket?.multicastLoopback = false;
      _multicastSocket?.joinMulticast(group);

      _multicastSocket?.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = _multicastSocket?.receive();
          if (datagram != null) {
            _handleMulticastDatagram(datagram);
          }
        }
      });

      // Start periodic self-announcement
      _announcementTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        announceSelf(deviceAlias: deviceAlias);
      });
      announceSelf(deviceAlias: deviceAlias);
    } catch (e) {
      debugPrint('Multicast initialization warning: $e');
    }
  }

  void _handleMulticastDatagram(Datagram datagram) {
    try {
      final message = utf8.decode(datagram.data);
      final json = jsonDecode(message) as Map<String, dynamic>;

      final ip = datagram.address.address;
      final device = DeviceDto.fromJson(json, ip);

      if (!_discoveredDevices.any((d) => d.ip == ip || d.fingerprint == device.fingerprint)) {
        _discoveredDevices.add(device);
        _deviceStreamController.add(List.from(_discoveredDevices));
      }
    } catch (_) {
      // Non-JSON datagram or invalid format
    }
  }

  Future<void> announceSelf({String deviceAlias = 'ShanuSend Phone'}) async {
    if (_multicastSocket == null) return;
    try {
      final payload = jsonEncode({
        'alias': deviceAlias,
        'version': '2.1',
        'deviceModel': 'Mobile',
        'deviceType': 'mobile',
        'fingerprint': 'shanu_mobile_fp',
        'port': 53317,
        'protocol': 'http',
        'download': false,
        'announcement': true,
      });

      final bytes = utf8.encode(payload);
      _multicastSocket?.send(bytes, InternetAddress('224.0.0.167'), 53317);
    } catch (e) {
      debugPrint('Multicast announce error: $e');
    }
  }

  Future<String?> getLocalIp() async {
    try {
      final wifiIp = await _networkInfo.getWifiIP();
      if (wifiIp != null && wifiIp.isNotEmpty) return wifiIp;
    } catch (_) {}

    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> scanSubnet() async {
    if (_isScanning) return;
    _isScanning = true;
    _discoveredDevices.clear();
    _deviceStreamController.add(_discoveredDevices);

    // Announce via multicast first for instant discovery
    announceSelf();

    final localIp = await getLocalIp();
    if (localIp == null) {
      _isScanning = false;
      return;
    }

    final subnetParts = localIp.split('.');
    if (subnetParts.length != 4) {
      _isScanning = false;
      return;
    }

    final subnetPrefix = '${subnetParts[0]}.${subnetParts[1]}.${subnetParts[2]}';

    final futures = <Future>[];
    for (int i = 1; i <= 254; i++) {
      final targetIp = '$subnetPrefix.$i';
      if (targetIp == localIp) continue;

      futures.add(_probeIp(targetIp));
    }

    await Future.wait(futures);
    _isScanning = false;
  }

  Future<void> _probeIp(String ip) async {
    try {
      final response = await _dio.get('http://$ip:53317/api/localsend/v2/info');
      if (response.statusCode == 200 && response.data != null) {
        final device = DeviceDto.fromJson(Map<String, dynamic>.from(response.data), ip);
        if (!_discoveredDevices.any((d) => d.ip == ip || d.fingerprint == device.fingerprint)) {
          _discoveredDevices.add(device);
          _deviceStreamController.add(List.from(_discoveredDevices));
        }
      }
    } catch (_) {
      // Offline or non-responsive host
    }
  }

  void dispose() {
    _announcementTimer?.cancel();
    _multicastSocket?.close();
    _deviceStreamController.close();
  }
}
