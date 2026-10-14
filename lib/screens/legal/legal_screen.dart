import 'package:flutter/material.dart';

import '../../l10n/tr.dart';
import '../../theme/app_spacing.dart';

/// Where users can reach the IsdaSafe team about privacy or the terms.
const kLegalContactEmail = 'sanchezdoreenjoymarait@gmail.com';

/// Shown at the top of both documents. Bump whenever either one changes.
const _lastUpdated = 'October 13, 2026';

/// The two legal documents, each a list of titled sections.
enum LegalDocument {
  privacyPolicy('Privacy Policy', Icons.privacy_tip_outlined),
  termsAndConditions('Terms and Conditions', Icons.description_outlined);

  const LegalDocument(this._title, this.icon);

  final String _title;
  final IconData icon;

  String get title => _title.tr;

  List<({String heading, String body})> get sections => switch (this) {
    LegalDocument.privacyPolicy => _privacySections,
    LegalDocument.termsAndConditions => _termsSections,
  };
}

/// Opens [document] as a full page.
void openLegalDocument(BuildContext context, LegalDocument document) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => LegalScreen(document: document)));
}

/// Read-only page showing a [LegalDocument]. Reachable before sign-in (from
/// Login and Register) and after (from Settings).
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.document});

  final LegalDocument document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                Text(
                  document.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Last updated: {0}'.trf([_lastUpdated]),
                  style: mutedStyle,
                ),
                const SizedBox(height: AppSpacing.lg),
                for (final section in document.sections) ...[
                  Text(
                    section.heading,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SelectableText(
                    section.body.replaceAll('{email}', kLegalContactEmail),
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Terms and Conditions · Privacy Policy" links, for the Login footer.
class LegalLinks extends StatelessWidget {
  const LegalLinks({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkStyle = TextButton.styleFrom(
      textStyle: theme.textTheme.bodySmall,
      visualDensity: VisualDensity.compact,
    );
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        TextButton(
          style: linkStyle,
          onPressed: () =>
              openLegalDocument(context, LegalDocument.termsAndConditions),
          child: Text(LegalDocument.termsAndConditions.title),
        ),
        Text('·', style: theme.textTheme.bodySmall),
        TextButton(
          style: linkStyle,
          onPressed: () =>
              openLegalDocument(context, LegalDocument.privacyPolicy),
          child: Text(LegalDocument.privacyPolicy.title),
        ),
      ],
    );
  }
}

/// Required "I agree" checkbox for account creation, with links to both
/// documents so they can be read before agreeing.
class LegalConsentCheckbox extends StatelessWidget {
  const LegalConsentCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;

  /// Null disables the checkbox (e.g. while the form is submitting).
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkStyle = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: theme.textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
        ),
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('I agree to the'.tr, style: theme.textTheme.bodySmall),
              TextButton(
                style: linkStyle,
                onPressed: () => openLegalDocument(
                  context,
                  LegalDocument.termsAndConditions,
                ),
                child: Text(LegalDocument.termsAndConditions.title),
              ),
              Text('and'.tr, style: theme.textTheme.bodySmall),
              TextButton(
                style: linkStyle,
                onPressed: () =>
                    openLegalDocument(context, LegalDocument.privacyPolicy),
                child: Text(LegalDocument.privacyPolicy.title),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

const _privacySections = <({String heading, String body})>[
  (
    heading: '1. Who we are',
    body:
        'IsdaSafe is a pond water-quality monitoring app for fish farmers. It '
        'connects to IsdaSafe sensor devices, shows your pond readings, sends '
        'alerts, and gives AI-assisted advice on fish species and feeding. This '
        'Privacy Policy explains what personal data we collect, why, and how we '
        'protect it, in line with the Philippine Data Privacy Act of 2012 '
        '(Republic Act No. 10173).',
  ),
  (
    heading: '2. Information we collect',
    body:
        '• Account details: your full name, email address, mobile number, '
        'password (stored only in hashed form by our authentication provider), '
        'and an optional profile photo. If you sign in with Google, we receive '
        'your Google name, email address and profile picture.\n'
        '• Pond information: pond names, the fish species you raise and their '
        'estimated weight, feeding schedules, the pond location you pick on '
        'the map, and photos you upload to verify a pond.\n'
        '• Sensor data: water readings (such as temperature, pH, dissolved '
        'oxygen and ammonia) sent by devices you pair, plus device identifiers '
        'and the Wi-Fi network name used during pairing. Your Wi-Fi password is '
        'sent only to your device and is not stored on our servers.\n'
        '• Location: your device location, only when you choose to use it to '
        'place a pond on the map.\n'
        '• AI assistant messages: the questions you ask about your pond and the '
        'replies you receive.\n'
        '• Notification data: push notification tokens for your phone or '
        'browser, and your alert settings.\n'
        '• App preferences: language and theme, saved on your device.\n'
        "On the web version, IsdaSafe uses your browser's local storage only to "
        'keep you signed in and to remember these preferences. We do not use '
        'advertising or tracking cookies.',
  ),
  (
    heading: '3. How we use your information',
    body:
        '• To create and secure your account, including verifying your mobile '
        'number with a one-time code.\n'
        '• To show your ponds, readings, trends and analytics.\n'
        '• To send water-quality alerts by push notification and, if you turn '
        'them on, by SMS.\n'
        '• To verify that a registered pond exists, using satellite imagery of '
        'its location and the photos you provide.\n'
        '• To generate fish species and feeding recommendations and to answer '
        'your questions in the AI assistant.\n'
        '• To keep the service working, prevent abuse, and fix problems.\n'
        'We do not sell your personal data and we do not use it for '
        'advertising.',
  ),
  (
    heading: '4. Services we share data with',
    body:
        'We rely on trusted providers that process data on our behalf, only as '
        'needed to run IsdaSafe:\n'
        '• Supabase: account sign-in, database and file storage.\n'
        '• Google: Google Sign-In, Google Maps and Places (pond location), '
        'Firebase Cloud Messaging (push notifications), and Gemini (AI '
        'assistant, recommendations and pond photo checks).\n'
        '• Semaphore: sending verification codes and SMS alerts to your mobile '
        'number.\n'
        '• Cloudflare Turnstile: bot protection on sign-in and registration.\n'
        '• Render: hosting our fish species prediction service.\n'
        'Authorised IsdaSafe administrators can also see ponds that have a '
        'paired device, including the owner\'s name, email address and mobile '
        'number, the pond\'s location and species, and its sensor readings, '
        'so they can monitor devices and help farmers. They are bound to use '
        'this only for that purpose.\n'
        'We may also disclose information when required by law or to protect '
        'the rights and safety of our users.',
  ),
  (
    heading: '5. How long we keep your data',
    body:
        'We keep your account, pond and reading data for as long as your '
        'account is active. You can delete your account at any time in '
        'Settings > Delete account. This immediately and permanently deletes '
        'your profile, ponds, readings, photos, notifications and alert '
        'settings, and releases your paired devices.',
  ),
  (
    heading: '6. How we protect your data',
    body:
        'Data is sent over encrypted connections (HTTPS). Access to your ponds '
        'and readings is restricted to your account by database security rules. '
        'No system is perfectly secure, so please use a strong password and '
        'keep your login details private.',
  ),
  (
    heading: '7. Your rights',
    body:
        'Under the Data Privacy Act, you have the right to be informed, to '
        'access your data, to correct it, to object to its processing, to have '
        'it erased or blocked, to data portability, and to file a complaint '
        'with the National Privacy Commission. You can update your name, email, '
        'mobile number and password in Settings, turn notifications and SMS '
        'alerts on or off, and delete your account at any time. For other '
        'requests, contact us at {email}.',
  ),
  (
    heading: '8. Children',
    body:
        'IsdaSafe is not intended for children under 13, and we do not '
        'knowingly collect their personal data.',
  ),
  (
    heading: '9. Changes to this policy',
    body:
        'We may update this Privacy Policy from time to time. When we do, we '
        'will change the "Last updated" date above, and for significant '
        'changes we will let you know in the app.',
  ),
  (
    heading: '10. Contact us',
    body:
        'If you have questions about this Privacy Policy or your personal data, '
        'email us at {email}.',
  ),
];

const _termsSections = <({String heading, String body})>[
  (
    heading: '1. Acceptance of these terms',
    body:
        'By creating an account or using IsdaSafe, you agree to these Terms and '
        'Conditions and to our Privacy Policy. If you do not agree, please do '
        'not use the app.',
  ),
  (
    heading: '2. Your account',
    body:
        'You must give accurate information when you register, including a '
        'mobile number you own. You are responsible for keeping your password '
        'safe and for everything done through your account. Tell us right away '
        'if you think someone else has accessed it.',
  ),
  (
    heading: '3. Using IsdaSafe',
    body:
        'You agree to use IsdaSafe only for lawful purposes and not to:\n'
        '• register ponds you do not own or manage, or upload false pond '
        'photos or locations;\n'
        '• interfere with, overload, or try to gain unauthorized access to the '
        'app, its servers, or other users\' data;\n'
        '• misuse the SMS, notification or AI features, including sending '
        'excessive test messages;\n'
        '• copy, resell, or reverse engineer the app except where the law '
        'allows it.',
  ),
  (
    heading: '4. Sensor devices',
    body:
        'Readings depend on IsdaSafe devices being correctly installed, '
        'calibrated, powered and connected. Sensors can drift, fail or lose '
        'connection, and readings may be delayed or inaccurate. Check your '
        'equipment regularly and confirm important readings with a separate '
        'test kit.',
  ),
  (
    heading: '5. Recommendations and AI advice',
    body:
        'Water-quality statuses, fish species recommendations, feeding '
        'schedules and AI assistant answers are for guidance only. They are '
        'generated automatically and can be wrong or incomplete. They are not '
        'a substitute for professional advice. For disease outbreaks, fish '
        'kills or other serious problems, contact your local Bureau of '
        'Fisheries and Aquatic Resources (BFAR) office or a qualified expert. '
        'You remain responsible for decisions about your ponds and stock.',
  ),
  (
    heading: '6. Alerts',
    body:
        'Push notifications and SMS alerts are provided on a best-effort basis. '
        'They depend on your phone, network, notification settings and third-'
        'party providers, and may be delayed or not delivered. Do not rely on '
        'alerts as your only way of monitoring your ponds.',
  ),
  (
    heading: '7. Your content',
    body:
        'You keep ownership of the pond information, photos and other content '
        'you add. You allow us to store and process it only to provide and '
        'improve IsdaSafe, as described in the Privacy Policy.',
  ),
  (
    heading: '8. Availability and changes',
    body:
        'We work to keep IsdaSafe running, but we do not guarantee it will '
        'always be available or error-free. We may change, suspend or stop '
        'features at any time, and we may suspend accounts that break these '
        'terms.',
  ),
  (
    heading: '9. Limitation of liability',
    body:
        'IsdaSafe is provided "as is". To the fullest extent allowed by law, '
        'the IsdaSafe team is not liable for any loss of fish, crops, income or '
        'data, or for any indirect or consequential damages, arising from your '
        'use of the app, its devices, readings, alerts or recommendations.',
  ),
  (
    heading: '10. Ending your use',
    body:
        'You can stop using IsdaSafe at any time and delete your account in '
        'Settings > Delete account. Deleting your account permanently removes '
        'your data and cannot be undone.',
  ),
  (
    heading: '11. Changes to these terms',
    body:
        'We may update these terms from time to time. We will change the "Last '
        'updated" date above, and continuing to use IsdaSafe after an update '
        'means you accept the new terms.',
  ),
  (
    heading: '12. Governing law and contact',
    body:
        'These terms are governed by the laws of the Republic of the '
        'Philippines. Questions about these terms can be sent to {email}.',
  ),
];
