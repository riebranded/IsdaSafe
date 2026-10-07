import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/pond.dart';
import '../providers/dashboard_provider.dart';
import '../providers/pond_chat_provider.dart';
import '../theme/app_spacing.dart';
import '../l10n/tr.dart';

/// Opens the pond assistant as a bottom sheet. [topic] only sets the starting
/// focus (greeting, suggested questions); the user can switch it in the sheet.
/// [contextBuilder] is called on every send so the model sees fresh readings.
Future<void> showPondChat(
  BuildContext context, {
  required Pond pond,
  required Map<String, Object?> Function() contextBuilder,
  ChatTopic topic = ChatTopic.general,
}) {
  final chat = PondChatProvider.forPond(pond.id);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (_) => ChangeNotifierProvider<PondChatProvider>.value(
      value: chat,
      child: PondChatSheet(
        pond: pond,
        initialTopic: topic,
        contextBuilder: contextBuilder,
      ),
    ),
  );
}

/// [showPondChat] for use inside a pond's dashboard (needs its `DashboardProvider`).
Future<void> showPondChatFromDashboard(
  BuildContext context, {
  required Pond pond,
  ChatTopic topic = ChatTopic.general,
}) {
  final dashboard = context.read<DashboardProvider>();
  return showPondChat(
    context,
    pond: pond,
    topic: topic,
    contextBuilder: () => pondChatContextFromDashboard(pond, dashboard),
  );
}

/// Compact "Ask AI" pill placed in a section header — the contextual entry
/// point into the assistant, pre-focused on that section's [topic].
class AskAiButton extends StatelessWidget {
  const AskAiButton({super.key, required this.pond, required this.topic});

  final Pond pond;
  final ChatTopic topic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: 'Ask the assistant about {0}'.trf([topic.label.toLowerCase()]),
      child: ActionChip(
        onPressed: () =>
            showPondChatFromDashboard(context, pond: pond, topic: topic),
        avatar: Icon(Icons.auto_awesome, size: 16, color: scheme.primary),
        label: Text('Ask AI'.tr),
        labelStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        backgroundColor: scheme.primary.withValues(alpha: 0.08),
        side: BorderSide(color: scheme.primary.withValues(alpha: 0.25)),
        shape: const StadiumBorder(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Floating entry point for the whole pond page.
class PondChatFab extends StatelessWidget {
  const PondChatFab({super.key, required this.pond});

  final Pond pond;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => showPondChatFromDashboard(context, pond: pond),
      icon: const Icon(Icons.auto_awesome),
      label: Text('Ask AI'.tr),
      tooltip: 'Ask the pond assistant'.tr,
    );
  }
}

class PondChatSheet extends StatefulWidget {
  const PondChatSheet({
    super.key,
    required this.pond,
    required this.initialTopic,
    required this.contextBuilder,
  });

  final Pond pond;
  final ChatTopic initialTopic;
  final Map<String, Object?> Function() contextBuilder;

  @override
  State<PondChatSheet> createState() => _PondChatSheetState();
}

class _PondChatSheetState extends State<PondChatSheet> {
  static const _maxLength = 500;

  final _controller = TextEditingController();
  final _scroll = ScrollController();
  late ChatTopic _topic = widget.initialTopic;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? preset]) {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty) return;
    _controller.clear();
    context.read<PondChatProvider>().send(
      text,
      topic: _topic,
      context: widget.contextBuilder,
    );
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: AppMotion.normal,
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chat = context.watch<PondChatProvider>();
    final messages = chat.messages;
    // The reply arrives asynchronously; keep the newest message in view.
    if (chat.sending || messages.isNotEmpty) _scrollToEnd();

    return AnimatedPadding(
      duration: AppMotion.fast,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.82,
        child: Column(
          children: [
            _Header(
              pondName: widget.pond.name,
              canClear: messages.isNotEmpty && !chat.sending,
              onClear: chat.clear,
            ),
            _TopicBar(
              selected: _topic,
              onSelected: (t) => setState(() => _topic = t),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _Bubble(
                    message: ChatMessage(
                      role: ChatRole.assistant,
                      text: _topic.greeting,
                    ),
                  ),
                  if (messages.isEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final s in _topic.suggestions)
                          ActionChip(
                            label: Text(s),
                            onPressed: () => _send(s),
                            shape: const StadiumBorder(),
                            labelStyle: theme.textTheme.labelLarge,
                          ),
                      ],
                    ),
                  ],
                  for (final m in messages) ...[
                    const SizedBox(height: AppSpacing.md),
                    _Bubble(message: m),
                  ],
                  if (chat.sending) ...[
                    const SizedBox(height: AppSpacing.md),
                    const _TypingBubble(),
                  ],
                  if (chat.error != null && !chat.sending) ...[
                    const SizedBox(height: AppSpacing.md),
                    _ErrorRow(
                      message: chat.error!,
                      onRetry: () => chat.retry(
                        topic: _topic,
                        context: widget.contextBuilder,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            _Composer(
              controller: _controller,
              enabled: !chat.sending,
              maxLength: _maxLength,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.pondName,
    required this.canClear,
    required this.onClear,
  });

  final String pondName;
  final bool canClear;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(Icons.auto_awesome, color: scheme.onPrimary, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pond assistant'.tr,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  pondName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: canClear ? onClear : null,
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear conversation'.tr,
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            tooltip: 'Close'.tr,
          ),
        ],
      ),
    );
  }
}

