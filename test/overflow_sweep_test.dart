import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:isdasafev2/l10n/language_provider.dart';
import 'package:isdasafev2/l10n/tr.dart';
import 'package:isdasafev2/providers/notification_provider.dart';
import 'package:isdasafev2/providers/pond_provider.dart';
import 'package:isdasafev2/providers/theme_provider.dart';
import 'package:isdasafev2/screens/app_shell.dart';
import 'package:isdasafev2/screens/auth/login_screen.dart';
import 'package:isdasafev2/screens/auth/otp_verification_screen.dart';
import 'package:isdasafev2/screens/auth/register_screen.dart';
import 'package:isdasafev2/screens/auth/reset_password_screen.dart';
import 'package:isdasafev2/theme/app_theme.dart';

import 'support/fake_notification_repository.dart';
import 'support/fake_pond_repository.dart';

/// Renders every main screen at small-phone through desktop sizes, with
/// enlarged text and in Tagalog (longer strings), and fails on any layout
/// overflow or framework error so cramped rows and clipped labels are
/// caught before a user sees the yellow-and-black stripes.
void main() {
  late GeolocatorPlatform originalGeolocator;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (call) async => call.method == 'getAll' ? <String, Object>{} : null,
        );
    await Supabase.initialize(
      url: 'http://localhost',
      publishableKey: 'test-key',
    );
    dotenv.loadFromString(envString: 'GOOGLE_PLACES_KEY=');
    await _loadRealFonts();
    originalGeolocator = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = _DeniedGeolocator();
  });

  tearDownAll(() => GeolocatorPlatform.instance = originalGeolocator);

  const sizes = <String, Size>{
    'small phone': Size(320, 568),
    'phone': Size(390, 844),
    'tablet': Size(800, 1280),
    'desktop': Size(1280, 800),
  };
  const textScales = [1.0, 1.3];
  const languages = [AppLanguage.english, AppLanguage.tagalog];

  final sourceLine = RegExp(r'lib[/\\][\w/\\]+\.dart:\d+');

  Widget wrap(Widget home, double textScale, LanguageProvider language) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => PondProvider(repository: FakePondRepository()),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              NotificationProvider(repository: FakeNotificationRepository()),
        ),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider.value(value: language),
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    );
  }

  /// Runs [body] while recording every framework error tagged with the step
  /// it happened in, restores the handler, then fails with the full list.
  Future<void> sweep(
    WidgetTester tester,
    Future<void> Function(void Function(String) step) body,
  ) async {
    final found = <String>{};
    var current = 'start';
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      final where = sourceLine.firstMatch(details.toString())?.group(0);
      final message = details.exceptionAsString().split('\n').first;
      found.add('[$current] $message @ ${where ?? '?'}');
    };
    try {
      await body((name) => current = name);
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
    } finally {
      FlutterError.onError = previous;
    }
    expect(found, isEmpty, reason: found.join('\n'));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> tapIfPresent(WidgetTester tester, Finder finder) async {
    if (finder.evaluate().isEmpty) return;
    await tester.tap(finder.last, warnIfMissed: false);
    await settle(tester);
  }

  Future<LanguageProvider> setUpView(
    WidgetTester tester,
    Size size,
    AppLanguage language,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final lang = LanguageProvider();
    await lang.setLanguage(language);
    addTearDown(() => lang.setLanguage(AppLanguage.english));
    return lang;
  }

  for (final language in languages) {
    for (final scale in textScales) {
      for (final entry in sizes.entries) {
        final label = '${entry.key} x$scale ${language.name}';

        testWidgets('no overflow: app shell tabs ($label)', (tester) async {
          final lang = await setUpView(tester, entry.value, language);
          await sweep(tester, (step) async {
            step('Dashboard');
            await tester.pumpWidget(wrap(const AppShell(), scale, lang));
            await settle(tester);
            step('Add pond dialog');
            await tapIfPresent(tester, find.byIcon(Icons.add));
            if (find.byType(Dialog).evaluate().isNotEmpty) {
              Navigator.of(tester.element(find.byType(Dialog).last)).pop();
              await settle(tester);
            }
            for (final tab in ['Map', 'Analytics', 'Settings']) {
              step(tab);
              await tapIfPresent(tester, find.text(tab.tr));
            }
            step('Notifications');
            await tapIfPresent(
              tester,
              find.byIcon(Icons.notifications_outlined),
            );
            await tapIfPresent(tester, find.text('Notifications'.tr));
            step('Pond A');
            await tapIfPresent(tester, find.text('Dashboard'.tr));
            await tapIfPresent(tester, find.text('Pond A'));
          });
        });

        testWidgets('no overflow: auth screens ($label)', (tester) async {
          final lang = await setUpView(tester, entry.value, language);
          final screens = <String, Widget>{
            'login': const LoginScreen(),
            'register': const RegisterScreen(),
            'reset': const ResetPasswordScreen(),
            'otp': const OtpVerificationScreen(
              fullName: 'Juan Dela Cruz',
              email: 'juan@example.com',
              phone: '+639171234567',
            ),
          };
          await sweep(tester, (step) async {
            for (final s in screens.entries) {
              step(s.key);
              await tester.pumpWidget(wrap(s.value, scale, lang));
              await settle(tester);
            }
          });
        });
      }
    }
  }
}

/// flutter_test draws text in a placeholder font whose glyphs are 1em
/// squares, far wider than the app's real fonts, which turns every label
/// into a false overflow. Register the SDK's Roboto under each family the
/// theme asks for (Lexend / Source Sans 3 via google_fonts, which can't
/// download in tests) so widths are close to what a phone renders.
Future<void> _loadRealFonts() async {
  final flutterRoot =
      Platform.environment['FLUTTER_ROOT'] ??
      File(
        Platform.resolvedExecutable,
      ).parent.parent.parent.parent.parent.parent.path;
  final dir = '$flutterRoot/bin/cache/artifacts/material_fonts';
  final regular = File('$dir/roboto-regular.ttf').readAsBytesSync();
  final medium = File('$dir/roboto-medium.ttf').readAsBytesSync();
  final bold = File('$dir/roboto-bold.ttf').readAsBytesSync();
  // google_fonts styles name the downloaded file's family first and the
  // plain family as fallback, which is what these fill in.
  const families = ['Roboto', 'Lexend', 'SourceSans3'];
  for (final family in families) {
    final loader = FontLoader(family);
    for (final bytes in [regular, medium, bold]) {
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

class _DeniedGeolocator extends GeolocatorPlatform {
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.deniedForever;

  @override
  Future<bool> isLocationServiceEnabled() async => false;
}
