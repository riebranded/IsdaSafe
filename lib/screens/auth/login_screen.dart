import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../widgets/auth_dialogs.dart';
import '../../widgets/captcha_field.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  /// How long the solved widget stays on screen before collapsing, so its
  /// own checkmark animation gets to finish playing instead of being cut
  /// off by an instant hide.
  static const _captchaHideDelay = Duration(milliseconds: 900);

  var _isSubmitting = false;
  var _isGoogleSubmitting = false;
  var _obscurePassword = true;
  String? _captchaToken;
  var _showCaptcha = true;

  void _handleCaptchaToken(String? token) {
    setState(() => _captchaToken = token);
    if (token == null) {
      // Expired/errored — show it again immediately, no reason to delay.
      setState(() => _showCaptcha = true);
      return;
    }
    Future.delayed(_captchaHideDelay, () {
      // Only hide if this is still the token that triggered the delay —
      // it may have already expired or been reset (e.g. by a submit
      // attempt) by the time this fires.
      if (mounted && _captchaToken == token) {
        setState(() => _showCaptcha = false);
      }
    });
  }

  static final _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final captchaToken = _captchaToken;
    if (captchaToken == null) return;

    setState(() => _isSubmitting = true);
    try {
      await AuthService.signInWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        captchaToken: captchaToken,
      );
      // AuthGate reacts to the auth-state stream automatically; nothing
      // further to do here.
    } on AuthException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Something went wrong. Please try again.');
      debugPrint('LoginScreen: sign-in error $e');
    } finally {
      // Tokens are single-use, and the widget hides itself shortly after
      // being solved — bring it back immediately for a fresh challenge
      // before the next attempt, whether this one succeeded or failed.
      if (mounted) {
        setState(() {
          _captchaToken = null;
          _showCaptcha = true;
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _submitWithGoogle() async {
    setState(() => _isGoogleSubmitting = true);
    try {
      await AuthService.signInWithGoogle();
    } on AuthException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Something went wrong. Please try again.');
      debugPrint('LoginScreen: Google sign-in error $e');
    } finally {
      if (mounted) setState(() => _isGoogleSubmitting = false);
    }
  }

  Future<void> _forgotPassword() async {
    await showForgotPasswordDialog(context);
  }

  void _goToRegister() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RegisterScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= kWideLayoutBreakpoint;

    if (!isWide) {
      final theme = Theme.of(context);
      return Scaffold(
        body: SafeArea(child: Center(child: _buildForm(theme, isWide: false))),
      );
    }

    // Wide (web/desktop) layout is a fixed light brand presentation —
    // independent of the user's in-app dark/light preference, which only
    // takes effect once they're past this screen — so the split layout
    // always reads as bright navy-on-cream, never as a dark/near-black
    // surface the ambient dark ColorScheme would otherwise produce here.
    return Theme(
      data: AppTheme.light,
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Scaffold(
            backgroundColor: theme.colorScheme.surfaceContainerLow,
            body: SafeArea(
              child: Row(
                children: [
                  Expanded(child: _BrandingPanel(theme: theme)),
                  Expanded(
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.all(AppSpacing.xxl),
                        constraints: const BoxConstraints(maxWidth: 480),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 40,
                              offset: const Offset(0, 16),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          child: _buildForm(theme, isWide: true),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildForm(ThemeData theme, {required bool isWide}) {
    final busy = _isSubmitting || _isGoogleSubmitting;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isWide) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Image.asset(
                    'assets/branding/logo.png',
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              Text(
                'Welcome back',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Log in to IsdaSafe to continue',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              TextFormField(
                controller: _emailController,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return 'Enter your email';
                  if (!_emailRegExp.hasMatch(trimmed)) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _passwordController,
                enabled: !busy,
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                validator: (value) => (value == null || value.isEmpty)
                    ? 'Enter your password'
                    : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: busy ? null : _forgotPassword,
                  child: const Text('Forgot password?'),
                ),
              ),
              // Hidden a moment after solving (see _handleCaptchaToken)
              // — reappears immediately when a fresh challenge is
              // needed for the next attempt (see _submit's finally).
              if (_showCaptcha) ...[
                const SizedBox(height: AppSpacing.sm),
                Center(
                  child: CaptchaField(onTokenChanged: _handleCaptchaToken),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: (busy || _captchaToken == null) ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Log in'),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    child: Text('or', style: theme.textTheme.bodySmall),
                  ),
                  const Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: busy ? null : _submitWithGoogle,
                icon: _isGoogleSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.g_mobiledata, size: 28),
                label: const Text('Continue with Google'),
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Don't have an account?",
                    style: theme.textTheme.bodyMedium,
                  ),
                  TextButton(
                    onPressed: busy ? null : _goToRegister,
                    child: const Text('Register'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wide-layout (web/desktop) left panel. Always rendered in the brand navy
/// from the logo — regardless of app theme — with a short feature list so
/// it reads as a proper marketing panel rather than just a centered logo.
class _BrandingPanel extends StatelessWidget {
  const _BrandingPanel({required this.theme});

  final ThemeData theme;

  static const _navy = Color(0xFF0B2644);
  static const _navyDeep = Color(0xFF081D37);
  static const _cream = Color(0xFFFDF6E3);

  static const _features = [
    (Icons.water_drop_outlined, 'Real-time water quality tracking'),
    (Icons.set_meal_outlined, 'AI-powered fish species recommendations'),
    (Icons.location_on_outlined, 'Map every pond you manage'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navy, _navyDeep],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: Image.asset(
                      'assets/branding/logo.png',
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'IsdaSafe',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Monitor your ponds, wherever you are.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xxl),
                for (final feature in _features) ...[
                  _FeatureRow(
                    icon: feature.$1,
                    label: feature.$2,
                    cream: _cream,
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.label,
    required this.cream,
  });

  final IconData icon;
  final String label;
  final Color cream;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(icon, color: cream, size: 20),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
