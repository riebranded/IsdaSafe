import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/auth_service.dart';
import '../services/system_notification_service.dart';
import '../theme/app_spacing.dart';
import '../widgets/account_dialogs.dart';
import '../widgets/language_toggle.dart';
import '../l10n/tr.dart';
import 'legal/legal_screen.dart';

/// Account info + sign-out — ported from the old sidebar's account row
/// (`AppShell`'s former `_AccountSection`) into its own destination.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<({String fullName, String email, String? photoUrl})?>
  _profileFuture = AuthService.fetchCurrentProfile();
  StreamSubscription? _authSub;

  @override
  void initState() {
    super.initState();
    // Also refetches after our own `updateFullName` below (it triggers a
    // `userUpdated` event), so this doubles as this screen's own refresh —
    // no separate setState needed after a successful rename.
    _authSub = AuthService.onAuthStateChange.listen((_) {
      // Picks up a just-confirmed email change (see requestEmailChange).
      AuthService.syncProfileEmail().catchError((_) {});
      setState(() {
        _profileFuture = AuthService.fetchCurrentProfile();
      });
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _editName(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setState) {
            void submit() {
              final trimmed = controller.text.trim();
              if (trimmed.isEmpty) {
                setState(() => errorText = 'Enter your name'.tr);
                return;
              }
              Navigator.of(context).pop(trimmed);
            }

            return AlertDialog(
              title: Text('Edit name'.tr),
              content: TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'Full name'.tr,
                  errorText: errorText,
                ),
                onChanged: (_) {
                  if (errorText != null) setState(() => errorText = null);
                },
                onSubmitted: (_) => submit(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Cancel'.tr),
                ),
                FilledButton(onPressed: submit, child: Text('Save'.tr)),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (newName == null || newName == currentName) return;
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await AuthService.updateFullName(newName);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Couldn\'t update name. Try again.'.tr)),
      );
    }
  }

  Future<void> _runAccountDialog(Future<String?> Function() open) async {
    final message = await open();
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = AuthService.currentUser;
    final phone = currentUser?.phone;

    return FutureBuilder<({String fullName, String email, String? photoUrl})?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        // Falls back to the synchronously-available session data while the
        // `profiles` fetch (needed for photo_url) is still in flight, so the
        // page shows a name/email immediately instead of flashing empty.
        final fallbackName =
            (currentUser?.userMetadata?['full_name'] as String?) ?? '';
        final fallbackEmail = currentUser?.email ?? '';
        final fullName = (profile?.fullName.isNotEmpty ?? false)
            ? profile!.fullName
            : fallbackName;
        final email = (profile?.email.isNotEmpty ?? false)
            ? profile!.email
            : fallbackEmail;
        final photoUrl = profile?.photoUrl;
        final displayName = fullName.isNotEmpty ? fullName : email;
        final initial = displayName.isNotEmpty
            ? displayName[0].toUpperCase()
            : '?';

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: theme.colorScheme.primary,
                      backgroundImage: photoUrl != null
                          ? NetworkImage(photoUrl)
                          : null,
                      child: photoUrl == null
                          ? Text(
                              initial,
                              style: TextStyle(
                                color: theme.colorScheme.onPrimary,
                                fontSize: 20,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (email.isNotEmpty && email != displayName)
                            Text(
                              email,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit name'.tr,
                      onPressed: () => _editName(fullName),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                bottom: AppSpacing.sm,
              ),
              child: Text(
                'Credentials'.tr,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.phone_outlined),
                    title: Text('Phone number'.tr),
                    subtitle: Text(
                      phone == null || phone.isEmpty
                          ? 'Not set'.tr
                          : (phone.startsWith('+') ? phone : '+$phone'),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () =>
                        _runAccountDialog(() => showChangePhoneDialog(context)),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.email_outlined),
                    title: Text('Email'.tr),
                    subtitle: Text(email.isEmpty ? 'Not set'.tr : email),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _runAccountDialog(
                      () => showChangeEmailDialog(context, currentEmail: email),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text('Password'.tr),
                    subtitle: Text('Change your password'.tr),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _runAccountDialog(
                      () => showChangePasswordDialog(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.translate),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'Language'.tr,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Choose the app language. The AI assistant replies in it too.'
                          .tr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const LanguageToggle(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _AppearanceCard(),
            const SizedBox(height: AppSpacing.lg),
            const _NotificationsCard(),
            const SizedBox(height: AppSpacing.lg),
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xs,
                bottom: AppSpacing.sm,
              ),
              child: Text(
                'Legal'.tr,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Card(
              child: Column(
                children: [
                  for (final (i, document) in LegalDocument.values.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: Icon(document.icon),
                      title: Text(document.title),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => openLegalDocument(context, document),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: ListTile(
                leading: const Icon(Icons.logout),
                title: Text('Sign out'.tr),
                onTap: AuthService.signOut,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Card(child: _DeleteAccountTile()),
          ],
        );
      },
    );
  }
}

/// Push notifications on/off: pond updates shown by the phone's or browser's
/// own notifications (through Firebase Cloud Messaging on Android), not just
/// inside the app; and SMS alerts on/off.
class _NotificationsCard extends StatelessWidget {
  const _NotificationsCard();

  Future<void> _toggle(BuildContext context, bool enabled) async {
    final messenger = ScaffoldMessenger.of(context);
    final service = SystemNotificationService.instance;
    final on = await service.setEnabled(enabled);
    if (enabled && !on) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Notifications are blocked. Allow them for IsdaSafe in your browser or phone settings, then try again.'
                .tr,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = SystemNotificationService.instance;

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        final String subtitle;
        if (!service.isSupported) {
          subtitle = 'Not available on this device or browser.'.tr;
        } else if (service.isBlocked) {
          subtitle =
              'Blocked. Allow notifications for IsdaSafe in your browser or phone settings.'
                  .tr;
        } else {
          subtitle =
              "Get notified when a pond reading needs attention, or a pond is verified or needs photos, even when IsdaSafe isn't on screen."
                  .tr;
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.xs,
                  ),
                  child: Text(
                    'Notifications'.tr,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.notifications_active_outlined),
                  title: Text('Push notifications'.tr),
                  subtitle: Text(subtitle),
                  value: service.isEnabled,
                  onChanged: service.isSupported
                      ? (value) => _toggle(context, value)
                      : null,
                ),
                const _SmsAlertsTile(),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Permanently deletes the account and all its data (Privacy Policy, "Your
/// rights"). On success the auth listener in AuthGate takes the user back to
/// Login, so there's nothing to navigate here.
class _DeleteAccountTile extends StatefulWidget {
  const _DeleteAccountTile();

  @override
  State<_DeleteAccountTile> createState() => _DeleteAccountTileState();
}

class _DeleteAccountTileState extends State<_DeleteAccountTile> {
  bool _deleting = false;

  Future<void> _delete() async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    final deleted = await AuthService.deleteAccount();
    if (deleted) {
      messenger.showSnackBar(
        SnackBar(content: Text('Your account has been deleted.'.tr)),
      );
      return;
    }
    if (!mounted) return;
    setState(() => _deleting = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          "Couldn't delete your account. Check your connection and try again."
              .tr,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return ListTile(
      leading: Icon(Icons.delete_forever_outlined, color: error),
      title: Text('Delete account'.tr, style: TextStyle(color: error)),
      subtitle: Text('Permanently delete your account and all its data.'.tr),
      trailing: _deleting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _deleting ? null : _delete,
    );
  }
}

/// "Are you sure?" for [_DeleteAccountTile] that only enables the delete
/// button once the user has typed [_phrase], so an account can't be deleted
/// by a stray tap. Styled like `showConfirmDialog`'s destructive variant.
/// Pops true when confirmed.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _controller = TextEditingController();

  /// Translated, so Tagalog users type the Tagalog phrase they're shown.
  String get _phrase => 'DELETE MY ACCOUNT'.tr;

  bool get _matches =>
      _controller.text.trim().toUpperCase() == _phrase.toUpperCase();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      icon: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.12),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.delete_forever_outlined, color: scheme.error),
      ),
      title: Text('Delete your account?'.tr, textAlign: TextAlign.center),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "This permanently deletes your account, ponds, readings, photos and alerts. Your paired devices are released so they can be added again. This can't be undone."
                  .tr,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'To confirm, type {0} below.'.tr.split('{0}').first,
                  ),
                  TextSpan(
                    text: _phrase,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: 'To confirm, type {0} below.'.tr.split('{0}').last,
                  ),
                ],
              ),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(hintText: _phrase),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_matches) Navigator.of(context).pop(true);
              },
            ),
          ],
        ),
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
          child: Text('Cancel'.tr),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          child: Text('Delete account'.tr),
        ),
      ],
    );
  }
}

