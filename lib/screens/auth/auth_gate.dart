import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/rate_limit_banner.dart';
import '../app_shell.dart';
import 'login_screen.dart';
import 'otp_verification_screen.dart';
import 'register_screen.dart';
import 'reset_password_screen.dart';
import '../../l10n/tr.dart';

/// Swaps between the auth flow and [AppShell] based on Supabase's current
/// session, and recovers a user who was killed mid-signup (session exists
/// but their `profiles` row is missing or not phone-verified yet) by
/// routing them back into OTP verification instead of the app.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  /// The user whose verified profile has already been confirmed. While the
  /// session stays on this user, auth events (a password/email/phone change
  /// fires `userUpdated`) must not re-run the check — that would swap
  /// [AppShell] for a spinner and rebuild it, bouncing the user from Settings
  /// back to the dashboard.
  String? _verifiedUserId;
  Future<bool>? _verifyFuture;

  @override
  void initState() {
    super.initState();
    AuthService.recoveryPending.addListener(_onRecoveryChanged);
  }

  @override
  void dispose() {
    AuthService.recoveryPending.removeListener(_onRecoveryChanged);
    super.dispose();
  }

  void _onRecoveryChanged() {
    if (mounted) setState(() {});
  }

  Future<bool> _verify(String userId) async {
    final verified = await AuthService.hasVerifiedProfile();
    if (verified) {
      _verifiedUserId = userId;
    } else {
      // Not done yet (mid-signup): let the next auth event re-check.
      _verifyFuture = null;
    }
    return verified;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: AuthService.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? AuthService.currentSession;
        if (session == null) {
          _verifiedUserId = null;
          _verifyFuture = null;
          return const LoginScreen();
        }
        final userId = session.user.id;
        // Opened from a password-reset email: choose the new password before
        // anything else (the recovery link has already signed them in).
        if (AuthService.recoveryPending.value) {
          return const ResetPasswordScreen();
        }
        if (_verifiedUserId == userId) return const AppShell();
        if (_verifiedUserId != null) _verifyFuture = null; // different user

        return FutureBuilder<bool>(
          future: _verifyFuture ??= _verify(userId),
          builder: (context, verifiedSnapshot) {
            if (verifiedSnapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (verifiedSnapshot.data == true) return const AppShell();

            if (AuthService.isManagingPhoneVerification) {
              // RegisterScreen/OtpVerificationScreen (pushed on top, so this
              // is never actually seen) is already handling this signup's
              // phone verification — don't also fire a redundant, racing
              // OTP send from here. This widget's build() still runs even
              // while obscured by a pushed route, so without this check it
              // would fire regardless of what's visible on screen.
              return const SizedBox.shrink();
            }

            final user = session.user;
            // `auth.users.phone` isn't set until verification succeeds — the
            // pending number lives in user_metadata until then (see
            // AuthService.signUpWithEmail).
            final pendingPhone =
                (user.userMetadata?['pending_phone'] as String?) ??
                user.phone ??
                '';

            if (pendingPhone.isEmpty) {
              // A full "Continue with Google" from Login/Register (not the
              // email/password form) lands a brand-new — or pre-pending_phone
              // legacy — user here with no signup in progress to recover.
              // RegisterScreen detects the existing session itself (see
              // its `_hasGoogleSession`) and asks only for the phone number.
              return const RegisterScreen();
            }

            // A full "Login with Google" (not Register) can also land a
            // brand-new user here — Google's OIDC claims populate one of
            // these two keys in user_metadata.
            final photoUrl =
                (user.userMetadata?['avatar_url'] as String?) ??
                (user.userMetadata?['picture'] as String?);
            return _PendingPhoneVerification(
              fullName: (user.userMetadata?['full_name'] as String?) ?? '',
              email: user.email ?? '',
              phone: pendingPhone,
              photoUrl: photoUrl,
            );
          },
        );
      },
    );
  }
}

/// Fires a fresh Semaphore OTP send for a user recovered mid-signup —
/// nothing about the in-flight send survives an app restart, so this always
/// requests a new code rather than trying to recover state from before.
class _PendingPhoneVerification extends StatefulWidget {
  const _PendingPhoneVerification({
    required this.fullName,
    required this.email,
    required this.phone,
    this.photoUrl,
  });

