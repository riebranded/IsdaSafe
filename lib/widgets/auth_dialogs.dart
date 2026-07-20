import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';

/// Shows a single-field dialog for requesting a password-reset email.
/// Returns true if the email was sent, or null if cancelled.
Future<bool?> showForgotPasswordDialog(BuildContext context) {
  final controller = TextEditingController();

  return showDialog<bool>(
    context: context,
    builder: (context) {
      String? errorText;
      var isSubmitting = false;

      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> submit() async {
            final email = controller.text.trim();
            if (email.isEmpty || !email.contains('@')) {
              setState(() => errorText = 'Enter a valid email address');
              return;
            }

            setState(() => isSubmitting = true);
            final messenger = ScaffoldMessenger.of(context);
            final navigator = Navigator.of(context);
            try {
              await AuthService.resetPasswordForEmail(email);
              navigator.pop(true);
              messenger.showSnackBar(
                SnackBar(content: Text('Password reset email sent to $email')),
              );
            } on AuthException catch (e) {
              setState(() {
                isSubmitting = false;
                errorText = e.message;
              });
            } catch (e) {
              setState(() {
                isSubmitting = false;
                errorText = 'Something went wrong. Please try again.';
              });
              debugPrint('showForgotPasswordDialog: error $e');
            }
          }

          return AlertDialog(
            title: const Text('Reset your password'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              enabled: !isSubmitting,
              decoration: InputDecoration(
                labelText: 'Email address',
                errorText: errorText,
              ),
              onChanged: (_) {
                if (errorText != null) setState(() => errorText = null);
              },
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isSubmitting ? null : submit,
                child: isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send reset link'),
              ),
            ],
          );
        },
      );
    },
  );
}
