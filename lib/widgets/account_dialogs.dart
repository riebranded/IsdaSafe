import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../theme/app_spacing.dart';
import 'password_strength_checklist.dart';
import 'phone_input.dart';
import '../l10n/tr.dart';

final _emailRegExp = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Each dialog resolves to a short success message for the caller to show
/// (null when cancelled).
Future<String?> showChangeEmailDialog(
  BuildContext context, {
  String? currentEmail,
}) => showDialog<String>(
  context: context,
  builder: (_) => _ChangeEmailDialog(currentEmail: currentEmail),
);

Future<String?> showChangePasswordDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      // Closing goes through the "discard?" confirmation (see the dialog).
      barrierDismissible: false,
      builder: (_) => const _ChangePasswordDialog(),
    );

Future<String?> showChangePhoneDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (_) => const _ChangePhoneDialog(),
    );

/// Failure/success notifications for the three account changes.
Future<void> _notifyFailed(String what, String reason) =>
    AuthService.recordAccountEvent(
      type: 'account_${what}_failed',
      title: '{0} change failed'.trf([_label(what)]),
      body: reason,
    );

Future<void> _notifySucceeded(String what, String body, {String? title}) =>
    AuthService.recordAccountEvent(
      type: 'account_${what}_changed',
      title: title ?? '{0} updated'.trf([_label(what)]),
      body: body,
    );

String _label(String what) => switch (what) {
  'phone' => 'Phone number'.tr,
  'email' => 'Email'.tr,
  _ => 'Password'.tr,
};

String _errorText(Object e) =>
    e is AuthException ? e.message : 'Something went wrong. Please try again.'.tr;

class _ChangeEmailDialog extends StatefulWidget {
  const _ChangeEmailDialog({this.currentEmail});

  final String? currentEmail;

  @override
  State<_ChangeEmailDialog> createState() => _ChangeEmailDialogState();
}

class _ChangeEmailDialogState extends State<_ChangeEmailDialog> {
  final _controller = TextEditingController();
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _controller.text.trim();
    if (!_emailRegExp.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address'.tr);
      return;
    }
    if (email.toLowerCase() == widget.currentEmail?.toLowerCase()) {
      setState(() => _error = 'That is already your email'.tr);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (await AuthService.isEmailTaken(email)) {
        _notifyFailed('email', '{0} is already in use by another account.'.trf([email]));
        if (mounted) setState(() => _error = 'That email is already in use'.tr);
        return;
      }
      await AuthService.requestEmailChange(email);
      _notifySucceeded(
        'email',
        'We sent a confirmation link to {0}. Follow it to finish the change.'.trf([email]),
        title: 'Email change requested'.tr,
      );
      if (mounted) {
        Navigator.of(context).pop(
          'Confirmation sent — follow the link in your email to finish the change.'.tr,
        );
      }
    } catch (e) {
      _notifyFailed('email', _errorText(e));
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Change email'.tr),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'We\'ll email a confirmation link. Your email changes once you follow it.'.tr,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: 'New email'.tr,
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel'.tr),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Text('Send link'.tr),
        ),
      ],
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog();

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

