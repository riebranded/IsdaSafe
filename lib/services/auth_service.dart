import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wraps Supabase Auth (email/password, Google OAuth) and native Google
/// Sign-In behind a single static API, mirroring the style of
/// [CurrentLocationService].
///
/// Phone verification goes through Firebase Phone Auth (see
/// docs/AUTH_SETUP.md Part 2) rather than Supabase's own Phone provider.
/// Firebase is used only to prove phone ownership — the resulting ID token
/// is verified server-side by the `verify-firebase-phone` Edge Function,
/// which marks the *Supabase* user's phone confirmed. Supabase remains the
/// single source of truth for the app's session; every method here hides
/// the Firebase types behind [AuthException] so callers never import
/// `firebase_auth` themselves.
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
  /// send at the same time, racing Firebase's reCAPTCHA widget against
  /// itself. Cleared once those screens are done, one way or another.
  static bool isManagingPhoneVerification = false;

  /// [pendingPhone] is stashed in `user_metadata` purely so [AuthGate] can
  /// recover it if the app is killed before phone verification finishes —
  /// `auth.users.phone` itself isn't set until the `verify-firebase-phone`
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

  /// Sends an OTP to [e164Phone] via Firebase Phone Auth. [onCodeSent] fires
  /// once the SMS is on its way, with a `verificationId` (needed to confirm
  /// the code later) and an optional `resendToken` (pass back via
  /// [forceResendingToken] to resend without waiting for a new SMS).
  ///
  /// [onAutoVerified] fires instead of [onCodeSent] on Android when Firebase
  /// can auto-retrieve the SMS itself — in that case the phone is already
  /// verified by the time it fires, and there's no code left to confirm.
  static Future<void> sendFirebasePhoneOtp({
    required String e164Phone,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function() onAutoVerified,
    required void Function(AuthException error) onVerificationFailed,
    int? forceResendingToken,
  }) {
    debugPrint(
      'AuthService: verifyPhoneNumber($e164Phone) called, forceResendingToken=$forceResendingToken',
    );
    return fb_auth.FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: e164Phone,
      forceResendingToken: forceResendingToken,
      verificationCompleted: (credential) async {
        debugPrint('AuthService: verificationCompleted fired (Android auto-retrieval)');
        try {
          await _completeFirebasePhoneVerification(credential);
          debugPrint('AuthService: auto-verification completed successfully');
          onAutoVerified();
        } catch (e) {
          debugPrint('AuthService: auto-verification completion failed: $e');
          onVerificationFailed(AuthException('$e'));
        }
      },
      verificationFailed: (error) {
        debugPrint('AuthService: verificationFailed fired — code=${error.code} message=${error.message}');
        onVerificationFailed(AuthException(error.message ?? 'Failed to send verification code.'));
      },
      codeSent: (verificationId, resendToken) {
        debugPrint(
          'AuthService: codeSent fired — verificationId=${verificationId.substring(0, verificationId.length.clamp(0, 12))}… resendToken=$resendToken',
        );
        onCodeSent(verificationId, resendToken);
      },
      codeAutoRetrievalTimeout: (verificationId) {
        debugPrint('AuthService: codeAutoRetrievalTimeout fired for $verificationId');
      },
    );
  }

  /// Convenience wrapper around [sendFirebasePhoneOtp] for callers that just
  /// want to `await` an outcome instead of juggling three callbacks —
  /// [sendFirebasePhoneOtp] itself only resolves once `verifyPhoneNumber` is
  /// *called*, not once Firebase actually reports a result. Throws
  /// [AuthException] on failure (mirroring every other method here).
  static Future<({String? verificationId, int? resendToken, bool autoVerified})> requestFirebasePhoneOtp(
    String e164Phone, {
    int? forceResendingToken,
  }) {
    final completer = Completer<({String? verificationId, int? resendToken, bool autoVerified})>();
    sendFirebasePhoneOtp(
      e164Phone: e164Phone,
      forceResendingToken: forceResendingToken,
      onCodeSent: (verificationId, resendToken) {
        if (!completer.isCompleted) {
          completer.complete((verificationId: verificationId, resendToken: resendToken, autoVerified: false));
        }
      },
      onAutoVerified: () {
        if (!completer.isCompleted) {
          completer.complete((verificationId: null, resendToken: null, autoVerified: true));
        }
      },
      onVerificationFailed: (error) {
        debugPrint('AuthService: requestFirebasePhoneOtp failing with: ${error.message}');
        if (!completer.isCompleted) completer.completeError(error);
      },
    );
    return completer.future;
  }

  /// Confirms the OTP the user typed against [verificationId], then marks
  /// the Supabase account's phone as verified via the `verify-firebase-phone`
  /// Edge Function.
  static Future<void> confirmFirebasePhoneOtp({
    required String verificationId,
    required String smsCode,
  }) {
    debugPrint('AuthService: confirmFirebasePhoneOtp called (code length=${smsCode.length})');
    final credential = fb_auth.PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    return _completeFirebasePhoneVerification(credential);
  }

  static Future<void> _completeFirebasePhoneVerification(fb_auth.PhoneAuthCredential credential) async {
    debugPrint('AuthService: calling FirebaseAuth.signInWithCredential...');
    final userCredential = await fb_auth.FirebaseAuth.instance.signInWithCredential(credential);
    debugPrint('AuthService: Firebase sign-in succeeded, uid=${userCredential.user?.uid}');

    final idToken = await userCredential.user?.getIdToken();
    if (idToken == null) {
      debugPrint('AuthService: getIdToken() returned null');
      throw const AuthException('Firebase did not return an ID token.');
    }
    debugPrint('AuthService: got Firebase ID token (length=${idToken.length})');

    try {
      debugPrint('AuthService: invoking verify-firebase-phone Edge Function...');
      final response = await _client.functions.invoke('verify-firebase-phone', body: {'idToken': idToken});
      debugPrint('AuthService: verify-firebase-phone responded status=${response.status} data=${response.data}');
    } on FunctionException catch (e) {
      debugPrint('AuthService: verify-firebase-phone failed — status=${e.status} details=${e.details}');
      final details = e.details;
      final message = details is Map ? details['error'] as String? : null;
      throw AuthException(message ?? 'Phone verification failed.');
    } finally {
      // Firebase is only used transiently to prove phone ownership —
      // Supabase remains the single source of truth for the app's session.
      await fb_auth.FirebaseAuth.instance.signOut();
      debugPrint('AuthService: signed out of Firebase (transient use only)');
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
    try {
      await GoogleSignIn.instance.signOut();
    } catch (e) {
      debugPrint('AuthService: GoogleSignIn.signOut error $e');
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