class _TopicBar extends StatelessWidget {
  const _TopicBar({required this.selected, required this.onSelected});

  final ChatTopic selected;
  final ValueChanged<ChatTopic> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: [
          for (final topic in ChatTopic.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: ChoiceChip(
                avatar: Icon(topic.icon, size: 16),
                label: Text(
                  topic == ChatTopic.general ? 'General'.tr : topic.label,
                ),
                selected: topic == selected,
                showCheckmark: false,
                shape: const StadiumBorder(),
                onSelected: (_) => onSelected(topic),
              ),
            ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isUser = message.isUser;
    final fg = isUser ? scheme.onPrimary : scheme.onSurface;
    const radius = Radius.circular(AppRadius.lg);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md + 2,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: isUser ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: radius,
              topRight: radius,
              bottomLeft: isUser ? radius : const Radius.circular(4),
              bottomRight: isUser ? const Radius.circular(4) : radius,
            ),
          ),
          child: SelectableText.rich(
            _formatReply(
              message.text,
              theme.textTheme.bodyMedium!.copyWith(color: fg, height: 1.4),
            ),
          ),
        ),
      ),
    );
  }
}

/// Renders the model's light formatting: `**bold**` spans and `- ` bullets.
TextSpan _formatReply(String text, TextStyle style) {
  final spans = <InlineSpan>[];
  final bold = RegExp(r'\*\*(.+?)\*\*');
  final lines = text.split('\n');
  for (final (i, rawLine) in lines.indexed) {
    final bulletMarker = RegExp(r'^\s*[-*]\s+');
    final line = bulletMarker.hasMatch(rawLine)
        ? '•  ${rawLine.replaceFirst(bulletMarker, '')}'
        : rawLine;
    var cursor = 0;
    for (final match in bold.allMatches(line)) {
      if (match.start > cursor)
        spans.add(TextSpan(text: line.substring(cursor, match.start)));
      spans.add(
        TextSpan(
          text: match.group(1),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      );
      cursor = match.end;
    }
    if (cursor < line.length) spans.add(TextSpan(text: line.substring(cursor)));
    if (i < lines.length - 1) spans.add(const TextSpan(text: '\n'));
  }
  return TextSpan(style: style, children: spans);
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Semantics(label: 'Assistant is typing'.tr, child: const _Dots()),
      ),
    );
  }
}

class _Dots extends StatefulWidget {
  const _Dots();

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Container(
              width: 7,
              height: 7,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(
                  alpha:
                      0.3 +
                      0.7 * (1 - ((_c.value * 3 - i) % 3) / 3).clamp(0.0, 1.0),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.error),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(message, style: theme.textTheme.bodySmall)),
          TextButton(onPressed: onRetry, child: Text('Retry'.tr)),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.enabled,
    required this.maxLength,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool enabled;
  final int maxLength;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: maxLength,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    hintText: 'Ask about your pond…'.tr,
                    counterText: '',
                    filled: true,
                    fillColor: scheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.xl),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                onPressed: enabled ? onSend : null,
                icon: const Icon(Icons.arrow_upward),
                tooltip: 'Send'.tr,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Text(
              'AI advice can be wrong. For disease outbreaks, contact your local BFAR office.'.tr,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
