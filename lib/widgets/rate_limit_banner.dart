import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// "Retry in 512s" is unreadable — only sub-minute cooldowns read fine as
/// bare seconds; anything longer (e.g. the 10-minute burst cooldown) needs
/// mm:ss. Shared by every rate-limit countdown in the auth flow.
String formatCountdown(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  final remainder = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$remainder';
}

/// Persistent (not a SnackBar) explanation for a rate-limit rejection —
/// used by RegisterScreen (initial OTP send) and OtpVerificationScreen
/// (Resend), both of which can leave a related button disabled for minutes
/// afterward. A SnackBar disappears in a few seconds, which isn't long
/// enough to explain why a button the user just tapped is now greyed out.
class RateLimitBanner extends StatelessWidget {
  const RateLimitBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 18, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
