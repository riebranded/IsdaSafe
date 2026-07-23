import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'providers/pond_provider.dart';
import 'providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  // Used only for phone OTP (see AuthService.sendFirebasePhoneOtp) —
  // Supabase remains the app's actual identity/session provider.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Web's sign-in flow (AuthService.signInWithGoogle) goes entirely through
  // Supabase's OAuth redirect and never touches the GoogleSignIn plugin, so
  // initializing it on web only serves to arm Google Identity Services' auto
  // One Tap prompt — which throws an uncaught JS TypeError
  // (`Cannot read properties of null (reading 'removeChild')`) on some
  // pages. Skip it there; native platforms still need it for
  // AuthService._authenticateWithGoogle.
  if (!kIsWeb) {
    final googleIosClientId = dotenv.env['GOOGLE_IOS_CLIENT_ID'];
    final googleWebClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];
    await GoogleSignIn.instance.initialize(
      clientId: (googleIosClientId?.isNotEmpty ?? false) ? googleIosClientId : null,
      serverClientId: (googleWebClientId?.isNotEmpty ?? false) ? googleWebClientId : null,
    );
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PondProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const IsdaSafeApp(),
    ),
  );
}
