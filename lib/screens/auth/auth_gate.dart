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

            final user = session.user;
            return OtpVerificationScreen(
              fullName: (user.userMetadata?['full_name'] as String?) ?? '',
              email: user.email ?? '',
              phone: user.phone ?? '',
            );
          },
        );
      },
    );
  }
}
