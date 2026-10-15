import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_notification.dart';
import 'browser_notifications/browser_notifications.dart';

/// Posts pond-verification updates to the operating system's notification
/// tray (Android, iOS, macOS, Linux, Windows), or as browser notifications on
/// the web, on top of the in-app toast. The user turns them on or off in
/// Settings ([setEnabled]).
///
/// These are local notifications fed by the realtime notifications stream, so
/// they appear while the app is running (foreground or background) — not once
/// the process is gone. That would need server push (FCM/APNs).
///
/// Every call is best-effort: a platform without support, or a denied
/// permission, must never break the app.
class SystemNotificationService extends ChangeNotifier {
  SystemNotificationService._();

  static final instance = SystemNotificationService._();

  static const _prefsKey = 'push_notifications_enabled';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// The user's choice. On the web it's off until they turn it on, since the
  /// browser only asks for permission in response to a tap.
  bool _wanted = !kIsWeb;

  /// The OS or browser refused permission.
  bool _denied = false;

  /// Whether this platform can show notifications at all.
  bool get isSupported => kIsWeb ? BrowserNotifications.isSupported : _ready;

  /// Notifications are on and allowed.
  bool get isEnabled => isSupported && _wanted && !isBlocked;

  /// Permission was refused, so they can only be allowed again from the
  /// browser's or phone's own settings.
  bool get isBlocked =>
      kIsWeb ? BrowserNotifications.permission == 'denied' : _denied;

  /// Turns notifications on (asking for permission if needed) or off.
  /// Returns the resulting [isEnabled].
  Future<bool> setEnabled(bool enabled) async {
    if (enabled) {
      if (kIsWeb) {
        if (BrowserNotifications.permission != 'granted') {
          await BrowserNotifications.requestPermission();
        }
      } else {
        await _requestPermission();
      }
    }
    _wanted = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, enabled);
    } catch (_) {}
    notifyListeners();
    return isEnabled;
  }

  Future<void> _requestPermission() async {
    final granted = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _denied = granted == false;
  }

  static const _channelId = 'pond_verification';
  static const _channelName = 'Pond verification';

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _wanted = prefs.getBool(_prefsKey) ?? _wanted;
    } catch (_) {}
    if (kIsWeb || _ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
          macOS: DarwinInitializationSettings(),
          linux: LinuxInitializationSettings(defaultActionName: 'Open'),
          windows: WindowsInitializationSettings(
            appName: 'Isda Safe',
            appUserModelId: 'com.isdasafe.app',
            guid: '8f1d6c52-3b0e-4a7e-9a55-2c4d1f7b9e30',
          ),
        ),
      );
      // Created up front so push notifications (FCM), which name them, can
      // use them even before the app has shown one itself.
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: 'Updates on the review of your ponds',
          importance: Importance.high,
        ),
      );
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _alertChannelId,
          _alertChannelName,
          description: 'When a pond reading enters warning or danger',
          importance: Importance.max,
        ),
      );
      // Android 13+ needs a runtime grant; a no-op elsewhere.
      if (_wanted) await _requestPermission();
      _ready = true;
    } catch (e) {
      debugPrint('SystemNotificationService: init failed $e');
    }
  }

  /// Shows a push that arrived while the app is open (Android only shows
  /// pushes by itself when it isn't), tagged like the push so it never
  /// shows twice.
  Future<void> showPush({
    required String tag,
    required String title,
    required String body,
  }) async {
    if (!isEnabled || kIsWeb) return;
    try {
      await _plugin.show(
        id: 0,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _alertChannelId,
            _alertChannelName,
            channelDescription: 'When a pond reading enters warning or danger',
            importance: Importance.max,
            priority: Priority.high,
            tag: tag,
          ),
        ),
      );
    } catch (e) {
      debugPrint('SystemNotificationService: showPush failed $e');
    }
  }

  /// The test from Settings shown right here: in the browser (which has no
  /// Firebase push), a browser notification.
  void showWebTest({required String title, required String body}) {
    if (!isEnabled || !kIsWeb) return;
    BrowserNotifications.show(title, body);
  }

  /// Water alerts get their own Android channel, so they can be given a
  /// different sound (or silenced) separately in the phone's settings.
  static const _alertChannelId = 'water_alerts';
  static const _alertChannelName = 'Pond water alerts';

  /// Shows [notification] in the system tray if it's a pond verification
  /// update, about a device transfer, or a water alert.
  Future<void> showPondUpdate(AppNotification notification) async {
    if (!isEnabled ||
        !(notification.isPondVerification ||
            notification.isDeviceTransfer ||
            notification.isWaterAlert)) {
      return;
    }
    if (kIsWeb) {
      BrowserNotifications.show(notification.title, notification.body);
      return;
    }
    final alert = notification.isWaterAlert;
    try {
      // Tagged with the notification's id (and id 0), like the push for it:
      // when both arrive, Android shows one.
      await _plugin.show(
        id: 0,
        title: notification.title,
        body: notification.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            alert ? _alertChannelId : _channelId,
            alert ? _alertChannelName : _channelName,
            channelDescription: alert
                ? 'When a pond reading enters warning or danger'
                : 'Updates on the review of your ponds',
            importance: notification.type == 'water_alert_cleared'
                ? Importance.defaultImportance
                : Importance.max,
            priority: Priority.high,
            // A long body ("Turn on the aerators now...") shows in full.
            styleInformation: BigTextStyleInformation(notification.body),
            tag: notification.id,
          ),
          iOS: const DarwinNotificationDetails(),
          macOS: const DarwinNotificationDetails(),
          linux: const LinuxNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('SystemNotificationService: show failed $e');
    }
  }
}
