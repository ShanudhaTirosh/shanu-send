import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

class KdeConnectService {
  static const int udpPort = 1716;
  static const int tcpPort = 1716;

  RawDatagramSocket? _udpSocket;
  final StreamController<Map<String, dynamic>> _packetController = StreamController.broadcast();

  Stream<Map<String, dynamic>> get packetStream => _packetController.stream;

  Future<void> startDiscovery(String deviceName, String deviceId) async {
    try {
      _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort);
      _udpSocket?.broadcastEnabled = true;

      _udpSocket?.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _udpSocket?.receive();
          if (datagram != null) {
            final message = utf8.decode(datagram.data);
            try {
              final Map<String, dynamic> packet = jsonDecode(message);
              _packetController.add(packet);
            } catch (e) {
              debugPrint('KDE Connect packet parse error: $e');
            }
          }
        }
      });

      // Broadcast identity beacon
      _sendBroadcastIdentity(deviceName, deviceId);
    } catch (e) {
      debugPrint('KDE Connect UDP bind error: $e');
    }
  }

  void _sendBroadcastIdentity(String deviceName, String deviceId) {
    final identityPacket = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'type': 'kdeconnect.identity',
      'body': {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'deviceType': 'phone',
        'protocolVersion': 7,
        'incomingCapabilities': [
          'kdeconnect.battery',
          'kdeconnect.clipboard',
          'kdeconnect.mousepad',
          'kdeconnect.mpris',
          'kdeconnect.notifications',
          'kdeconnect.ping',
          'kdeconnect.presenter',
          'kdeconnect.runcommand',
          'kdeconnect.sms',
          'kdeconnect.systemvolume',
          'kdeconnect.lockdevice',
        ],
        'outgoingCapabilities': [
          'kdeconnect.battery',
          'kdeconnect.clipboard',
          'kdeconnect.mousepad',
          'kdeconnect.mpris',
          'kdeconnect.notifications',
          'kdeconnect.ping',
          'kdeconnect.presenter',
          'kdeconnect.runcommand',
          'kdeconnect.sms',
          'kdeconnect.systemvolume',
          'kdeconnect.lockdevice',
        ],
        'tcpPort': tcpPort,
      }
    };

    final bytes = utf8.encode(jsonEncode(identityPacket));
    _udpSocket?.send(bytes, InternetAddress('255.255.255.255'), udpPort);
  }

  void stop() {
    _udpSocket?.close();
    _packetController.close();
  }
}