  final String fullName;
  final String email;
  final String phone;
  final String? photoUrl;

  @override
  State<_PendingPhoneVerification> createState() =>
      _PendingPhoneVerificationState();
}

class _PendingPhoneVerificationState extends State<_PendingPhoneVerification> {
  late Future<void> _future;
  Timer? _retryTimer;
  var _secondsRemaining = 0;

  /// Identifies which [_future] the current countdown (if any) was armed
  /// for, so the rate-limit branch in [build] arms it exactly once per
  /// send attempt instead of re-arming itself on every rebuild once
  /// [_secondsRemaining] reaches 0 and the button becomes tappable again.
  Future<void>? _countdownArmedFor;

  @override
  void initState() {
    super.initState();
    _future = _send();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _startRetryCountdown(Duration duration) {
    if (!mounted) return;
    _retryTimer?.cancel();
    setState(() => _secondsRemaining = duration.inSeconds);
    _retryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _secondsRemaining = 0);
        return;
      }
      setState(() => _secondsRemaining -= 1);
    });
  }

  void _retry() {
    if (_secondsRemaining > 0) return;
    setState(() => _future = _send());
  }

  Future<void> _send() async {
    if (AuthService.bypassOtpVerification) {
      // The phone was already vetted by RegisterScreen's isPhoneTaken check
      // before it ever reached user_metadata, so recovering here can go
      // straight to marking the profile verified — same as RegisterScreen's
      // own bypass branch.
      debugPrint(
        'AuthGate: OTP bypass enabled — marking recovered profile verified without SMS.',
      );
      await AuthService.upsertProfile(
        fullName: widget.fullName,
        email: widget.email,
        phone: widget.phone,
        phoneVerified: true,
        photoUrl: widget.photoUrl,
      );
      await AuthService.refreshAuthState();
      return;
    }
    debugPrint(
      'AuthGate: recovering mid-signup user, requesting fresh Semaphore OTP for ${widget.phone}...',
    );
    await AuthService.requestSemaphoreOtp(widget.phone);
    debugPrint('AuthGate: recovery OTP send succeeded');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          final error = snapshot.error;
          final message = error is AuthException
              ? error.message
              : 'Failed to send verification code.'.tr;

          // A user recovered here (session restored, but phone still
          // unverified) can easily have already burned through
          // send-semaphore-otp's send limit before they ever left — e.g.
          // exiting mid-signup after a couple of resends, then logging
          // back in with the same email later. Without gating Retry the
          // same way OtpVerificationScreen gates Resend, tapping it just
          // repeats the same rate-limit failure instantly, with no
          // indication of why or how long to actually wait.
          final isCooldown = message == AuthService.otpCooldownMessage;
          final isBurstOrDaily =
              message == AuthService.otpBurstOrDailyLimitMessage;
          if ((isCooldown || isBurstOrDaily) && _countdownArmedFor != _future) {
            _countdownArmedFor = _future;
            final duration = isBurstOrDaily
                ? AuthService.otpBurstCooldownDuration
                : AuthService.otpCooldownDuration;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _startRetryCountdown(duration),
            );
          }
          final isRateLimited = isCooldown || isBurstOrDaily;
          final canRetry = !isRateLimited || _secondsRemaining == 0;

          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isRateLimited)
                      RateLimitBanner(message: message)
                    else
                      Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: canRetry ? _retry : null,
                      child: Text(
                        canRetry
                            ? 'Retry'.tr
                            : 'Retry in {0}'.trf([formatCountdown(_secondsRemaining)]),
                      ),
                    ),
                    TextButton(
                      onPressed: AuthService.signOut,
                      child: Text('Sign out'.tr),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        if (AuthService.bypassOtpVerification) {
          // refreshAuthState() above already fired an auth-state event;
          // AuthGate's StreamBuilder will rebuild into AppShell shortly —
          // nothing to show here in the meantime.
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return OtpVerificationScreen(
          fullName: widget.fullName,
          email: widget.email,
          phone: widget.phone,
          photoUrl: widget.photoUrl,
        );
      },
    );
  }
}
