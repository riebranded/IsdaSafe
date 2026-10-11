import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../theme/app_spacing.dart';

/// The app's one confirmation dialog, so every "are you sure?" looks and reads
/// the same: an icon, a question as the title, what will happen, then
/// [cancelLabel] (keeps things as they are) and [confirmLabel] (does it).
/// [destructive] colors the icon and the confirm button red, for actions that
/// remove something. Returns true only when confirmed.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) async {
  final decision = await showDecisionDialog(
    context,
    icon: icon,
    title: title,
    message: message,
    confirmLabel: confirmLabel,
    cancelLabel: cancelLabel,
    destructive: destructive,
  );
  return decision == true;
}

/// [showConfirmDialog] for when "no" is an answer of its own (e.g. declining
/// a request): true for [confirmLabel], false for [cancelLabel], null when
/// the dialog is dismissed without choosing.
Future<bool?> showDecisionDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      final accent = destructive ? scheme.error : scheme.primary;
      return AlertDialog(
        icon: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: accent),
        ),
        title: Text(title, textAlign: TextAlign.center),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Text(message, textAlign: TextAlign.center),
        ),
        actionsAlignment: MainAxisAlignment.end,
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel ?? 'Cancel'.tr),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  )
                : null,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
}
