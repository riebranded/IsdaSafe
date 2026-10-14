import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'push_service.dart';

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
  static const bool bypassOtpVerification = false;

  /// True if [e164Phone] is already attached to another profile. Backed by
  /// a SECURITY DEFINER RPC ([public.is_phone_taken]) since `profiles`' RLS
  /// only lets a user read their own row — a plain `select` here would
  /// always come back empty regardless of who else has claimed the number.
  static Future<bool> isPhoneTaken(String e164Phone) async {
    final result = await _client.rpc(
      'is_phone_taken',
      params: {'check_phone': e164Phone},
    );
    return result == true;
  }

  /// True if [email] is already attached to another profile. Same shape
  /// (and same RLS reasoning) as [isPhoneTaken] — checked proactively by
  /// RegisterScreen alongside the phone check so a duplicate email and a
  /// duplicate phone submitted together both surface at once, instead of
  /// only ever discovering the email is taken later, from `signUpWithEmail`
  /// throwing (which only runs at all once the phone check has already
  /// passed).
  static Future<bool> isEmailTaken(String email) async {
    final result = await _client.rpc(
      'is_email_taken',
      params: {'check_email': email},
    );
    return result == true;
  }

  /// [pendingPhone] is stashed in `user_metadata` purely so [AuthGate] can
  /// recover it if the app is killed before phone verification finishes —
  /// `auth.users.phone` itself isn't set until the `verify-semaphore-otp`
  /// Edge Function succeeds, so there'd otherwise be nowhere to read the
  /// number back from to resend a code after a restart.
  /// [captchaToken] is required once Turnstile CAPTCHA protection is enabled
  /// on the Supabase project (see docs/AUTH_SETUP.md) — Supabase rejects
  /// every password-grant call below without one.
  static Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String pendingPhone,
    required String captchaToken,
  }) {
    return _auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName, 'pending_phone': pendingPhone},
      captchaToken: captchaToken,
    );
  }

  static Future<AuthResponse> signInWithEmail({
    required String email,
    required String password,
    required String captchaToken,
  }) {
    return _auth.signInWithPassword(
      email: email,
      password: password,
      captchaToken: captchaToken,
    );
  }

  static Future<void> resetPasswordForEmail(
    String email, {
    required String captchaToken,
  }) {
    return _auth.resetPasswordForEmail(
      email,
      captchaToken: captchaToken,
      redirectTo: _siteBase(),
    );
  }

  /// Checks the one-time code from the password-reset email. On success
  /// Supabase opens a recovery session and emits `passwordRecovery`, which
  /// [listenForPasswordRecovery] turns into the set-new-password screen.
  /// Needs the project's "Reset password" email template to include
  /// `{{ .Token }}`.
  static Future<void> verifyRecoveryCode(String email, String code) async {
    await _auth.verifyOTP(email: email, token: code, type: OtpType.recovery);
  }

  /// [requestSemaphoreOtp]'s exact wording for the 60s per-user cooldown —
  /// matches `COOLDOWN_SECONDS`'s message in `send-semaphore-otp/index.ts`.
  /// Exposed so callers can tell a cooldown rejection apart from other
  /// [AuthException]s (e.g. to extend a local resend timer to match)
  /// without re-deriving the server's own copy.
  static const otpCooldownMessage =
      'Please wait before requesting another code.';

  /// [requestSemaphoreOtp]'s exact wording for the burst (3/10min) or daily
  /// (8/24h) send limits — matches `RATE_LIMITED_MESSAGE` in
  /// `send-semaphore-otp/index.ts`. See [otpCooldownMessage].
  static const otpBurstOrDailyLimitMessage =
      'Too many attempts, please try again later.';

  /// Matches `COOLDOWN_SECONDS` in `send-semaphore-otp/index.ts` — how long
  /// to disable a local resend/retry control after [otpCooldownMessage].
  static const otpCooldownDuration = Duration(seconds: 60);

  /// Matches `BURST_WINDOW_MINUTES` in `send-semaphore-otp/index.ts` — how
  /// long to disable a local resend/retry control after
  /// [otpBurstOrDailyLimitMessage]. (The daily cap can be longer still, but
  /// there's no way to tell the two apart from the error message alone —
  /// this is the shorter of the two, so a caller may occasionally need to
  /// wait out a second rejection rather than the full 24h up front.)
  static const otpBurstCooldownDuration = Duration(minutes: 10);

  /// Requests a phone-verification SMS for [e164Phone] via the
  /// `send-semaphore-otp` Edge Function, which generates/stores the code
  /// server-side and sends it through Semaphore. Throws [AuthException] on
  /// failure (including rate-limit rejections, surfaced with a
  /// user-facing message from the Edge Function — see [otpCooldownMessage]
  /// and [otpBurstOrDailyLimitMessage]).
  static Future<void> requestSemaphoreOtp(String e164Phone) async {
    debugPrint('AuthService: requesting Semaphore OTP for $e164Phone...');
    try {
      final response = await _client.functions.invoke(
        'send-semaphore-otp',
        body: {'phone': e164Phone},
      );
      debugPrint(
        'AuthService: send-semaphore-otp responded status=${response.status} data=${response.data}',
      );
    } on FunctionException catch (e) {
      debugPrint(
        'AuthService: send-semaphore-otp failed — status=${e.status} details=${e.details}',
      );
      final details = e.details;
      final message = details is Map ? details['error'] as String? : null;
      throw AuthException(message ?? 'Failed to send verification code.');
    }
  }

  /// Confirms [code] against the Supabase account's pending Semaphore OTP
  /// via the `verify-semaphore-otp` Edge Function, which marks the
  /// account's phone verified on success.
  static Future<void> confirmSemaphoreOtp(String code) async {
    debugPrint(
      'AuthService: confirmSemaphoreOtp called (code length=${code.length})',
    );
    try {
      final response = await _client.functions.invoke(
        'verify-semaphore-otp',
        body: {'code': code},
      );
      debugPrint(
        'AuthService: verify-semaphore-otp responded status=${response.status} data=${response.data}',
      );
    } on FunctionException catch (e) {
      debugPrint(
        'AuthService: verify-semaphore-otp failed — status=${e.status} details=${e.details}',
      );
      final details = e.details;
      final message = details is Map ? details['error'] as String? : null;
      throw AuthException(message ?? 'Phone verification failed.');
    }
  }

  /// Records a phone that [confirmSemaphoreOtp] just verified on the
  /// `profiles` row. (`auth.users.phone` is already updated by the Edge
  /// Function.) A targeted update, for the same reason as [updateFullName].
  static Future<void> updateVerifiedPhone(String e164Phone) async {
    final uid = currentUser!.id;
    await _client
        .from('profiles')
        .update({'phone': e164Phone, 'phone_verified': true})
        .eq('id', uid);
  }

  /// Records an in-app notification about an account change (see
  /// `notifications` + the `account_*` insert policy). Best effort: the change
  /// itself already happened (or failed), so a failure here is only logged.
  static Future<void> recordAccountEvent({
    required String type,
    required String title,
    required String body,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) return;
    try {
      await _client.from('notifications').insert({
        'user_id': uid,
        'type': type,
        'title': title,
        'body': body,
      });
    } catch (e) {
      debugPrint('AuthService: recordAccountEvent error $e');
    }
  }

  /// Starts an email change. Supabase emails a confirmation link (to both
  /// addresses when "secure email change" is on); `auth.users.email` only
  /// changes once it's followed — see [syncProfileEmail].
  static Future<void> requestEmailChange(String newEmail) async {
    await _auth.updateUser(
      UserAttributes(email: newEmail),
      emailRedirectTo: _emailConfirmedUrl(),
    );
  }

  /// Where the confirmation link lands: the static `web/email-confirmed.html`
  /// page, which says the email is confirmed and then forwards to the site.
  /// On web that's this app's own origin; on mobile there's no origin, so it
  /// comes from an optional `SITE_URL` in `.env` (null → Supabase's default
  /// Site URL). Must be in Supabase's Redirect URLs allow-list.
  static String? _emailConfirmedUrl() {
    final base = _siteBase();
    return base == null ? null : '$base/email-confirmed.html';
  }

  /// The deployed site's origin without a trailing slash (see
  /// [requestEmailChange] for where it comes from), or null if unknown.
  static String? _siteBase() {
    final base = kIsWeb ? Uri.base.origin : dotenv.env['SITE_URL'];
    if (base == null || base.isEmpty) return null;
    return base.replaceFirst(RegExp(r'/+$'), '');
  }

  /// True from the moment a password-reset email link is opened until the new
  /// password is saved (or abandoned) — [AuthGate] shows the set-new-password
  /// screen while it's set, instead of dropping the recovery session into the
  /// app. Call [listenForPasswordRecovery] once at startup.
  static final ValueNotifier<bool> recoveryPending = ValueNotifier(false);

  static void listenForPasswordRecovery() {
    onAuthStateChange.listen((state) {
      if (state.event == AuthChangeEvent.passwordRecovery) {
        recoveryPending.value = true;
      }
    });
    // The recovery event can fire while Supabase initialises, before anything
    // listens — on web the link's own URL still says what it was.
    if (kIsWeb) {
      final base = Uri.base;
      if (base.fragment.contains('type=recovery') ||
          base.queryParameters['type'] == 'recovery') {
        recoveryPending.value = true;
      }
    }
  }

  /// Copies the confirmed auth email onto `profiles.email` once they differ
  /// (i.e. after the user followed the confirmation link).
  static Future<void> syncProfileEmail() async {
    final user = currentUser;
    final email = user?.email;
    if (user == null || email == null || email.isEmpty) return;
    await _client
        .from('profiles')
        .update({'email': email})
        .eq('id', user.id)
        .neq('email', email);
  }

  /// Sets a new password. Supabase can demand a recent login or a
  /// reauthentication code for this; that surfaces as an [AuthException] with
  /// [needsReauthentication] true — call [sendReauthenticationCode] and retry
  /// with the emailed [nonce].
  static Future<void> changePassword(
    String newPassword, {
    String? nonce,
  }) async {
    await _auth.updateUser(UserAttributes(password: newPassword, nonce: nonce));
  }

  static bool needsReauthentication(AuthException e) =>
      e.code == 'reauthentication_needed' ||
      e.message.toLowerCase().contains('reauthentication');

  static Future<void> sendReauthenticationCode() => _auth.reauthenticate();

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
  ///
  /// Returns false when the user backs out of Google's account picker, so
  /// callers can stay put quietly instead of showing an error.
  static Future<bool> signInWithGoogle() async {
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
      return true;
    }

    final GoogleSignInAccount googleUser;
    try {
      final account = await _authenticateWithGoogle();
      if (account == null) return false;
      googleUser = account;
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      rethrow;
    }
    debugPrint('AuthService[google]: signed in as ${googleUser.email}');

    const scopes = ['email', 'profile'];
    final authorization = await _googleStep(
      'authorizationForScopes/authorizeScopes',
      () async =>
          await googleUser.authorizationClient.authorizationForScopes(scopes) ??
          await googleUser.authorizationClient.authorizeScopes(scopes),
    );

    final idToken = googleUser.authentication.idToken;
    debugPrint(
      'AuthService[google]: idToken ${idToken == null ? 'MISSING' : 'present'}',
    );
    if (idToken == null) {
      throw const AuthException('No ID token returned by Google.');
    }

    await _googleStep(
      'Supabase signInWithIdToken',
      () => _auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: authorization.accessToken,
      ),
    );
    return true;
  }

  static Future<GoogleSignInAccount?> _authenticateWithGoogle() async {
    final googleSignIn = GoogleSignIn.instance;
    // The silent attempt is only a shortcut: if it errors, still offer the
    // interactive account picker instead of failing sign-in outright.
    GoogleSignInAccount? googleUser;
    try {
      googleUser = await _googleStep(
        'attemptLightweightAuthentication',
        () async => await googleSignIn.attemptLightweightAuthentication(),
      );
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
    }
    if (googleUser == null && googleSignIn.supportsAuthenticate()) {
      googleUser = await _googleStep('authenticate', googleSignIn.authenticate);
    }
    return googleUser;
  }

  /// Debug helper: logs which Google sign-in step is running and which one
  /// threw, then rethrows so callers see the original error.
  static Future<T> _googleStep<T>(String step, Future<T> Function() run) async {
    debugPrint('AuthService[google]: $step...');
    try {
      final result = await run();
      debugPrint('AuthService[google]: $step OK');
      return result;
    } catch (e, st) {
      debugPrint('AuthService[google]: $step FAILED: $e\n$st');
      rethrow;
    }
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
    // Needs the session, so before signing out: no more pushes to this
    // phone for this account.
    await PushService.instance.unregister();
    await _auth.signOut();
  }

  /// Permanently deletes the signed-in account and all its data through the
  /// `delete-account` edge function, then clears the local session. Returns
  /// false (and stays signed in) if the server couldn't delete it.
  static Future<bool> deleteAccount() async {
    if (currentUser == null) return false;
    try {
      final response = await _client.functions.invoke('delete-account');
      if ((response.data as Map?)?['status'] != 'deleted') return false;
    } catch (e) {
      debugPrint('AuthService: delete account failed $e');
      return false;
    }
    if (!kIsWeb) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (e) {
        debugPrint('AuthService: GoogleSignIn.signOut error $e');
      }
    }
    // The user (and its push tokens) no longer exist on the server, so only
    // the local session is left to clear.
    await _auth.signOut(scope: SignOutScope.local);
    return true;
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
    await _client.storage
        .from('avatars')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    return _client.storage.from('avatars').getPublicUrl(path);
  }

  /// Updates the signed-in user's display name — both the `profiles` row
  /// (source of truth for [fetchCurrentProfile]) and auth `user_metadata`
  /// (what the `currentUser`-based fallbacks read before that fetch
  /// resolves). The `updateUser` call also fires a `userUpdated` event on
  /// [onAuthStateChange], which mounted account UI (sidebar, top bar,
  /// Settings) listens for to refresh itself.
  ///
  /// Deliberately a targeted `update` rather than routing through
  /// [upsertProfile] — that upserts every column, so a bare `fullName` call
  /// would silently reset `phone_verified` to false for a profile that had
  /// already completed verification.
  static Future<void> updateFullName(String fullName) async {
    final uid = currentUser!.id;
    await _client
        .from('profiles')
        .update({'full_name': fullName})
        .eq('id', uid);
    await _auth.updateUser(UserAttributes(data: {'full_name': fullName}));
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
      final row = await _client
          .from('profiles')
          .select('phone_verified')
          .eq('id', uid)
          .maybeSingle();
      return row != null && row['phone_verified'] == true;
    } catch (e) {
      debugPrint('AuthService: hasVerifiedProfile error $e');
      return false;
    }
  }

  /// Whether pond water alerts are texted to the verified phone
  /// (`profiles.alert_sms`): [AlertSms.warning] (warning and danger, the
  /// default), [AlertSms.critical] (danger only) or [AlertSms.off]. Settings
  /// shows it as an on/off switch ([AlertSms.isOn]). Null if it can't be
  /// loaded.
  static Future<({AlertSms level, String? phone})?> fetchAlertSms() async {
    final uid = currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _client
          .from('profiles')
          .select('alert_sms, phone, phone_verified')
          .eq('id', uid)
          .maybeSingle();
      if (row == null) return null;
      return (
        level: AlertSms.values.firstWhere(
          (v) => v.name == row['alert_sms'],
          orElse: () => AlertSms.warning,
        ),
        phone: row['phone_verified'] == true ? row['phone'] as String? : null,
      );
    } catch (e) {
      debugPrint('AuthService: fetchAlertSms error $e');
      return null;
    }
  }

  /// Saves [level] as `profiles.alert_sms`. Returns false on failure.
  static Future<bool> updateAlertSms(AlertSms level) async {
    final uid = currentUser?.id;
    if (uid == null) return false;
    try {
      await _client
          .from('profiles')
          .update({'alert_sms': level.name})
          .eq('id', uid);
      return true;
    } catch (e) {
      debugPrint('AuthService: updateAlertSms error $e');
      return false;
    }
  }

  /// Texts a made-up water alert to the verified phone (the `send-test-sms`
  /// edge function), worded like a real one, to check alert texts arrive.
  static Future<TestSmsResult> sendTestSms() async {
    if (currentUser == null) return TestSmsResult.failed;
    try {
      final response = await _client.functions.invoke('send-test-sms');
      final data = response.data as Map?;
      final status = data?['status'];
      debugPrint('AuthService: test SMS -> $status ${data?['detail'] ?? ''}');
      return TestSmsResult.values.firstWhere(
        (v) => v.status == status,
        orElse: () => TestSmsResult.failed,
      );
    } catch (e) {
      debugPrint('AuthService: test SMS failed $e');
      return TestSmsResult.unreachable;
    }
  }

  /// Used by the dashboard sidebar's account section to show the current
  /// user's name/email/photo. Unlike [hasVerifiedProfile], failures surface
  /// as null rather than being swallowed, since the caller has a clear
  /// fallback (a placeholder avatar) either way.
  static Future<({String fullName, String email, String? photoUrl})?>
  fetchCurrentProfile() async {
    final uid = currentUser?.id;
    if (uid == null) return null;
    try {
      final row = await _client
          .from('profiles')
          .select('full_name, email, photo_url')
          .eq('id', uid)
          .maybeSingle();
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

/// How "Send a test SMS alert" went ([AuthService.sendTestSms]).
enum TestSmsResult {
  /// Semaphore accepted it; it arrives in a minute or so.
  sent('sent'),

  /// Semaphore rejected it (credits, sender name, ...).
  failed('failed'),

  /// The server's SMS_ENABLED secret isn't "true".
  disabled('disabled'),

  /// The server has no SEMAPHORE_API_KEY secret.
  notConfigured('not_configured'),

  /// No verified phone on the account.
  noPhone('no_phone'),

  /// Too many tests this hour.
  rateLimited('rate_limited'),

  /// Couldn't reach the server.
  unreachable('');

  const TestSmsResult(this.status);

  /// What the edge function answers.
  final String status;
}

/// Which pond water alerts are texted (`profiles.alert_sms`).
enum AlertSms {
  /// Warning and danger.
  warning,

  /// Danger only.
  critical,

  off;

  /// Whether any alerts are texted.
  bool get isOn => this != AlertSms.off;
}
