import 'language_provider.dart';
import 'tagalog_strings.dart';

/// `'Sign out'.tr` — the string itself in English, its Tagalog translation
/// when the app language is Tagalog. Unknown strings fall back to English,
/// so a missing translation never breaks the UI.
extension TranslatableString on String {
  String get tr {
    if (LanguageProvider.current == AppLanguage.english) return this;
    return tagalogStrings[this] ?? this;
  }

  /// Positional version for generated call sites: `'Retry in {0}'.trf([x])`.
  String trf(List<Object?> args) {
    var text = tr;
    for (var i = 0; i < args.length; i++) {
      text = text.replaceAll('{$i}', '${args[i]}');
    }
    return text;
  }

  /// Translates a template with `{name}` placeholders, then fills them in:
  /// `'Last updated: {when}'.trArgs({'when': '5 min ago'})`.
  String trArgs(Map<String, Object?> args) {
    var text = tr;
    args.forEach((key, value) => text = text.replaceAll('{$key}', '$value'));
    return text;
  }
}
