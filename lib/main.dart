import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'providers/pond_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  final googleWebClientId = dotenv.env['GOOGLE_WEB_CLIENT_ID'];
  final googleIosClientId = dotenv.env['GOOGLE_IOS_CLIENT_ID'];
  // The web plugin requires `clientId` (the web OAuth client) and rejects
  // `serverClientId` outright; native platforms are the opposite — they use
  // `serverClientId` (the web client) to mint an ID token Supabase can verify.
  await GoogleSignIn.instance.initialize(
    clientId: kIsWeb
        ? ((googleWebClientId?.isNotEmpty ?? false) ? googleWebClientId : null)
        : ((googleIosClientId?.isNotEmpty ?? false) ? googleIosClientId : null),
    serverClientId: kIsWeb
        ? null
        : ((googleWebClientId?.isNotEmpty ?? false) ? googleWebClientId : null),
  );

  runApp(
    ChangeNotifierProvider(
      create: (_) => PondProvider(),
      child: const IsdaSafeApp(),
    ),
  );
}
