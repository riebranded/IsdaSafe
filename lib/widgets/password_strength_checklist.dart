import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// A single password requirement and the predicate that checks it.
class PasswordRule {
  const PasswordRule(this.label, this.test);

  final String label;
  final bool Function(String value) test;
}

/// Single source of truth for password requirements — used by both the
/// realtime [PasswordStrengthChecklist] and [isStrongPassword] (the
/// submit-time validator), so they can never disagree.
final List<PasswordRule> passwordRules = [
  PasswordRule('At least 8 characters', (v) => v.length >= 8),
  PasswordRule('An uppercase letter (A-Z)', (v) => v.contains(RegExp(r'[A-Z]'))),
  PasswordRule('A lowercase letter (a-z)', (v) => v.contains(RegExp(r'[a-z]'))),
  PasswordRule('A number (0-9)', (v) => v.contains(RegExp(r'[0-9]'))),
  PasswordRule(
    'A special character (!@#\$%^&*...)',
    (v) => v.contains(RegExp(r'''[!@#$%^&*(),.?":{}|<>_\-\[\]/\\+=~`]''')),
  ),
];

bool isStrongPassword(String value) => passwordRules.every((rule) => rule.test(value));

/// Live checklist rendered beneath the password field on Register, ticking
/// each rule off in realtime as the user types.
class PasswordStrengthChecklist extends StatelessWidget {
  const PasswordStrengthChecklist({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final rule in passwordRules)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  rule.test(password) ? Icons.check_circle : Icons.cancel_outlined,
                  size: 16,
                  color: rule.test(password) ? context.statusColors.good : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(rule.label, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}