/// SMS alerts on/off (`profiles.alert_sms`): when a new reading puts a pond's
/// water in warning or danger, the server texts the account's verified phone
/// (the `evaluate_water_alerts()` trigger and the `send-alert-sms` edge
/// function). The alerts always appear in the Notifications list too.
class _SmsAlertsTile extends StatefulWidget {
  const _SmsAlertsTile();

  @override
  State<_SmsAlertsTile> createState() => _SmsAlertsTileState();
}

class _SmsAlertsTileState extends State<_SmsAlertsTile> {
  late final Future<({AlertSms level, String? phone})?> _loaded =
      AuthService.fetchAlertSms().then((value) {
        if (value != null && mounted) setState(() => _on = value.level.isOn);
        return value;
      });
  bool? _on;
  bool _saving = false;

  Future<void> _set(bool on) async {
    final previous = _on;
    setState(() {
      _on = on;
      _saving = true;
    });
    final ok = await AuthService.updateAlertSms(
      on ? AlertSms.warning : AlertSms.off,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (!ok) _on = previous;
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Couldn't save. Check your connection and try again.".tr,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _loaded,
      builder: (context, snapshot) {
        final phone = snapshot.data?.phone;
        final on = _on;
        final String subtitle;
        if (snapshot.connectionState != ConnectionState.done) {
          subtitle = 'Loading…'.tr;
        } else if (snapshot.data == null) {
          subtitle = "Couldn't load your text alert setting.".tr;
        } else if (phone == null) {
          subtitle = 'Verify a phone number to get text alerts.'.tr;
        } else {
          subtitle = 'Texts {0} when a pond reading is in warning or danger.'
              .trf([phone]);
        }
        return SwitchListTile(
          secondary: const Icon(Icons.sms_outlined),
          title: Text('SMS alerts'.tr),
          subtitle: Text(subtitle),
          // Off until there's a verified phone to text.
          value: phone != null && (on ?? false),
          onChanged: phone != null && on != null && !_saving ? _set : null,
        );
      },
    );
  }
}

