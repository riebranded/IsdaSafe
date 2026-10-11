import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';

/// The `Notification` constructor (https://notifications.spec.whatwg.org/).
JSFunction? get _notification =>
    globalContext.getProperty<JSFunction?>('Notification'.toJS);

bool isSupported() => _notification != null;

String permission() {
  final notification = _notification;
  if (notification == null) return 'denied';
  return notification.getProperty<JSString>('permission'.toJS).toDart;
}

Future<String> requestPermission() async {
  final notification = _notification;
  if (notification == null) return 'denied';
  try {
    final result = await notification
        .callMethod<JSPromise<JSString>>('requestPermission'.toJS)
        .toDart;
    return result.toDart;
  } catch (e) {
    debugPrint('BrowserNotifications: requestPermission failed $e');
    return permission();
  }
}

void show(String title, String body) {
  final notification = _notification;
  if (notification == null || permission() != 'granted') return;
  try {
    notification.callAsConstructor<JSObject>(
      title.toJS,
      {'body': body, 'icon': 'icons/Icon-192.png'}.jsify(),
    );
  } catch (e) {
    debugPrint('BrowserNotifications: show failed $e');
  }
}
