import 'package:ex_kit/ex.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationModel {
  const NotificationModel({
    required this.title,
    required this.body,
    this.payload,
    this.id,
  });

  final int? id;
  final String title;
  final String body;
  final String? payload;
}

mixin AppNotification {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static void Function(String? payload)? _onNotificationTap;

  static Future<void> initialize({void Function(String? payload)? onNotificationTap}) async {
    _onNotificationTap = onNotificationTap;

    const initializationSettings = InitializationSettings(
      macOS: DarwinInitializationSettings(),
    );

    await _plugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (response) => _onNotificationTap?.call(response.payload),
    );
  }

  static void registerNotificationTapHandler(void Function(String? payload)? handler) {
    _onNotificationTap = handler;
  }

  static Future<bool> requestPermissions() async {
    final macOSGranted = await _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
          critical: true,
        );
    return macOSGranted ?? true;
  }

  static Future<void> show(NotificationModel model) async {
    const notificationDetails = NotificationDetails(
      macOS: DarwinNotificationDetails(),
    );

    await _plugin.show(
      ExRandom.between(100000, 10000000),
      model.title,
      model.body,
      notificationDetails,
      payload: model.payload,
    );
  }
}
