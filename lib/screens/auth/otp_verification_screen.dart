import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/rate_limit_banner.dart';

const _kOtpLength = 6;

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.fullName,
    required this.email,
    required this.phone,
    this.photoUrl,
  });

  final String fullName;
  final String email;
  final String phone;

  /// Imported from Google during Register's prefill, if used. Null for
  /// plain email/password sign-ups.
  final String? photoUrl;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  // A single real field captures the whole code — six separate one-char
  // fields can't reliably support paste/autofill, since the browser only
  // ever targets whichever *one* field is focused. This field is kept
  // invisible; the boxes below just reflect its content.
  final _otpController = TextEditingController();
  final _otpFocusNode = FocusNode();

  Timer? _resendTimer;
  var _secondsRemaining = AuthService.otpCooldownDuration.inSeconds;
  var _isVerifying = false;
  var _isResending = false;

  /// Set when a Resend attempt is rejected — shown as a persistent inline
  /// banner rather than (or alongside, for non-rate-limit failures) a
  /// SnackBar, since a rate-limit message explaining why Resend is now
  /// disabled for minutes needs to stay visible longer than a SnackBar's
  /// few seconds, not disappear before the user has a chance to read it.
  String? _resendError;

  @override
  void initState() {
    super.initState();
    _startResendCountdown();
    _otpController.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    // Whether this screen ends in success or the user backs out, AuthGate's
    // own recovery flow is safe to take over again from here on.
    AuthService.isManagingPhoneVerification = false;
    _resendTimer?.cancel();
    _otpController.dispose();
    _otpFocusNode.dispose();
    super.dispose();
  }

  void _startResendCountdown({Duration duration = AuthService.otpCooldownDuration}) {
    _secondsRemaining = duration.inSeconds;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        // The banner explaining why Resend was disabled is now stale —
        // it's available again, so clear it rather than leave old text
        // sitting above a re-enabled button.
        setState(() {
          _secondsRemaining = 0;
          _resendError = null;
        });
        return;
      }
      setState(() => _secondsRemaining -= 1);
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _code => _otpController.text;

  void _onCodeChanged() {
    setState(() {});
    if (_code.length == _kOtpLength) _verify();
  }

  Future<void> _verify() async {
    if (_code.length != _kOtpLength || _isVerifying) return;

    setState(() => _isVerifying = true);
    try {
      debugPrint('OtpVerificationScreen: confirming code...');
      await AuthService.confirmSemaphoreOtp(_code);
      debugPrint('OtpVerificationScreen: confirmed — upserting profile as verified...');
      await AuthService.upsertProfile(
        fullName: widget.fullName,
        email: widget.email,
        phone: widget.phone,
        phoneVerified: true,
        photoUrl: widget.photoUrl,
      );
      await AuthService.refreshAuthState();
      debugPrint('OtpVerificationScreen: profile upsert done, navigating into the app');
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      debugPrint('OtpVerificationScreen: verify AuthException: ${e.message}');
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Something went wrong. Please try again.');
      debugPrint('OtpVerificationScreen: verify error $e');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    if (_secondsRemaining > 0 || _isResending) return;

    setState(() {
      _isResending = true;
      _resendError = null;
    });
    try {
      await AuthService.requestSemaphoreOtp(widget.phone);
      if (mounted) {
        _otpController.clear();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification code resent.')));
        _startResendCountdown();
      }
    } on AuthException catch (e) {
      if (mounted) _handleResendError(e.message);
    } catch (e) {
      if (mounted) _showError('Something went wrong. Please try again.');
      debugPrint('OtpVerificationScreen: resend error $e');
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  /// A rate-limit rejection here means the 60s client-side cooldown either
  /// let the user through early (clock drift, a resend from another
  /// session/device) or, for the burst/daily caps, was never long enough to
  /// begin with — those only clear after minutes, not seconds. Extending
  /// the local cooldown to match keeps Resend properly disabled instead of
  /// re-enabling in 60s and failing the same way again; the banner (see
  /// build) explains why, since a SnackBar alone doesn't stay up long
  /// enough to read the reason a button just got disabled for 10 minutes.
  void _handleResendError(String message) {
    if (message == AuthService.otpBurstOrDailyLimitMessage) {
      _startResendCountdown(duration: AuthService.otpBurstCooldownDuration);
    } else if (message != AuthService.otpCooldownMessage) {
      // Not a rate limit at all (network error, server error, etc.) —
      // Resend is already re-enabled (the guard at the top of _resend only
      // fires once _secondsRemaining is 0), so there's nothing to extend.
      _showError(message);
      return;
    }
    setState(() => _resendError = message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canResend = _secondsRemaining == 0 && !_isResending;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your number')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sms_outlined, size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: AppSpacing.md),
                  Text('Enter verification code', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'We sent a 6-digit code to ${widget.phone}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  GestureDetector(
                    onTap: () => _otpFocusNode.requestFocus(),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        _OtpBoxes(code: _code, length: _kOtpLength, enabled: !_isVerifying),
                        // The real field: invisible, but this is what
                        // actually receives typing, backspace, paste, and
                        // autofill — a single normal text field handles all
                        // of that correctly for free, unlike per-digit boxes.
                        Opacity(
                          opacity: 0,
                          child: TextField(
                            controller: _otpController,
                            focusNode: _otpFocusNode,
                            enabled: !_isVerifying,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(_kOtpLength),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton(
                    onPressed: (!_isVerifying && _code.length == _kOtpLength) ? _verify : null,
                    child: _isVerifying
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Verify'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Didn't get a code?", style: theme.textTheme.bodyMedium),
                      TextButton(
                        onPressed: canResend ? _resend : null,
                        child: Text(canResend ? 'Resend' : 'Resend in ${formatCountdown(_secondsRemaining)}'),
                      ),
                    ],
                  ),
                  if (_resendError != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    RateLimitBanner(message: _resendError!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Purely visual — six boxes reflecting [code], each showing a dot (like a
/// password field) once filled. The real input is the invisible [TextField]
/// stacked on top of this in [_OtpVerificationScreenState.build].
class _OtpBoxes extends StatelessWidget {
  const _OtpBoxes({required this.code, required this.length, required this.enabled});

  final String code;
  final int length;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activeIndex = code.length.clamp(0, length - 1);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var i = 0; i < length; i++)
          Container(
            width: 44,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: i == activeIndex && enabled
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: i == activeIndex && enabled ? 2 : 1,
              ),
            ),
            child: i < code.length ? Text('●', style: theme.textTheme.titleLarge) : null,
          ),
      ],
    );
  }
}
