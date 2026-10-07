import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import 'captcha_field.dart';
import '../l10n/tr.dart';

/// Compact, square-ish dialog for resetting a forgotten password in two steps:
/// enter the email (we send a one-time code), then enter that code. A correct
/// code opens a recovery session, and [AuthGate] then shows the set-new-
/// password screen. Returns true once the code is verified, or null if
/// cancelled.
Future<bool?> showForgotPasswordDialog(BuildContext context) {
  final email = TextEditingController();
  final code = TextEditingController();
  final captchaKey = GlobalKey<CaptchaFieldState>();

  return showDialog<bool>(
    context: context,
    builder: (context) {
      String? errorText;
      String? captchaToken;
      var codeSent = false;
      var isSubmitting = false;

      return StatefulBuilder(
        builder: (context, setState) {
          void fail(String message) => setState(() {
            isSubmitting = false;
            errorText = message;
          });

          void clearError() {
            if (errorText != null) setState(() => errorText = null);
          }

          Future<void> sendCode() async {
            final address = email.text.trim();
            if (address.isEmpty || !address.contains('@')) {
              setState(() => errorText = 'Enter a valid email address'.tr);
              return;
            }
            final token = captchaToken;
            if (token == null) return;

            setState(() => isSubmitting = true);
            try {
              await AuthService.resetPasswordForEmail(address, captchaToken: token);
              setState(() {
                isSubmitting = false;
                codeSent = true;
                errorText = null;
              });
            } on AuthException catch (e) {
              fail(e.message);
            } catch (e) {
              fail('Something went wrong. Please try again.'.tr);
              debugPrint('showForgotPasswordDialog: error $e');
            } finally {
              // Tokens are single-use — always fetch a fresh one.
              captchaKey.currentState?.reset();
            }
          }

          Future<void> verify() async {
            final entered = code.text.trim();
            if (entered.length < 6) {
              setState(() => errorText = 'Enter the code from the email'.tr);
              return;
            }
            setState(() => isSubmitting = true);
            final navigator = Navigator.of(context);
            try {
              await AuthService.verifyRecoveryCode(email.text.trim(), entered);
              navigator.pop(true);
            } on AuthException catch (e) {
              fail(e.message);
            } catch (e) {
              fail('Something went wrong. Please try again.'.tr);
              debugPrint('showForgotPasswordDialog: verify error $e');
            }
          }

          return AlertDialog(
            title: Text(
              codeSent ? 'Enter the code'.tr : 'Reset your password'.tr,
              textAlign: TextAlign.center,
            ),
            content: SizedBox(
              width: 300,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: codeSent
                      ? [
                          Text(
                            'We sent a code to {0}'.trf([email.text.trim()]),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: code,
                            autofocus: true,
                            enabled: !isSubmitting,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            maxLength: 8,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: const TextStyle(
                              fontSize: 24,
                              letterSpacing: 6,
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              hintText: '••••••',
                              errorText: errorText,
                            ),
                            onChanged: (_) => clearError(),
                            onSubmitted: (_) => verify(),
                          ),
                        ]
                      : [
                          TextField(
                            controller: email,
                            autofocus: true,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                            enabled: !isSubmitting,
                            decoration: InputDecoration(
                              labelText: 'Email address'.tr,
                              errorText: errorText,
                            ),
                            onChanged: (_) => clearError(),
                            onSubmitted: (_) => sendCode(),
                          ),
                          const SizedBox(height: 12),
                          CaptchaField(
                            key: captchaKey,
                            onTokenChanged: (token) =>
                                setState(() => captchaToken = token),
                          ),
                        ],
                ),
              ),
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                child: Text('Cancel'.tr),
              ),
              FilledButton(
                onPressed: isSubmitting
                    ? null
                    : codeSent
                    ? verify
                    : (captchaToken == null ? null : sendCode),
                child: isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(codeSent ? 'Verify code'.tr : 'Send code'.tr),
              ),
            ],
          );
        },
      );
    },
  );
}
