import 'browser_notifications_stub.dart'
    if (dart.library.js_interop) 'browser_notifications_web.dart'
    as impl;

/// The browser's Notification API (web build only): lets the app show
/// notifications outside the page while its tab is open. Elsewhere
/// [isSupported] is false and everything is a no-op.
abstract final class BrowserNotifications {
  static bool get isSupported => impl.isSupported();

  /// 'granted', 'denied' or 'default' (not asked yet).
  static String get permission => impl.permission();

  /// Asks the user for permission; returns the resulting [permission].
  static Future<String> requestPermission() => impl.requestPermission();

  static void show(String title, String body) => impl.show(title, body);
}
