import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps Supabase Auth (email/password, Google OAuth) and native Google
/// Sign-In behind a single static API, mirroring the style of
/// [CurrentLocationService].
///
/// Phone verification goes through Semaphore (see docs/AUTH_SETUP.md Part 2)
/// rather than Supabase's own Phone provider. Semaphore only sends the SMS —
/// a Supabase Edge Function (`send-semaphore-otp`) generates/stores the code
/// server-side and another (`verify-semaphore-otp`) checks it and marks the
/// *Supabase* user's phone confirmed. Supabase remains the single source of
/// truth for the app's session.
abstract final class AuthService {
  static SupabaseClient get _client => Supabase.instance.client;
  static GoTrueClient get _auth => _client.auth;

  static Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;
  static Session? get currentSession => _auth.currentSession;
  static User? get currentUser => _auth.currentUser;

  /// Forces [onAuthStateChange] to emit again. Marking a profile verified
  /// (the Edge Function call + [upsertProfile]) is an out-of-band change —
  /// it doesn't itself produce a Supabase auth event — so without this,
  /// [AuthGate] has nothing telling it to re-check [hasVerifiedProfile] and
  /// keeps showing whatever it last rendered (frozen mid-signup) even after
  /// popping back to it.
  static Future<void> refreshAuthState() => _auth.refreshSession();

  /// True while [RegisterScreen] or [OtpVerificationScreen] is actively
  /// managing a phone verification it just kicked off. [AuthGate] sits
  /// underneath those screens for the entire app's lifetime and reacts to
  /// every auth-state change — including the one `signUpWithEmail` fires —
  /// so without this it also fires its own "recover a killed session" OTP
  /// send at the same time, racing the one already in flight. Cleared once
  /// those screens are done, one way or another.
  static bool isManagingPhoneVerification = false;

  /// TEMPORARY: skips the actual Semaphore SMS send/verify step everywhere
  /// it's used (RegisterScreen, AuthGate's mid-signup recovery) and marks
  /// the profile phone-verified immediately instead. The phone-uniqueness
  /// check ([isPhoneTaken]) still runs regardless — flip this back to
  /// `false` once Semaphore is ready to re-enable real OTP delivery.
  static const bool bypassOtpVerification = true;

  /// True if [e164Phone] is already attached to another profile. Backed by
  /// a SECURITY DEFINER RPC ([public.is_phone_taken]) since `profiles`' RLS
  /// only lets a user read their own row — a plain `select` here would
  /// always come back empty regardless of who else has claimed the number.
  static Future<bool> isPhoneTaken(String e164Phone) async {
    final result = await _client.rpc('is_phone_taken', params: {'check_phone': e164Phone});
    return result == true;
  }

