import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/auth_service.dart';
import '../services/push_service.dart';
import '../services/system_notification_service.dart';
import '../theme/app_spacing.dart';
import '../widgets/account_dialogs.dart';
import '../widgets/language_toggle.dart';
import '../l10n/tr.dart';

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
            Card(
              child: ListTile(
                leading: const Icon(Icons.logout),
                title: Text('Sign out'.tr),
                onTap: AuthService.signOut,
              ),
            ),
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
                // To check that push works on this phone (Android).
                if (PushService.instance.canTest && service.isEnabled)
                  const _TestPushTile(),
                const _SmsAlertsTile(),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Sends a test push through Firebase to this account's phones, after a few
/// seconds so there's time to leave the app and see it arrive as a real one.
class _TestPushTile extends StatefulWidget {
  const _TestPushTile();

  @override
  State<_TestPushTile> createState() => _TestPushTileState();
}

class _TestPushTileState extends State<_TestPushTile> {
  bool _sending = false;

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    final result = await PushService.instance.sendTest();
    if (!mounted) return;
    setState(() => _sending = false);
    final seconds = PushService.testDelay.inSeconds;
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(switch (result) {
          TestPushResult.scheduled =>
            'Test notification sent. It arrives in about {0} seconds: leave the app now to see it like a real alert.'
                .trf([seconds]),
          TestPushResult.notConfigured =>
            "Push isn't set up on the server yet: add the Firebase key (FCM_SERVICE_ACCOUNT) in Supabase."
                .tr,
          TestPushResult.notRegistered =>
            "This phone couldn't register for push. Check that notifications are allowed for IsdaSafe, then try again."
                .tr,
          TestPushResult.unsupported =>
            'Push notifications are only available in the Android app.'.tr,
          TestPushResult.failed =>
            "Couldn't send the test notification. Check your connection and try again."
                .tr,
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.send_to_mobile_outlined),
      title: Text('Send a test notification'.tr),
      subtitle: Text(
        kIsWeb
            ? 'Checks that notifications show in this browser.'.tr
            : 'Checks that push notifications reach this phone.'.tr,
      ),
      trailing: _sending
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: _sending ? null : _send,
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
        return Column(
          children: [
            SwitchListTile(
              secondary: const Icon(Icons.sms_outlined),
              title: Text('SMS alerts'.tr),
              subtitle: Text(subtitle),
              // Off until there's a verified phone to text.
              value: phone != null && (on ?? false),
              onChanged: phone != null && on != null && !_saving ? _set : null,
            ),
            if (phone != null) _TestSmsTile(phone: phone),
          ],
        );
      },
    );
  }
}

/// Texts a made-up water alert to the verified phone, to check that alert
/// texts really arrive (and say why not when they can't).
class _TestSmsTile extends StatefulWidget {
  const _TestSmsTile({required this.phone});

  final String phone;

  @override
  State<_TestSmsTile> createState() => _TestSmsTileState();
}

class _TestSmsTileState extends State<_TestSmsTile> {
  bool _sending = false;

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    final result = await AuthService.sendTestSms();
    if (!mounted) return;
    setState(() => _sending = false);
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(switch (result) {
          TestSmsResult.sent =>
            'Test SMS sent to {0}. It should arrive within a minute.'.trf([
              widget.phone,
            ]),
          TestSmsResult.failed =>
            'Semaphore rejected the SMS. Check your Semaphore credits and sender name.'
                .tr,
          TestSmsResult.disabled =>
            'SMS is switched off on the server: set the SMS_ENABLED secret to true in Supabase.'
                .tr,
          TestSmsResult.notConfigured =>
            "SMS isn't set up on the server yet: add the SEMAPHORE_API_KEY secret in Supabase."
                .tr,
          TestSmsResult.noPhone =>
            'Verify a phone number to get text alerts.'.tr,
          TestSmsResult.rateLimited =>
            'Too many test texts. Try again in an hour.'.tr,
          TestSmsResult.unreachable =>
            "Couldn't send the test SMS. Check your connection and try again."
                .tr,
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.outgoing_mail),
      title: Text('Send a test SMS alert'.tr),
      subtitle: Text(
        'Texts a sample water alert to {0} to check SMS alerts work.'.trf([
          widget.phone,
        ]),
      ),
      trailing: _sending
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: _sending ? null : _send,
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
