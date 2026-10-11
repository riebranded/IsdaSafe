import 'package:flutter/material.dart';

import '../l10n/tr.dart';
import '../theme/app_spacing.dart';

/// The end of a list that shows its items a page at a time: while [remaining]
/// items are hidden, it calls [onLoadMore] by itself once it's scrolled near
/// the visible area (or is already on screen). A "Load more" button stays as
/// a fallback, e.g. for screen readers. Nothing when everything is shown.
///
/// Works inside an outer scroll view (the list itself isn't one), so the
/// readings can sit under the charts on the same page.
class LazyLoadFooter extends StatefulWidget {
  const LazyLoadFooter({
    super.key,
    required this.remaining,
    required this.onLoadMore,
  });

  /// Items not shown yet.
  final int remaining;

  /// Shows the next page. Called at most once per frame.
  final VoidCallback onLoadMore;

  /// How close to the bottom (in pixels) the next page starts loading.
  static const loadAhead = 400.0;

  @override
  State<LazyLoadFooter> createState() => _LazyLoadFooterState();
}

class _LazyLoadFooterState extends State<LazyLoadFooter> {
  ScrollPosition? _position;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_maybeLoad);
      _position = position;
      position?.addListener(_maybeLoad);
    }
    _checkAfterFrame();
  }

  @override
  void didUpdateWidget(LazyLoadFooter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A page just loaded: if it didn't fill the screen, load another.
    _checkAfterFrame();
  }

  @override
  void dispose() {
    _position?.removeListener(_maybeLoad);
    super.dispose();
  }

  void _checkAfterFrame() {
    if (_scheduled || widget.remaining <= 0) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _maybeLoad();
    });
  }

  void _maybeLoad() {
    if (widget.remaining <= 0 || !mounted) return;
    final position = _position;
    // No scroll view around it: leave it to the button.
    if (position == null || !position.hasContentDimensions) return;
    // Only when this footer is near the visible area, not just when the
    // page as a whole is near its end (other content may follow the list).
    final box = context.findRenderObject() as RenderBox?;
    final viewport = position.context.notificationContext?.findRenderObject();
    if (box == null || !box.attached || viewport is! RenderBox) return;
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    if (top <= viewport.size.height + LazyLoadFooter.loadAhead) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.remaining <= 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Center(
        child: TextButton.icon(
          onPressed: widget.onLoadMore,
          icon: const Icon(Icons.expand_more),
          label: Text('Load more'.tr),
        ),
      ),
    );
  }
}
