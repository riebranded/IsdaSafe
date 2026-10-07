import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/language_provider.dart';

/// English / Tagalog switch. Changing it re-translates the whole app (and
/// makes the AI answer in that language).
class LanguageToggle extends StatelessWidget {
  const LanguageToggle({super.key, this.compact = false});

  /// Smaller, for tight spots like the login screen's corner.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<LanguageProvider>();
    return SegmentedButton<AppLanguage>(
      showSelectedIcon: false,
      style: compact
          ? const ButtonStyle(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            )
          : null,
      segments: [
        for (final language in AppLanguage.values)
          ButtonSegment(value: language, label: Text(language.label)),
      ],
      selected: {provider.language},
      onSelectionChanged: (selection) =>
          context.read<LanguageProvider>().setLanguage(selection.first),
    );
  }
}
