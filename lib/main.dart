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
import 'services/system_notification_service.dart';

//Test

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  AuthService.listenForPasswordRecovery();
  await SystemNotificationService.instance.init();

  if (!kIsWeb) {
    final googleIosClientId = dotenv.env['GOOGLE_IOS_CLIENT_ID'];
    final googleWebClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];
    await GoogleSignIn.instance.initialize(
      clientId: (googleIosClientId?.isNotEmpty ?? false)
          ? googleIosClientId
          : null,
      serverClientId: (googleWebClientId?.isNotEmpty ?? false)
          ? googleWebClientId
          : null,
    );
  }

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
