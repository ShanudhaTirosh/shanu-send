import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

class ShanuConnectService {
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
              // Not part of the wire protocol — added locally so consumers
              // can reply to whoever actually sent this packet.
              packet['_senderIp'] = datagram.address.address;
              if (!_packetController.isClosed) {
                _packetController.add(packet);
              }
            } catch (e) {
              debugPrint('ShanuConnect packet parse error: $e');
            }
          }
        }
      });

      // Broadcast identity beacon
      _sendBroadcastIdentity(deviceName, deviceId);
    } catch (e) {
      debugPrint('ShanuConnect UDP bind error: $e');
    }
  }

  void _sendBroadcastIdentity(String deviceName, String deviceId) {
    final identityPacket = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'type': 'shanuconnect.identity',
      'body': {
        'deviceId': deviceId,
        'deviceName': deviceName,
        'deviceType': 'phone',
        'protocolVersion': 7,
        'incomingCapabilities': [
          'shanuconnect.battery',
          'shanuconnect.clipboard',
          'shanuconnect.mousepad',
          'shanuconnect.mpris',
          'shanuconnect.notifications',
          'shanuconnect.notifications.reply',
          'shanuconnect.ping',
          'shanuconnect.presenter',
          'shanuconnect.runcommand',
          'shanuconnect.sms',
          'shanuconnect.systemvolume',
          'shanuconnect.lockdevice',
          'shanuconnect.telephony',
          'shanuconnect.sftp',
        ],
        'outgoingCapabilities': [
          'shanuconnect.battery',
          'shanuconnect.clipboard',
          'shanuconnect.mousepad',
          'shanuconnect.mpris',
          'shanuconnect.notifications',
          'shanuconnect.notifications.reply',
          'shanuconnect.ping',
          'shanuconnect.presenter',
          'shanuconnect.runcommand',
          'shanuconnect.sms',
          'shanuconnect.systemvolume',
          'shanuconnect.lockdevice',
          'shanuconnect.telephony',
          'shanuconnect.sftp',
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
      debugPrint('ShanuConnect packet send error: $e');
    }
  }

  void sendNotificationReply(String notificationId, String replyMessage, [String? targetIp]) {
    final packet = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'type': 'shanuconnect.notifications.reply',
      'body': {
        'notificationId': notificationId,
        'replyMessage': replyMessage,
      }
    };
    sendPacket(packet, targetIp);
  }

  void sendTelephonyCallAction(String action, String phoneNumber, [String? targetIp]) {
    final packet = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'type': 'shanuconnect.telephony',
      'body': {
        'action': action,
        'phoneNumber': phoneNumber,
      }
    };
    sendPacket(packet, targetIp);
  }

  void sendSftpRequest(String path, [String? targetIp]) {
    final packet = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'type': 'shanuconnect.sftp',
      'body': {
        'path': path,
      }
    };
    sendPacket(packet, targetIp);
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
      'type': 'shanuconnect.mousepad',
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
      'type': 'shanuconnect.mpris',
      'body': body,
    };
    sendPacket(packet, targetIp);
  }

  void sendRunCommand(String command, [String? targetIp]) {
    final packet = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'type': 'shanuconnect.runcommand',
      'body': {
        'key': command,
      }
    };
    sendPacket(packet, targetIp);
  }

  void sendPresenterSlide({required bool next, String? targetIp}) {
    final packet = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'type': 'shanuconnect.presenter',
      'body': {
        if (next) 'next': true else 'prev': true,
      }
    };
    sendPacket(packet, targetIp);
  }

  void sendLockDevice({required bool lock, String? targetIp}) {
    final packet = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'type': 'shanuconnect.lockdevice',
      'body': {
        'isLocked': lock,
      }
    };
    sendPacket(packet, targetIp);
  }

  void sendClipboardText(String text, [String? targetIp]) {
    final packet = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'type': 'shanuconnect.clipboard',
      'body': {
        'content': text,
      }
    };
    sendPacket(packet, targetIp);
  }

  void sendSystemVolume(double volume, [String? targetIp]) {
    final packet = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'type': 'shanuconnect.systemvolume',
      'body': {
        'volume': volume.toInt(),
      }
    };
    sendPacket(packet, targetIp);
  }

  /// [deviceId] must be this device's real persisted ID (see
  /// DeviceIdentityService) — sending a hardcoded/shared ID here defeats the
  /// whole point of a trusted-device allow-list, since every install would
  /// look identical.
  ///
  /// [sasCode] carries the 6-digit code being confirmed, shown on both
  /// screens. [ack] marks this packet as a reply confirming (or rejecting,
  /// when [pair] is false) a code the sender saw on their own screen.
  void sendPairing({
    required bool pair,
    required String deviceId,
    String? sasCode,
    bool ack = false,
    String? targetIp,
  }) {
    final packet = {
      'id': DateTime.now().millisecondsSinceEpoch,
      'type': 'shanuconnect.pair',
      'body': {
        'pair': pair,
        'deviceId': deviceId,
        if (sasCode != null) 'sasCode': sasCode,
        'ack': ack,
      }
    };
    sendPacket(packet, targetIp);
  }

  void stop() {
    _udpSocket?.close();
    _packetController.close();
  }
}

typedef KdeConnectService = ShanuConnectService;
