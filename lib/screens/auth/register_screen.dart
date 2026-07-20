import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// produces an invalid "+6309171234567" that Firebase rejects outright.
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

  Future<void> _prefillWithGoogle() async {
    setState(() => _isGoogleSubmitting = true);
    try {
      final profile = await AuthService.fetchGoogleProfileForPrefill();
      if (profile == null) return;
      setState(() {
        if (profile.fullName != null && profile.fullName!.isNotEmpty) {
          _fullNameController.text = profile.fullName!;
        }
        if (profile.email != null && profile.email!.isNotEmpty) {
          _emailController.text = profile.email!;
        }
      });
      // Note: Google's basic email/profile scopes do not expose a phone
      // number, so the mobile-number field is intentionally left for the
      // user to fill in themselves — this is verified via OTP regardless.
    } on AuthException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Something went wrong. Please try again.');
      debugPrint('RegisterScreen: Google prefill error $e');
    } finally {
      if (mounted) setState(() => _isGoogleSubmitting = false);
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final fullName = _fullNameController.text.trim();
    final email = _emailController.text.trim();
    final e164Phone = '$_kPhCountryCode${_stripLeadingTrunkZero(_phoneController.text.trim())}';

    setState(() => _isSubmitting = true);
    // Claimed before AuthGate's underlying StreamBuilder can react to the
    // session signUpWithEmail is about to create — see
    // AuthService.isManagingPhoneVerification for why this matters.
    AuthService.isManagingPhoneVerification = true;
    try {
      debugPrint('RegisterScreen: signing up $email...');
      await AuthService.signUpWithEmail(
        email: email,
        password: _passwordController.text,
        fullName: fullName,
        pendingPhone: e164Phone,
      );
      debugPrint('RegisterScreen: sign-up succeeded, requesting Firebase OTP for $e164Phone...');
      final outcome = await AuthService.requestFirebasePhoneOtp(e164Phone);
      debugPrint('RegisterScreen: OTP request outcome — autoVerified=${outcome.autoVerified}');
      if (!mounted) return;

      if (outcome.autoVerified) {
        // Android auto-retrieved the SMS itself — the phone is already
        // verified, so there's no code left for the user to enter.
        await AuthService.upsertProfile(fullName: fullName, email: email, phone: e164Phone, phoneVerified: true);
        await AuthService.refreshAuthState();
        AuthService.isManagingPhoneVerification = false;
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
        return;
      }

      // OtpVerificationScreen takes over ownership of the flag from here —
      // it clears it in its own dispose(), however that screen ends.
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpVerificationScreen(
            fullName: fullName,
            email: email,
            phone: e164Phone,
            verificationId: outcome.verificationId!,
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
      appBar: AppBar(title: const Text('Create account')),
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
                    OutlinedButton.icon(
                      onPressed: busy ? null : _prefillWithGoogle,
                      icon: _isGoogleSubmitting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.g_mobiledata, size: 28),
                      label: const Text('Continue with Google'),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Fills in your name and email from Google. You still set a '
                      'password and verify your mobile number.',
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
                      enabled: !busy,
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
                    const SizedBox(height: AppSpacing.xs),
                    // Required by Google's terms since the reCAPTCHA badge
                    // (shown while sending the phone OTP) is hidden via CSS
                    // — see web/index.html.
                    Text(
                      'This site is protected by reCAPTCHA and the Google '
                      'Privacy Policy and Terms of Service apply.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
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
                      validator: (value) => isStrongPassword(value ?? '') ? null : 'Password does not meet all requirements',
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
                          icon: Icon(_obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                        ),
                      ),
                      validator: (value) => value == _passwordController.text ? null : 'Passwords do not match',
                      onFieldSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Create account'),
                    ),
                    const SizedBox(height: AppSpacing.lg),
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
}
