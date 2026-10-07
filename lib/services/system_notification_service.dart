import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/app_notification.dart';

/// Posts pond-verification updates to the operating system's notification
/// tray (Android, iOS, macOS, Linux, Windows), on top of the in-app toast.
///
/// These are local notifications fed by the realtime notifications stream, so
/// they appear while the app is running (foreground or background) — not once
/// the process is gone. That would need server push (FCM/APNs).
///
/// Every call is best-effort: a platform without support, or a denied
/// permission, must never break the app.
class SystemNotificationService {
  SystemNotificationService._();

  static final instance = SystemNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _channelId = 'pond_verification';
  static const _channelName = 'Pond verification';

  Future<void> init() async {
    if (kIsWeb || _ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
          windows: WindowsInitializationSettings(
            appName: 'IsdaSafe',
            appUserModelId: 'com.isdasafe.app',
            guid: '8f1d6c52-3b0e-4a7e-9a55-2c4d1f7b9e30',
          ),
        ),
      );
      // Android 13+ needs a runtime grant; a no-op elsewhere.
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (e) {
      debugPrint('SystemNotificationService: init failed $e');
    }
  }

  /// Shows [notification] in the system tray if it's a pond verification
  /// update.
  Future<void> showPondUpdate(AppNotification notification) async {
    if (!_ready || !notification.isPondVerification) return;
    try {
      await _plugin.show(
        id: notification.id.hashCode & 0x7fffffff,
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Updates on the review of your ponds',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('SystemNotificationService: show failed $e');
    }
  }
}
