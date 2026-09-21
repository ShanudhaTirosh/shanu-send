import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  final StreamController<String> _actionController = StreamController<String>.broadcast();
  Stream<String> get actionStream => _actionController.stream;

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Request permissions on Android 13+ / iOS
    if (!kIsWeb) {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Open ShanuSend');

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: darwinSettings,
      macOS: darwinSettings,
      linux: linuxSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          final action = '${response.actionId ?? "click"}:${response.payload}';
          _actionController.add(action);
        }
      },
    );

    _isInitialized = true;
    debugPrint('Native NotificationService initialized successfully');
  }

  Future<void> showIncomingTransferAlert({
    required String senderAlias,
    required int fileCount,
    required String sessionId,
  }) async {
    await initialize();

    final title = 'Incoming File Request from $senderAlias';
    final body = '$senderAlias wants to send $fileCount file(s). Tap to accept or decline.';

    const androidDetails = AndroidNotificationDetails(
      'shanusend_transfers',
      'File Transfers',
      channelDescription: 'Alerts for incoming LocalSend and AirDrop file transfers',
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
      actions: [
        AndroidNotificationAction('accept', 'Accept', showsUserInterface: true),
        AndroidNotificationAction('decline', 'Decline', showsUserInterface: false),
      ],
    );

    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentSound: true,
      presentBadge: true,
      categoryIdentifier: 'TRANSFER_REQUEST',
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    await _notifications.show(
      sessionId.hashCode,
      title,
      body,
      notificationDetails,
      payload: sessionId,
    );
  }

  Future<void> showPairingAlert({
    required String deviceName,
    required String pin,
    required String deviceId,
  }) async {
    await initialize();

    final title = 'ShanuConnect Pairing Request';
    final body = '$deviceName (PIN: $pin) wants to pair for remote control.';

    const androidDetails = AndroidNotificationDetails(
      'shanusend_pairing',
      'Device Pairing',
      channelDescription: 'Alerts for ShanuConnect remote control pairing',
      importance: Importance.max,
      priority: Priority.high,
      actions: [
        AndroidNotificationAction('approve_pair', 'Approve Pairing', showsUserInterface: true),
        AndroidNotificationAction('reject_pair', 'Reject', showsUserInterface: false),
      ],
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );

    await _notifications.show(
      deviceId.hashCode,
      title,
      body,
      notificationDetails,
      payload: '$deviceId:$pin',
    );
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    await initialize();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'shanusend_general',
        'General Alerts',
        importance: Importance.defaultImportance,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );
  }
}
