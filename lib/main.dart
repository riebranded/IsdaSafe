import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'providers/pond_provider.dart';
import 'providers/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

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
