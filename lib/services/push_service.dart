import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'system_notification_service.dart';

/// How "Send a test notification" went ([PushService.sendTest]).
enum TestPushResult {
  /// On its way; arrives in [PushService.testDelay].
  scheduled,

  /// Push isn't available here (not Android, or Firebase didn't start).
  unsupported,

  /// This phone couldn't register for push (notifications off or blocked).
  notRegistered,

  /// The server has no Firebase key (FCM_SERVICE_ACCOUNT) yet.
  notConfigured,

  /// Couldn't reach the server.
  failed,
}

/// Push notifications through Firebase Cloud Messaging (Android only for
/// now), so pond alerts and updates reach the phone even when IsdaSafe isn't
/// running. While it is running, the same notifications also arrive over
/// realtime and [SystemNotificationService] shows them; both use the same
/// tag, so Android shows each one once.
///
/// This phone's FCM token is stored with the signed-in account
/// (`register_push_token()`); the `send-push` edge function sends to every
/// token of the notification's owner. It's registered while signed in with
/// notifications switched on in Settings, and removed on sign-out or when
/// they're switched off ([sync]).
///
/// Needs android/app/google-services.json (Firebase project); without it
/// Firebase fails to start and push is simply off.
class PushService {
  PushService._();

  static final instance = PushService._();

  bool _ready = false;
  String? _registered;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether this platform gets push notifications at all.
  bool get isSupported => _ready;

  /// Whether Settings can send a test notification here: through Firebase on
  /// Android, as a browser notification on the web.
  bool get canTest => _ready || kIsWeb;

  /// How long [sendTest] waits before pushing, so there's time to leave the
  /// app and see it arrive like a real alert.
  static const testDelay = Duration(seconds: 5);

  SupabaseClient get _client => Supabase.instance.client;

  /// Starts Firebase. Call once at startup; never throws.
  Future<void> init() async {
    if (!_supported || _ready) return;
    try {
      await Firebase.initializeApp();
      // A new token (reinstall, data cleared, ...) replaces the old one.
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        if (_registered != null) unawaited(_register(token));
      });
      // Android doesn't show a push while the app is open. Real ones also
      // arrive over realtime (and are shown from there); a test push only
      // comes this way, so show it here.
      FirebaseMessaging.onMessage.listen((message) {
        final note = message.notification;
        if (message.data['type'] != 'test_push' || note == null) return;
        unawaited(
          SystemNotificationService.instance.showPush(
            tag: message.data['tag'] ?? 'test_push',
            title: note.title ?? '',
            body: note.body ?? '',
          ),
        );
      });
      _ready = true;
    } catch (e) {
      debugPrint('PushService: Firebase init failed $e');
    }
  }

  /// Registers this phone for push when [wanted] (signed in, notifications
  /// on), or removes it otherwise. Safe to call repeatedly.
  Future<void> sync({required bool wanted}) async {
    if (!_ready) return;
    if (!wanted) return unregister();
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token != _registered) await _register(token);
    } catch (e) {
      debugPrint('PushService: getToken failed $e');
    }
  }

  Future<void> _register(String token) async {
    if (_client.auth.currentUser == null) return;
    try {
      await _client.rpc(
        'register_push_token',
        params: {'p_token': token, 'p_platform': 'android'},
      );
      _registered = token;
      debugPrint('PushService: registered');
    } catch (e) {
      debugPrint('PushService: register failed $e');
    }
  }

  /// Asks the server to push a test notification to this account's phones
  /// after [testDelay]. Makes sure this phone is registered first.
  Future<TestPushResult> sendTest() async {
    if (kIsWeb) return _sendWebTest();
    if (!_ready) return TestPushResult.unsupported;
    if (!SystemNotificationService.instance.isEnabled) {
      return TestPushResult.notRegistered;
    }
    await sync(wanted: true);
    if (_registered == null) return TestPushResult.notRegistered;
    try {
      final response = await _client.functions.invoke(
        'send-test-push',
        body: {'delay_seconds': testDelay.inSeconds},
      );
      final status = (response.data as Map?)?['status'];
      debugPrint('PushService: test push -> $status');
      return switch (status) {
        'scheduled' => TestPushResult.scheduled,
        'not_configured' => TestPushResult.notConfigured,
        'no_devices' => TestPushResult.notRegistered,
        _ => TestPushResult.failed,
      };
    } catch (e) {
      debugPrint('PushService: test push failed $e');
      return TestPushResult.failed;
    }
  }

  /// The browser has no Firebase push: shows a browser notification after
  /// [testDelay] instead, so there's time to switch tabs and see it arrive.
  TestPushResult _sendWebTest() {
    final notifications = SystemNotificationService.instance;
    if (!notifications.isEnabled) return TestPushResult.notRegistered;
    unawaited(
      Future.delayed(
        testDelay,
        () => notifications.showWebTest(
          title: 'IsdaSafe test notification',
          body: 'Notifications work in this browser.',
        ),
      ),
    );
    return TestPushResult.scheduled;
  }

  /// Stops push to this phone for the signed-in account. Call before
  /// signing out (it needs the session).
  Future<void> unregister() async {
    final token = _registered;
    if (!_ready || token == null) return;
    _registered = null;
    try {
      await _client.rpc('unregister_push_token', params: {'p_token': token});
    } catch (e) {
      debugPrint('PushService: unregister failed $e');
    }
  }
}
