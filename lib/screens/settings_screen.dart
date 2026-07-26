import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/auth_service.dart';
import '../theme/app_spacing.dart';

/// Account info + sign-out — ported from the old sidebar's account row
/// (`AppShell`'s former `_AccountSection`) into its own destination.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<({String fullName, String email, String? photoUrl})?> _profileFuture =
      AuthService.fetchCurrentProfile();
  StreamSubscription? _authSub;

  @override
  void initState() {
    super.initState();
    // Also refetches after our own `updateFullName` below (it triggers a
    // `userUpdated` event), so this doubles as this screen's own refresh —
    // no separate setState needed after a successful rename.
    _authSub = AuthService.onAuthStateChange.listen((_) {
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
                setState(() => errorText = 'Enter your name');
                return;
              }
              Navigator.of(context).pop(trimmed);
            }

            return AlertDialog(
              title: const Text('Edit name'),
              content: TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(labelText: 'Full name', errorText: errorText),
                onChanged: (_) {
                  if (errorText != null) setState(() => errorText = null);
                },
                onSubmitted: (_) => submit(),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                FilledButton(onPressed: submit, child: const Text('Save')),
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
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't update name. Try again.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = AuthService.currentUser;

    return FutureBuilder<({String fullName, String email, String? photoUrl})?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        // Falls back to the synchronously-available session data while the
        // `profiles` fetch (needed for photo_url) is still in flight, so the
        // page shows a name/email immediately instead of flashing empty.
        final fallbackName = (currentUser?.userMetadata?['full_name'] as String?) ?? '';
        final fallbackEmail = currentUser?.email ?? '';
        final fullName = (profile?.fullName.isNotEmpty ?? false) ? profile!.fullName : fallbackName;
        final email = (profile?.email.isNotEmpty ?? false) ? profile!.email : fallbackEmail;
        final photoUrl = profile?.photoUrl;
        final displayName = fullName.isNotEmpty ? fullName : email;
        final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

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
                      backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                      child: photoUrl == null
                          ? Text(initial, style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 20))
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
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (email.isNotEmpty && email != displayName)
                            Text(
                              email,
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit name',
                      onPressed: () => _editName(fullName),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _AppearanceCard(),
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: AuthService.signOut,
              ),
            ),
          ],
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
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
              child: Text(
                'Appearance',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            RadioGroup<ThemeMode>(
              groupValue: themeProvider.themeMode,
              onChanged: (mode) {
                if (mode != null) context.read<ThemeProvider>().setThemeMode(mode);
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
    description: "Match your device's theme",
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
    required this.label,
    required this.description,
    required this.icon,
  });

  final ThemeMode mode;
  final String label;
  final String description;
  final IconData icon;
}