/// Verifies the account's phone by SMS code first, and only then offers the
/// new-password form.
class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _otp = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _emailCode = TextEditingController();
  late final String? _phone = _currentPhone();
  var _otpVerified = false;
  var _codeSent = false;
  var _needsEmailCode = false;
  var _obscure = true;
  String? _error;
  var _busy = false;

  static String? _currentPhone() {
    final phone = AuthService.currentUser?.phone;
    if (phone == null || phone.isEmpty) return null;
    return phone.startsWith('+') ? phone : '+$phone';
  }

  String get _maskedPhone {
    final phone = _phone!;
    return phone.length <= 4
        ? phone
        : '${'•' * (phone.length - 4)}${phone.substring(phone.length - 4)}';
  }

  @override
  void initState() {
    super.initState();
    if (_phone == null) {
      _error = 'Add a verified phone number first — we send the code there.'.tr;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sendCode());
    }
  }

  @override
  void dispose() {
    _otp.dispose();
    _password.dispose();
    _confirm.dispose();
    _emailCode.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.requestSemaphoreOtp(_phone!);
      if (mounted) setState(() => _codeSent = true);
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otp.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code'.tr);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.confirmSemaphoreOtp(code);
      if (mounted) setState(() => _otpVerified = true);
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!isStrongPassword(_password.text)) {
      setState(() => _error = 'Password does not meet all the requirements'.tr);
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'Passwords do not match'.tr);
      return;
    }
    final nonce = _needsEmailCode ? _emailCode.text.trim() : null;
    if (_needsEmailCode && (nonce == null || nonce.isEmpty)) {
      setState(() => _error = 'Enter the code we emailed you'.tr);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.changePassword(_password.text, nonce: nonce);
      _notifySucceeded('password', 'Your password was changed.'.tr);
      if (mounted) Navigator.of(context).pop('Password updated.'.tr);
    } on AuthException catch (e) {
      if (AuthService.needsReauthentication(e) && !_needsEmailCode) {
        try {
          await AuthService.sendReauthenticationCode();
          if (mounted) setState(() => _needsEmailCode = true);
        } catch (e2) {
          _notifyFailed('password', _errorText(e2));
          if (mounted) setState(() => _error = _errorText(e2));
        }
      } else {
        _notifyFailed('password', e.message);
        if (mounted) setState(() => _error = e.message);
      }
    } catch (e) {
      _notifyFailed('password', _errorText(e));
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _otpStep(ThemeData theme) => [
    Text(
      _codeSent
          ? 'Enter the 6-digit code we texted to {0}.'.trf([_maskedPhone])
          : _phone == null
          ? 'We couldn\'t find a phone number on your account.'.tr
          : 'Sending a verification code to {0}…'.trf([_maskedPhone]),
      style: theme.textTheme.bodySmall,
    ),
    const SizedBox(height: AppSpacing.md),
    TextField(
      controller: _otp,
      enabled: _codeSent,
      autofocus: true,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(6),
      ],
      decoration: InputDecoration(
        labelText: 'Verification code'.tr,
        errorText: _error,
      ),
      onChanged: (_) {
        if (_error != null) setState(() => _error = null);
      },
      onSubmitted: (_) => _verifyOtp(),
    ),
    if (_phone != null)
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton(
          onPressed: _busy ? null : _sendCode,
          child: Text('Resend code'.tr),
        ),
      ),
  ];

  List<Widget> _passwordStep(ThemeData theme) => [
    if (_needsEmailCode) ...[
      Text(
        'For your security, we also emailed you a code. Enter it to confirm the change.'.tr,
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: AppSpacing.md),
      TextField(
        controller: _emailCode,
        autofocus: true,
        decoration: InputDecoration(labelText: 'Email code'.tr),
      ),
      const SizedBox(height: AppSpacing.md),
    ],
    TextField(
      controller: _password,
      autofocus: !_needsEmailCode,
      obscureText: _obscure,
      decoration: InputDecoration(
        labelText: 'New password'.tr,
        suffixIcon: IconButton(
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      onChanged: (_) => setState(() => _error = null),
    ),
    const SizedBox(height: AppSpacing.sm),
    PasswordStrengthChecklist(password: _password.text),
    const SizedBox(height: AppSpacing.md),
    TextField(
      controller: _confirm,
      obscureText: _obscure,
      decoration: InputDecoration(labelText: 'Confirm new password'.tr),
      onChanged: (_) => setState(() => _error = null),
      onSubmitted: (_) => _submit(),
    ),
    if (_error != null) ...[
      const SizedBox(height: AppSpacing.sm),
      Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
    ],
  ];

  /// Asks before abandoning the change; closes the dialog on yes.
  Future<void> _confirmCancel() async {
    if (_busy) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancel password change?'.tr),
        content: Text('Your password won\'t be changed.'.tr),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Keep editing'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Yes, cancel'.tr),
          ),
        ],
      ),
    );
    if (sure == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmCancel();
      },
      child: AlertDialog(
        title: Text(_otpVerified ? 'Change password'.tr : 'Verify it’s you'.tr),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _otpVerified ? _passwordStep(theme) : _otpStep(theme),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : _confirmCancel,
            child: Text('Cancel'.tr),
          ),
          FilledButton(
            onPressed: _busy || (!_otpVerified && !_codeSent)
                ? null
                : (_otpVerified ? _submit : _verifyOtp),
            child: Text(_otpVerified ? 'Update'.tr : 'Verify'.tr),
          ),
        ],
      ),
    );
  }
}

class _ChangePhoneDialog extends StatefulWidget {
  const _ChangePhoneDialog();

  @override
  State<_ChangePhoneDialog> createState() => _ChangePhoneDialogState();
}

class _ChangePhoneDialogState extends State<_ChangePhoneDialog> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String? _e164;
  String? _error;
  var _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final digits = _phone.text.trim();
    if (digits.length != 10 || !digits.startsWith('9')) {
      setState(
        () => _error = 'Enter a valid mobile number (e.g. 917 123 4567)'.tr,
      );
      return;
    }
    final e164 = '$kPhCountryCode$digits';
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (await AuthService.isPhoneTaken(e164)) {
        _notifyFailed(
          'phone',
          'The number is already in use by other account.'.tr,
        );
        if (mounted) {
          setState(
            () => _error = 'The number is already in use by other account'.tr,
          );
        }
        return;
      }
      await AuthService.requestSemaphoreOtp(e164);
      if (mounted) setState(() => _e164 = e164);
    } catch (e) {
      _notifyFailed('phone', _errorText(e));
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code'.tr);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.confirmSemaphoreOtp(code);
      await AuthService.updateVerifiedPhone(_e164!);
      await AuthService.refreshAuthState();
      _notifySucceeded('phone', 'Your phone number is now {0}.'.trf([_e164]));
      if (mounted) Navigator.of(context).pop('Phone number updated.'.tr);
    } catch (e) {
      _notifyFailed('phone', _errorText(e));
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final awaitingCode = _e164 != null;
    return AlertDialog(
      title: Text('Change phone number'.tr),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (awaitingCode) ...[
              Text(
                'Enter the code we texted to {0}.'.trf([_e164]),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: InputDecoration(
                  labelText: 'Verification code'.tr,
                  errorText: _error,
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _verify(),
              ),
            ] else ...[
              Text(
                'We\'ll text a code to the new number to verify it.'.tr,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _phone,
                autofocus: true,
                keyboardType: TextInputType.phone,
                inputFormatters: phoneInputFormatters,
                decoration: InputDecoration(
                  labelText: 'New mobile number'.tr,
                  prefixText: '$kPhCountryCode ',
                  errorText: _error,
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _sendCode(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text('Cancel'.tr),
        ),
        FilledButton(
          onPressed: _busy ? null : (awaitingCode ? _verify : _sendCode),
          child: Text(awaitingCode ? 'Verify'.tr : 'Send code'.tr),
        ),
      ],
    );
  }
}
