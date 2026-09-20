import 'dart:async';
import 'dart:io';
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
  bool _isScanning = false;

  Stream<List<DeviceDto>> get deviceStream => _deviceStreamController.stream;
  List<DeviceDto> get devices => List.unmodifiable(_discoveredDevices);
  bool get isScanning => _isScanning;

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
    _deviceStreamController.close();
  }
}
