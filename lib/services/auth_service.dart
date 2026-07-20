import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps Supabase Auth (email/password, Google OAuth, phone OTP) and native
/// Google Sign-In behind a single static API, mirroring the style of
/// [CurrentLocationService].
///
/// Phone verification goes through Supabase's Phone provider (backed by
/// Twilio, configured in the Supabase dashboard — see docs/AUTH_SETUP.md).
/// This class never talks to Twilio directly, so the Twilio Auth Token
/// never reaches the client.
abstract final class AuthService {
  static SupabaseClient get _client => Supabase.instance.client;
  static GoTrueClient get _auth => _client.auth;

  static Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;
  static Session? get currentSession => _auth.currentSession;
  static User? get currentUser => _auth.currentUser;

  static Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
  }) {
    return _auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );
  }

  static Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.signInWithPassword(email: email, password: password);
  }

  static Future<void> resetPasswordForEmail(String email) {
    return _auth.resetPasswordForEmail(email);
  }

  /// Triggers an OTP SMS to [e164Phone] via the Twilio provider configured
  /// in the Supabase dashboard. Requires an active session (the user must
  /// already be signed up/in).
  static Future<UserResponse> startPhoneVerification(String e164Phone) {
    return _auth.updateUser(UserAttributes(phone: e164Phone));
  }

  static Future<UserResponse> resendPhoneOtp(String e164Phone) {
    return startPhoneVerification(e164Phone);
  }

  static Future<AuthResponse> verifyPhoneOtp({
    required String e164Phone,
    required String token,
  }) {
    return _auth.verifyOTP(
      type: OtpType.phoneChange,
      phone: e164Phone,
      token: token,
    );
  }

  /// Full native Google sign-in (Login screen). Creates/reuses a Supabase
  /// session via the ID-token exchange.
  ///
  /// On web, `google_sign_in`'s web plugin only supports its own
  /// FedCM-rendered button — calling `authenticate()` programmatically
  /// throws `UnimplementedError`, and lightweight/One-Tap auth alone
  /// returns null when there's no auto-signed-in session, which previously
  /// surfaced as "Google sign-in was cancelled" on every tap. Route through
  /// Supabase's OAuth redirect instead, which needs no native button.
  static Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      await _auth.signInWithOAuth(OAuthProvider.google);
      return;
    }

    final googleUser = await _authenticateWithGoogle();
    if (googleUser == null) {
      throw const AuthException('Google sign-in was cancelled.');
    }

    const scopes = ['email', 'profile'];
    final authorization =
        await googleUser.authorizationClient.authorizationForScopes(scopes) ??
        await googleUser.authorizationClient.authorizeScopes(scopes);

    final idToken = googleUser.authentication.idToken;
    if (idToken == null) {
      throw const AuthException('No ID token returned by Google.');
    }

    await _auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: authorization.accessToken,
    );
  }

  /// Best-effort profile fetch from Google — used ONLY to prefill the
  /// Register form (full name + email). Never creates a Supabase session.
  ///
  /// Google's basic `email`/`profile` scopes do not expose a phone number,
  /// so this intentionally never returns one — the user still enters and
  /// verifies their phone number via OTP.
  static Future<({String? fullName, String? email})?> fetchGoogleProfileForPrefill() async {
    final googleUser = await _authenticateWithGoogle();
    if (googleUser == null) return null;
    return (fullName: googleUser.displayName, email: googleUser.email);
  }

  static Future<GoogleSignInAccount?> _authenticateWithGoogle() async {
    final googleSignIn = GoogleSignIn.instance;
    var googleUser = await googleSignIn.attemptLightweightAuthentication();
    if (googleUser == null && googleSignIn.supportsAuthenticate()) {
      googleUser = await googleSignIn.authenticate();
    }
    return googleUser;
  }

  static Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      debugPrint('AuthService: GoogleSignIn.signOut error $e');
    }
    await _auth.signOut();
  }

  static Future<void> upsertProfile({
    required String fullName,
    required String email,
    String? phone,
    bool phoneVerified = false,
  }) {
    final uid = currentUser!.id;
    return _client.from('profiles').upsert({
      'id': uid,
      'full_name': fullName,
      'email': email,
      'phone': ?phone,
      'phone_verified': phoneVerified,
    });
  }

  /// Used by [AuthGate] to decide whether a signed-in user still needs to
  /// finish phone verification.
  static Future<bool> hasVerifiedProfile() async {
    final uid = currentUser?.id;
    if (uid == null) return false;
    try {
      final row = await _client.from('profiles').select('phone_verified').eq('id', uid).maybeSingle();
      return row != null && row['phone_verified'] == true;
    } catch (e) {
      debugPrint('AuthService: hasVerifiedProfile error $e');
      return false;
    }
  }
}