  /// [pendingPhone] is stashed in `user_metadata` purely so [AuthGate] can
  /// recover it if the app is killed before phone verification finishes —
  /// `auth.users.phone` itself isn't set until the `verify-semaphore-otp`
  /// Edge Function succeeds, so there'd otherwise be nowhere to read the
  /// number back from to resend a code after a restart.
  static Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String pendingPhone,
  }) {
    return _auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName, 'pending_phone': pendingPhone},
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

  /// Requests a phone-verification SMS for [e164Phone] via the
  /// `send-semaphore-otp` Edge Function, which generates/stores the code
  /// server-side and sends it through Semaphore. Throws [AuthException] on
  /// failure (including rate-limit rejections, surfaced with a
  /// user-facing message from the Edge Function).
  static Future<void> requestSemaphoreOtp(String e164Phone) async {
    debugPrint('AuthService: requesting Semaphore OTP for $e164Phone...');
    try {
      final response = await _client.functions.invoke('send-semaphore-otp', body: {'phone': e164Phone});
      debugPrint('AuthService: send-semaphore-otp responded status=${response.status} data=${response.data}');
    } on FunctionException catch (e) {
      debugPrint('AuthService: send-semaphore-otp failed — status=${e.status} details=${e.details}');
      final details = e.details;
      final message = details is Map ? details['error'] as String? : null;
      throw AuthException(message ?? 'Failed to send verification code.');
    }
  }

  /// Confirms [code] against the Supabase account's pending Semaphore OTP
  /// via the `verify-semaphore-otp` Edge Function, which marks the
  /// account's phone verified on success.
  static Future<void> confirmSemaphoreOtp(String code) async {
    debugPrint('AuthService: confirmSemaphoreOtp called (code length=${code.length})');
    try {
      final response = await _client.functions.invoke('verify-semaphore-otp', body: {'code': code});
      debugPrint('AuthService: verify-semaphore-otp responded status=${response.status} data=${response.data}');
    } on FunctionException catch (e) {
      debugPrint('AuthService: verify-semaphore-otp failed — status=${e.status} details=${e.details}');
      final details = e.details;
      final message = details is Map ? details['error'] as String? : null;
      throw AuthException(message ?? 'Phone verification failed.');
    }
  }

  /// Full Google sign-in (Login screen). Creates/reuses a Supabase session.
  ///
  /// On web, `google_sign_in`'s web plugin only supports its own
  /// FedCM-rendered button — calling `authenticate()` programmatically
  /// throws `UnimplementedError`, and lightweight/One-Tap auth alone returns
  /// null when there's no auto-signed-in session. Route through Supabase's
  /// OAuth redirect instead: same standard pattern Supabase's own Flutter
  /// docs recommend, and it needs only the one redirect URI registered in
  /// Google Cloud Console (unlike the native button, which requires every
  /// dev/prod origin registered as a JavaScript origin).
  static Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      // Without an explicit redirectTo, GoTrue sends the browser back to
      // whatever "Site URL" is configured in the Supabase dashboard once
      // Google's callback completes — not wherever this page actually is.
      // `flutter run -d chrome` picks a random dev port each launch, so that
      // static Site URL almost never matches and the browser lands on a dead
      // "this site can't be reached" page. Uri.base is the page's own
      // current URL, so this always redirects back to whatever's actually
      // serving the app — but that exact origin must also be added to
      // Supabase's Authentication → URL Configuration → Redirect URLs
      // allow-list (a `http://localhost:*` wildcard covers every dev port).
      //
      // Without this, Google may also silently reuse the last-used session
      // or prompt for a typed email instead of listing every signed-in
      // account.
      await _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: Uri.base.toString(),
        queryParams: {'prompt': 'select_account'},
      );
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

  static Future<GoogleSignInAccount?> _authenticateWithGoogle() async {
    final googleSignIn = GoogleSignIn.instance;
    var googleUser = await googleSignIn.attemptLightweightAuthentication();
    if (googleUser == null && googleSignIn.supportsAuthenticate()) {
      googleUser = await googleSignIn.authenticate();
    }
    return googleUser;
  }

  static Future<void> signOut() async {
    // On web, sign-in goes entirely through Supabase's OAuth redirect and
    // never touches this plugin (see signInWithGoogle), and main.dart only
    // calls GoogleSignIn.instance.initialize() on native platforms — calling
    // signOut() here on web awaits an `initialize()` that never comes and
    // hangs forever, so sign-out itself never proceeds past this line.
    if (!kIsWeb) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (e) {
        debugPrint('AuthService: GoogleSignIn.signOut error $e');
      }
    }
    await _auth.signOut();
  }

  /// Uploads a user-picked profile photo to the public `avatars` Storage
  /// bucket and returns its public URL, ready to hand to [upsertProfile].
  /// Storage RLS restricts writes to a `<uid>/...` prefix matching the
  /// caller's own id, so this requires an active session — call only after
  /// sign-up/sign-in has completed.
  static Future<String> uploadAvatar({
    required Uint8List bytes,
    required String contentType,
  }) async {
    final uid = currentUser!.id;
    final extension = contentType.split('/').last;
    final path = '$uid/avatar.$extension';
    await _client.storage.from('avatars').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(upsert: true, contentType: contentType),
    );
    return _client.storage.from('avatars').getPublicUrl(path);
  }

  static Future<void> upsertProfile({
    required String fullName,
    required String email,
    String? phone,
    bool phoneVerified = false,
    String? photoUrl,
  }) {
    final uid = currentUser!.id;
    return _client.from('profiles').upsert({
      'id': uid,
      'full_name': fullName,
      'email': email,
      'phone': ?phone,
      'phone_verified': phoneVerified,
      'photo_url': ?photoUrl,
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

  /// Used by the dashboard sidebar's account section to show the current
  /// user's name/email/photo. Unlike [hasVerifiedProfile], failures surface
  /// as null rather than being swallowed, since the caller has a clear
  /// fallback (a placeholder avatar) either way.
  static Future<({String fullName, String email, String? photoUrl})?> fetchCurrentProfile() async {
    final uid = currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _client.from('profiles').select('full_name, email, photo_url').eq('id', uid).maybeSingle();
      if (row == null) return null;
      return (
        fullName: (row['full_name'] as String?) ?? '',
        email: (row['email'] as String?) ?? '',
        photoUrl: row['photo_url'] as String?,
      );
    } catch (e) {
      debugPrint('AuthService: fetchCurrentProfile error $e');
      return null;
    }
  }
}
