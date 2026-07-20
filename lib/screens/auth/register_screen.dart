import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/password_strength_checklist.dart';
import 'otp_verification_screen.dart';

/// This app only serves Philippine mobile numbers, so the calling code is
/// fixed rather than offered as a choice.
const _kPhCountryCode = '+63';

/// PH mobile numbers are commonly typed with their local trunk prefix
/// ("09171234567"), but E.164 drops it — the country code replaces it, not
/// precedes it. Concatenating "+63" directly onto a leading-0 number
/// produces an invalid "+6309171234567" that send-semaphore-otp rejects.
String _stripLeadingTrunkZero(String digits) => digits.startsWith('0') ? digits.substring(1) : digits;

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  /// True when a Supabase session already exists (AuthGate routes here
  /// straight after a fresh "Continue with Google" that has no account yet
  /// — see AuthGate's `pendingPhone.isEmpty` branch). In that case the user
  /// is already authenticated: no password to collect, and submitting only
  /// needs to gather the phone number rather than call [AuthService.signUpWithEmail].
  late final bool _hasGoogleSession = AuthService.currentSession != null;

  String? _googlePhotoUrl;
  Uint8List? _pickedImageBytes;
  String? _pickedImageMimeType;
  var _password = '';
  var _isSubmitting = false;
  var _isGoogleSubmitting = false;
  var _obscurePassword = true;
  var _obscureConfirmPassword = true;

  static final _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(() {
      setState(() => _password = _passwordController.text);
    });
    if (_hasGoogleSession) {
      final user = AuthService.currentUser!;
      _fullNameController.text = (user.userMetadata?['full_name'] as String?) ?? '';
      _emailController.text = user.email ?? '';
      _googlePhotoUrl =
          (user.userMetadata?['avatar_url'] as String?) ?? (user.userMetadata?['picture'] as String?);
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Same "does this Google account already have an account?" check as
  /// LoginScreen: a full sign-in creates/reuses the Supabase session, then
  /// pops back to AuthGate's root route so it can react — showing AppShell
  /// if the account is already verified, or this same screen again (now
  /// with `_hasGoogleSession` true, prefilled, asking only for the phone
  /// number) if it isn't.
  Future<void> _continueWithGoogle() async {
    setState(() => _isGoogleSubmitting = true);
    try {
      await AuthService.signInWithGoogle();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Something went wrong. Please try again.');
      debugPrint('RegisterScreen: Google sign-in error $e');
    } finally {
      if (mounted) setState(() => _isGoogleSubmitting = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final xfile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (xfile == null) return;
      final bytes = await xfile.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedImageBytes = bytes;
        _pickedImageMimeType = xfile.mimeType ?? 'image/jpeg';
      });
    } catch (e) {
      if (mounted) _showError('Could not open the image picker.');
      debugPrint('RegisterScreen: image pick error $e');
    }
  }

  /// Uploads the picked image (if any) and returns its public URL; falls
  /// back to the Google-provided photo otherwise. Called from [_submit],
  /// once a session is guaranteed to exist (needed for Storage's RLS check).
  Future<String?> _resolvePhotoUrl() {
    final bytes = _pickedImageBytes;
    if (bytes == null) return Future.value(_googlePhotoUrl);
    return AuthService.uploadAvatar(bytes: bytes, contentType: _pickedImageMimeType ?? 'image/jpeg');
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final fullName = _fullNameController.text.trim();
    final email = _emailController.text.trim();
    final e164Phone = '$_kPhCountryCode${_stripLeadingTrunkZero(_phoneController.text.trim())}';

    setState(() => _isSubmitting = true);
    // Claimed before AuthGate's underlying StreamBuilder can react to the
    // session signUpWithEmail (or, in `_hasGoogleSession` mode, the Google
    // sign-in already sitting on the session) is about to create — see
    // AuthService.isManagingPhoneVerification for why this matters.
    AuthService.isManagingPhoneVerification = true;
    try {
      if (!_hasGoogleSession) {
        debugPrint('RegisterScreen: signing up $email...');
        await AuthService.signUpWithEmail(
          email: email,
          password: _passwordController.text,
          fullName: fullName,
          pendingPhone: e164Phone,
        );
      }

      // A session now exists either way, so an uploaded avatar has a uid
      // to key its Storage path off of.
      final photoUrl = await _resolvePhotoUrl();

      debugPrint('RegisterScreen: requesting Semaphore OTP for $e164Phone...');
      await AuthService.requestSemaphoreOtp(e164Phone);
      debugPrint('RegisterScreen: OTP request succeeded');
      if (!mounted) return;

      // OtpVerificationScreen takes over ownership of the flag from here —
      // it clears it in its own dispose(), however that screen ends.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            fullName: fullName,
            email: email,
            phone: e164Phone,
            photoUrl: photoUrl,
          ),
        ),
      );
    } on AuthException catch (e) {
      AuthService.isManagingPhoneVerification = false;
      if (mounted) _showError(e.message);
    } catch (e) {
      AuthService.isManagingPhoneVerification = false;
      if (mounted) _showError('Something went wrong. Please try again.');
      debugPrint('RegisterScreen: sign-up error $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _isSubmitting || _isGoogleSubmitting;

    return Scaffold(
      appBar: AppBar(title: Text(_hasGoogleSession ? 'Finish setting up' : 'Create account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildAvatarPicker(theme),
                    const SizedBox(height: AppSpacing.lg),
                    if (_hasGoogleSession) ...[
                      Text(
                        'Signed in as ${_emailController.text} via Google',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Just need your mobile number to finish setting up your account.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ] else ...[
                      OutlinedButton.icon(
                        onPressed: busy ? null : _continueWithGoogle,
                        icon: _isGoogleSubmitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.g_mobiledata, size: 28),
                        label: const Text('Continue with Google'),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Already have an account with this Google login? You’ll be '
                        'signed straight in instead.',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Row(
                        children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                            child: Text('or', style: theme.textTheme.bodySmall),
                          ),
                          const Expanded(child: Divider()),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    TextFormField(
                      controller: _fullNameController,
                      enabled: !busy,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
                      validator: (value) => (value == null || value.trim().isEmpty) ? 'Enter your full name' : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _emailController,
                      enabled: !busy && !_hasGoogleSession,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(Icons.email_outlined)),
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty) return 'Enter your email';
                        if (!_emailRegExp.hasMatch(trimmed)) return 'Enter a valid email address';
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _phoneController,
                      enabled: !busy,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Mobile number',
                        prefixIcon: Icon(Icons.phone_outlined),
                        prefixText: '$_kPhCountryCode ',
                        helperText: 'e.g. 9171234567 — the leading 0 is optional',
                      ),
                      validator: (value) {
                        final digits = _stripLeadingTrunkZero(value?.trim() ?? '');
                        if (digits.length != 10) return 'Enter a valid 10-digit mobile number';
                        return null;
                      },
                    ),
                    if (!_hasGoogleSession) ...[
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _passwordController,
                        enabled: !busy,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        validator: (value) =>
                            isStrongPassword(value ?? '') ? null : 'Password does not meet all requirements',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      PasswordStrengthChecklist(password: _password),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: _confirmPasswordController,
                        enabled: !busy,
                        obscureText: _obscureConfirmPassword,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            ),
                            onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                          ),
                        ),
                        validator: (value) => value == _passwordController.text ? null : 'Passwords do not match',
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(_hasGoogleSession ? 'Continue' : 'Create account'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_hasGoogleSession)
                      Center(
                        child: TextButton(
                          onPressed: busy ? null : AuthService.signOut,
                          child: const Text('Not you? Sign out'),
                        ),
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Already have an account?', style: theme.textTheme.bodyMedium),
                          TextButton(
                            onPressed: busy ? null : () => Navigator.of(context).pop(),
                            child: const Text('Log in'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Circular avatar placeholder — shows a picked image, else the Google
  /// photo (if prefilled), else a generic person icon — with a tappable
  /// camera badge that opens the gallery via [_pickImage].
  Widget _buildAvatarPicker(ThemeData theme) {
    final busy = _isSubmitting || _isGoogleSubmitting;
    ImageProvider? image;
    if (_pickedImageBytes != null) {
      image = MemoryImage(_pickedImageBytes!);
    } else if (_googlePhotoUrl != null) {
      image = NetworkImage(_googlePhotoUrl!);
    }

    return Center(
      child: Stack(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            backgroundImage: image,
            child: image == null
                ? Icon(Icons.person, size: 40, color: theme.colorScheme.onSurfaceVariant)
                : null,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Material(
              color: theme.colorScheme.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: busy ? null : _pickImage,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(Icons.camera_alt, size: 16, color: theme.colorScheme.onPrimary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
