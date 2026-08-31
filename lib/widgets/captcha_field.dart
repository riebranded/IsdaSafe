import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// `cloudflare_turnstile` renders through `flutter_inappwebview` on native
/// platforms, which only ships Android/iOS/Windows/macOS implementations —
/// no Linux. Mirrors `location_picker_map.dart`'s `isMapViewSupported` gate
/// for the same reason: `kIsWeb` short-circuits before `Platform.*` is ever
/// evaluated, so this is safe to read on web too.
bool get isCaptchaSupported =>
    kIsWeb ||
    Platform.isAndroid ||
    Platform.isIOS ||
    Platform.isWindows ||
    Platform.isMacOS;

/// Renders a Cloudflare Turnstile challenge and reports the current
/// verification token up to [onTokenChanged] — null whenever there isn't a
/// currently-valid one (not yet solved, expired, or errored). Callers gate
/// their submit button on that value and pass the last non-null one through
/// as `captchaToken` to the relevant `AuthService` call.
///
/// Tokens are single-use, so callers must call [CaptchaFieldState.reset]
/// after every submit attempt (success or failure) to fetch a fresh one —
/// see docs/AUTH_SETUP.md for the Cloudflare/Supabase-side setup this
/// depends on.
class CaptchaField extends StatefulWidget {
  const CaptchaField({super.key, required this.onTokenChanged});

  final ValueChanged<String?> onTokenChanged;

  @override
  State<CaptchaField> createState() => CaptchaFieldState();
}

class CaptchaFieldState extends State<CaptchaField> {
  final _controller = TurnstileController();
  Timer? _recoveryTimer;

  /// Discards the current (now spent, or about to expire) token and starts a
  /// fresh challenge. Call after every submit attempt.
  void reset() {
    widget.onTokenChanged(null);
    _controller.refreshToken();
  }

  /// On a non-retryable error (or a script-load timeout), `cloudflare_turnstile`
  /// makes the widget invisible itself (`Visibility(visible: _hasError ==
  /// null || isErrorResolvable)` in its own build) and never reloads it —
  /// that's on the caller. Normally [reset] would do it, but that only runs
  /// from a submit attempt, and the submit button stays disabled while the
  /// token is null — so without this, the widget is gone for good and the
  /// form can never be completed. The short delay avoids hammering
  /// `refreshToken` (which reloads the whole WebView) in a tight loop if
  /// the underlying problem, e.g. no network, hasn't cleared yet.
  void _recoverFromError() {
    widget.onTokenChanged(null);
    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _controller.refreshToken();
    });
  }

  @override
  void dispose() {
    _recoveryTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!isCaptchaSupported) {
      return Text(
        "Verification isn't available on this platform.",
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }

    final siteKey = dotenv.env['TURNSTILE_SITE_KEY'] ?? '';
    if (siteKey.isEmpty) {
      return Text(
        'Missing TURNSTILE_SITE_KEY — see docs/AUTH_SETUP.md.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.error,
        ),
      );
    }

    return ColoredBox(
      // The widget's own WebView/iframe paints a plain black rectangle for
      // an instant before the Turnstile challenge itself loads — matching
      // the surface color here (instead of leaving it transparent) hides
      // that flash instead of showing a jarring black box mid-form.
      color: theme.colorScheme.surface,
      child: CloudflareTurnstile(
        siteKey: siteKey,
        // Matches the "localhost" hostname registered against the widget for
        // native builds (see docs/AUTH_SETUP.md) — irrelevant on web, where
        // the script runs against the page's real origin instead.
        baseUrl: 'http://localhost/',
        controller: _controller,
        options: TurnstileOptions(
          size: TurnstileSize.flexible,
          // `auto` picks the challenge's own dark/light rendering from the
          // *device* brightness, which can mismatch our Material theme
          // (e.g. dark widget chrome on a light surface) — tie it to the
          // app's actual theme instead.
          theme: theme.brightness == Brightness.dark
              ? TurnstileTheme.dark
              : TurnstileTheme.light,
        ),
        onTokenReceived: widget.onTokenChanged,
        onTokenExpired: () => widget.onTokenChanged(null),
        onError: (error) {
          debugPrint('CaptchaField: Turnstile error $error — auto-recovering.');
          _recoverFromError();
        },
        onTimeout: () {
          debugPrint('CaptchaField: Turnstile script load timed out — auto-recovering.');
          _recoverFromError();
        },
      ),
    );
  }
}
