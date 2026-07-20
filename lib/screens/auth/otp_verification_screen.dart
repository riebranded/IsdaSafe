import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth_service.dart';
import '../../theme/app_spacing.dart';

const _kOtpLength = 6;
const _kResendCooldown = Duration(seconds: 30);

class OtpVerificationScreen extends StatefulWidget {
  const OtpVerificationScreen({
    super.key,
    required this.fullName,
    required this.email,
    required this.phone,
  });

  final String fullName;
  final String email;
  final String phone;

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _controllers = List.generate(_kOtpLength, (_) => TextEditingController());
  final _focusNodes = List.generate(_kOtpLength, (_) => FocusNode());

  Timer? _resendTimer;
  var _secondsRemaining = _kResendCooldown.inSeconds;
  var _isVerifying = false;
  var _isResending = false;

  @override
  void initState() {
    super.initState();
    _startResendCountdown();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _startResendCountdown() {
    _secondsRemaining = _kResendCooldown.inSeconds;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining <= 1) {
        timer.cancel();
        setState(() => _secondsRemaining = 0);
        return;
      }
      setState(() => _secondsRemaining -= 1);
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _code => _controllers.map((c) => c.text).join();

  void _onDigitChanged(int index, String value) {
    if (value.isNotEmpty && index < _kOtpLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    setState(() {});
    if (_code.length == _kOtpLength) _verify();
  }

  void _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
      setState(() {});
    }
  }

  Future<void> _verify() async {
    if (_code.length != _kOtpLength || _isVerifying) return;

    setState(() => _isVerifying = true);
    try {
      await AuthService.verifyPhoneOtp(e164Phone: widget.phone, token: _code);
      await AuthService.upsertProfile(
        fullName: widget.fullName,
        email: widget.email,
        phone: widget.phone,
        phoneVerified: true,
      );
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on AuthException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Something went wrong. Please try again.');
      debugPrint('OtpVerificationScreen: verify error $e');
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  Future<void> _resend() async {
    if (_secondsRemaining > 0 || _isResending) return;

    setState(() => _isResending = true);
    try {
      await AuthService.resendPhoneOtp(widget.phone);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification code resent.')));
        _startResendCountdown();
      }
    } on AuthException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Something went wrong. Please try again.');
      debugPrint('OtpVerificationScreen: resend error $e');
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canResend = _secondsRemaining == 0 && !_isResending;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your number')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.sms_outlined, size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: AppSpacing.md),
                  Text('Enter verification code', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'We sent a 6-digit code to ${widget.phone}',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < _kOtpLength; i++)
                        SizedBox(
                          width: 44,
                          child: KeyboardListener(
                            focusNode: FocusNode(skipTraversal: true),
                            onKeyEvent: (event) => _onKeyEvent(i, event),
                            child: TextField(
                              controller: _controllers[i],
                              focusNode: _focusNodes[i],
                              enabled: !_isVerifying,
                              autofocus: i == 0,
                              maxLength: 1,
                              textAlign: TextAlign.center,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              style: theme.textTheme.titleLarge,
                              decoration: const InputDecoration(counterText: ''),
                              onChanged: (value) => _onDigitChanged(i, value),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton(
                    onPressed: (!_isVerifying && _code.length == _kOtpLength) ? _verify : null,
                    child: _isVerifying
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Verify'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Didn't get a code?", style: theme.textTheme.bodyMedium),
                      TextButton(
                        onPressed: canResend ? _resend : null,
                        child: Text(canResend ? 'Resend' : 'Resend in ${_secondsRemaining}s'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
