import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'l10n/language_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/pond_provider.dart';
import 'providers/theme_provider.dart';
import 'services/auth_service.dart';
import 'services/push_service.dart';
import 'services/system_notification_service.dart';
import 'services/usb_sensor/device_claim.dart';
import 'services/usb_sensor/pond_readings_store.dart';
import 'services/usb_sensor/usb_sensor_hub.dart';

//Test

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  debugPrint(
    'BUILD MARKER: place-search logging v1, '
    'GOOGLE_PLACES_KEY ${(dotenv.env['GOOGLE_PLACES_KEY'] ?? '').isEmpty ? 'EMPTY' : 'set'}',
  );

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  AuthService.listenForPasswordRecovery();
  await SystemNotificationService.instance.init();
  // Push (Android): registered while signed in with notifications on.
  await PushService.instance.init();
  void syncPush() => PushService.instance.sync(
    wanted:
        AuthService.currentUser != null &&
        SystemNotificationService.instance.isEnabled,
  );
  AuthService.onAuthStateChange.listen((_) => syncPush());
  SystemNotificationService.instance.addListener(syncPush);
  // Reopen the IsdaSafe device's USB port if it was connected on an earlier
  // visit and is plugged in (web only; never prompts).
  unawaited(UsbSensorHub.instance.reconnect());

  if (!kIsWeb) {
    final googleIosClientId = dotenv.env['GOOGLE_IOS_CLIENT_ID'];
    final googleWebClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];
    debugPrint(
      'GoogleSignIn init: serverClientId=$googleWebClientId '
      'clientId=$googleIosClientId',
    );
    await GoogleSignIn.instance.initialize(
      clientId: (googleIosClientId?.isNotEmpty ?? false)
          ? googleIosClientId
          : null,
      serverClientId: (googleWebClientId?.isNotEmpty ?? false)
          ? googleWebClientId
          : null,
    );
  }

  // A device's QR label opens the site with ?claim=...; pairing is offered
  // once signed in (see AppShell).
  PendingClaimLink.captureFrom(Uri.base);

  final pondProvider = PondProvider();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: pondProvider),
        // A verification result arrives as a notification; re-fetch ponds so
        // their status badge updates live.
        ChangeNotifierProvider(
          create: (_) => NotificationProvider(
            onNewNotification: (n) {
              if (n.isPondVerification) {
                pondProvider.refresh();
                SystemNotificationService.instance.showPondUpdate(n);
              } else if (n.isDeviceTransfer) {
                // A device left or joined this account.
                PondReadingsStore.instance.refresh();
                SystemNotificationService.instance.showPondUpdate(n);
              } else if (n.isWaterAlert) {
                // The reading behind it: show it without waiting a minute.
                PondReadingsStore.instance.refresh();
                SystemNotificationService.instance.showPondUpdate(n);
              }
            },
          ),
        ),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ],
      child: const IsdaSafeApp(),
    ),
  );
}
