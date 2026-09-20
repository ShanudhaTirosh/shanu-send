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

  void sendPacket(Map<String, dynamic> packet, [String? targetIp]) {
    try {
      final bytes = utf8.encode(jsonEncode(packet));
      final ip = targetIp != null ? InternetAddress(targetIp) : InternetAddress('255.255.255.255');
      _udpSocket?.send(bytes, ip, udpPort);
    } catch (e) {
      debugPrint('KDE Connect packet send error: $e');
    }
  }

  void sendMousepad(double dx, double dy, {String? click, String? targetIp}) {
    final Map<String, dynamic> body = {
      'dx': dx,
      'dy': dy,
    };
    if (click != null) {
      body['click'] = click;
    }
    final packet = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'type': 'kdeconnect.mousepad',
      'body': body,
    };
    sendPacket(packet, targetIp);
  }

  void sendMprisCommand(String action, {double? volume, String? targetIp}) {
    final Map<String, dynamic> body = {
      'action': action,
    };
    if (volume != null) {
      body['volume'] = volume.toInt();
    }
    final packet = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'type': 'kdeconnect.mpris',
      'body': body,
    };
    sendPacket(packet, targetIp);
  }

  void sendRunCommand(String command, [String? targetIp]) {
    final packet = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'type': 'kdeconnect.runcommand.request',
      'body': {
        'key': command,
      }
    };
    sendPacket(packet, targetIp);
  }

  void sendPresenterSlide({required bool next, String? targetIp}) {
    final packet = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'type': 'kdeconnect.presenter',
      'body': {
        if (next) 'next': true else 'prev': true,
      }
    };
    sendPacket(packet, targetIp);
  }

  void stop() {
    _udpSocket?.close();
    _packetController.close();
  }
}

