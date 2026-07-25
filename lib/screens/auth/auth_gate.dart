import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../app_shell.dart';
import 'login_screen.dart';
import 'otp_verification_screen.dart';
import 'register_screen.dart';

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
                (user.userMetadata?['avatar_url'] as String?) ?? (user.userMetadata?['picture'] as String?);
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
  State<_PendingPhoneVerification> createState() => _PendingPhoneVerificationState();
}

class _PendingPhoneVerificationState extends State<_PendingPhoneVerification> {
  late Future<void> _future;

  @override
  void initState() {
    super.initState();
    _future = _send();
  }

  Future<void> _send() async {
    if (AuthService.bypassOtpVerification) {
      // The phone was already vetted by RegisterScreen's isPhoneTaken check
      // before it ever reached user_metadata, so recovering here can go
      // straight to marking the profile verified — same as RegisterScreen's
      // own bypass branch.
      debugPrint('AuthGate: OTP bypass enabled — marking recovered profile verified without SMS.');
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
    debugPrint('AuthGate: recovering mid-signup user, requesting fresh Semaphore OTP for ${widget.phone}...');
    await AuthService.requestSemaphoreOtp(widget.phone);
    debugPrint('AuthGate: recovery OTP send succeeded');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
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

        if (AuthService.bypassOtpVerification) {
          // refreshAuthState() above already fired an auth-state event;
          // AuthGate's StreamBuilder will rebuild into AppShell shortly —
          // nothing to show here in the meantime.
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