/// Light / Dark / System theme picker. Reads and writes the app-wide
/// [ThemeProvider]; selecting an option updates `MaterialApp.themeMode`
/// immediately (see [IsdaSafeApp]) and persists across launches.
class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = context.watch<ThemeProvider>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Text(
                'Appearance'.tr,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            RadioGroup<ThemeMode>(
              groupValue: themeProvider.themeMode,
              onChanged: (mode) {
                if (mode != null)
                  context.read<ThemeProvider>().setThemeMode(mode);
              },
              child: Column(
                children: [
                  for (final option in _ThemeOption.values)
                    RadioListTile<ThemeMode>(
                      value: option.mode,
                      secondary: Icon(option.icon),
                      title: Text(option.label),
                      subtitle: Text(option.description),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The three selectable appearance modes, each mapped to a [ThemeMode] with
/// its own label/description/icon for the Settings list.
enum _ThemeOption {
  system(
    mode: ThemeMode.system,
    label: 'System default',
    description: 'Match your device\'s theme',
    icon: Icons.brightness_auto_outlined,
  ),
  light(
    mode: ThemeMode.light,
    label: 'Light',
    description: 'Always use the light theme',
    icon: Icons.light_mode_outlined,
  ),
  dark(
    mode: ThemeMode.dark,
    label: 'Dark',
    description: 'Always use the dark theme',
    icon: Icons.dark_mode_outlined,
  );

  const _ThemeOption({
    required this.mode,
    required String label,
    required String description,
    required this.icon,
  }) : _label = label,
       _description = description;

  final ThemeMode mode;
  final String _label;
  final String _description;
  final IconData icon;

  String get label => _label.tr;
  String get description => _description.tr;
}
