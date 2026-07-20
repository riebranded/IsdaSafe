import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../app_shell.dart';
import 'login_screen.dart';
import 'otp_verification_screen.dart';

/// Swaps between the auth flow and [AppShell] based on Supabase's current
/// session, and recovers a user who was killed mid-signup (session exists
/// but their `profiles` row is missing or not phone-verified yet) by
/// routing them back into OTP verification instead of the app.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: AuthService.onAuthStateChange,
      builder: (context, snapshot) {
        final session = snapshot.data?.session ?? AuthService.currentSession;
        if (session == null) return const LoginScreen();

        return FutureBuilder<bool>(
          future: AuthService.hasVerifiedProfile(),
          builder: (context, verifiedSnapshot) {
            if (verifiedSnapshot.connectionState != ConnectionState.done) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
            final pendingPhone = (user.userMetadata?['pending_phone'] as String?) ?? user.phone ?? '';
            return _PendingPhoneVerification(
              fullName: (user.userMetadata?['full_name'] as String?) ?? '',
              email: user.email ?? '',
              phone: pendingPhone,
            );
          },
        );
      },
    );
  }
}

/// Fires a fresh Firebase OTP send for a user recovered mid-signup (no
/// `verificationId` survives an app restart, unlike [RegisterScreen], which
/// already has one from the send it just triggered).
class _PendingPhoneVerification extends StatefulWidget {
  const _PendingPhoneVerification({required this.fullName, required this.email, required this.phone});

  final String fullName;
  final String email;
  final String phone;

  @override
  State<_PendingPhoneVerification> createState() => _PendingPhoneVerificationState();
}

class _PendingPhoneVerificationState extends State<_PendingPhoneVerification> {
  late Future<String?> _future;

  @override
  void initState() {
    super.initState();
    _future = _send();
  }

  /// Returns a `verificationId` to hand to [OtpVerificationScreen], or null
  /// if Firebase auto-verified the phone without a code (already marked
  /// verified in that case — nothing left for the caller to do).
  Future<String?> _send() async {
    if (widget.phone.isEmpty) {
      // Only possible for an account created before `pending_phone` started
      // being stored (or one that somehow never had a phone entered) —
      // there's no number left anywhere to recover, so this account can't
      // self-heal. Signing out and registering again is the way forward.
      throw const AuthException(
        "We couldn't find a pending phone number for this account. Please sign out and register again.",
      );
    }
    debugPrint('AuthGate: recovering mid-signup user, requesting fresh Firebase OTP for ${widget.phone}...');
    final outcome = await AuthService.requestFirebasePhoneOtp(widget.phone);
    debugPrint('AuthGate: recovery OTP outcome — autoVerified=${outcome.autoVerified}');
    if (!outcome.autoVerified) return outcome.verificationId;

    await AuthService.upsertProfile(
      fullName: widget.fullName,
      email: widget.email,
      phone: widget.phone,
      phoneVerified: true,
    );
    await AuthService.refreshAuthState();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError) {
          final error = snapshot.error;
          final message = error is AuthException ? error.message : 'Failed to send verification code.';
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => setState(() => _future = _send()),
                      child: const Text('Retry'),
                    ),
                    TextButton(
                      onPressed: AuthService.signOut,
                      child: const Text('Sign out'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final verificationId = snapshot.data;
        if (verificationId == null) {
          // Android auto-verified the phone already — [_send] marked the
          // profile verified, so AppShell can show immediately.
          return const AppShell();
        }

        return OtpVerificationScreen(
          fullName: widget.fullName,
          email: widget.email,
          phone: widget.phone,
          verificationId: verificationId,
        );
      },
    );
  }
}
