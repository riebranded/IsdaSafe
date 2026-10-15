import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/tr.dart';
import '../theme/app_spacing.dart';

/// One stop of an [AppTour]: the widget to spotlight (by its [target] key)
/// and a popover explaining it. Steps without a target — or whose target
/// isn't on screen — show the popover centered over the dimmed app.
class TourStep {
  const TourStep({
    required this.title,
    required this.body,
    this.icon,
    this.target,
    this.also = const [],
    this.points = const [],
    this.onEnter,
  });

  final String title;
  final String body;
  final IconData? icon;

  /// Spotlit and scrolled into view, with the popover placed beside it.
  final GlobalKey? target;

  /// More areas spotlit along with [target], e.g. the screen a nav button
  /// opens.
  final List<GlobalKey> also;

  /// The functions found there, shown as a bullet list under [body].
  final List<String> points;

  /// Runs before the step is shown, e.g. to switch to the tab it explains.
  final VoidCallback? onEnter;
}

/// A driver.js-style guided tour: dims the app, cuts a spotlight around each
/// step's target and shows a popover beside it with Back / Next / Skip.
/// Arrow keys and Escape work on web and desktop.
class AppTour {
  const AppTour._();

  static const _seenKey = 'app_tour_seen_v1';
  static OverlayEntry? _entry;

  static bool get isShowing => _entry != null;

  /// Off in widget tests (see test/flutter_test_config.dart) so the tour
  /// doesn't cover the screens other tests drive.
  static bool autoStartEnabled = true;

  /// Whether the tour still has to be shown automatically to this user.
  /// False when storage can't be read, so the tour never pops up unasked
  /// over an app it can't remember dismissing.
  static Future<bool> shouldAutoStart() async {
    if (!autoStartEnabled) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return !(prefs.getBool(_seenKey) ?? false);
    } catch (_) {
      return false;
    }
  }

  static Future<void> _markSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_seenKey, true);
    } catch (_) {}
  }

  /// Shows [steps] over the whole app. Completes when the user finishes or
  /// skips; either way the tour won't auto-start again.
  static Future<void> start(
    BuildContext context,
    List<TourStep> steps, {
    VoidCallback? onFinish,
  }) {
    if (steps.isEmpty || _entry != null) return Future.value();
    final done = Completer<void>();
    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _TourOverlay(
        steps: steps,
        onClose: () {
          entry.remove();
          _entry = null;
          _markSeen();
          onFinish?.call();
          done.complete();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    return done.future;
  }
}

class _TourOverlay extends StatefulWidget {
  const _TourOverlay({required this.steps, required this.onClose});

  final List<TourStep> steps;
  final VoidCallback onClose;

  @override
  State<_TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<_TourOverlay> {
  final _focusNode = FocusNode(debugLabel: 'app tour');
  var _index = 0;

  /// The spotlight around the step's target, in overlay coordinates; null
  /// for a centered step. The popover sits beside it.
  Rect? _hole;

  /// Every spotlit area: [_hole] first, then the step's `also` areas.
  List<Rect> _holes = const [];

  /// Stays false until the first step is measured, so the popover doesn't
  /// flash in the middle before jumping to its target.
  var _ready = false;

  TourStep get _step => widget.steps[_index];
  bool get _isLast => _index == widget.steps.length - 1;

  @override
  void initState() {
    super.initState();
    // Steps may rebuild the app (switch tabs), which can't happen mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) => _go(0));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-measure after a resize or rotation (the layout may have switched
    // between the side panel and the bottom bar).
    MediaQuery.sizeOf(context);
    if (_ready) WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _go(int index) async {
    if (index < 0 || index >= widget.steps.length) return;
    setState(() => _index = index);
    widget.steps[index].onEnter?.call();
    // Let the app rebuild (e.g. a tab switch) before measuring the target.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted || _index != index) return;
    // Scroll a target that's further down a list into view first.
    final targetContext = _step.target?.currentContext;
    if (targetContext != null && targetContext.mounted) {
      await Scrollable.ensureVisible(
        targetContext,
        alignment: 0.5,
        duration: AppMotion.normal,
      );
      if (!mounted || _index != index) return;
    }
    _measure();
    _focusNode.requestFocus();
  }

  void _measure() {
    if (!mounted) return;
    final overlayBox = context.findRenderObject() as RenderBox?;
    if (overlayBox == null) return;
    final screen = Offset.zero & overlayBox.size;

    Rect? rectOf(GlobalKey? key) {
      final box = key?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) return null;
      final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
      final rect = (topLeft & box.size).inflate(6);
      // Off-screen or invisible targets aren't spotlit.
      if (rect.isEmpty || !screen.overlaps(rect)) return null;
      return rect.intersect(screen.deflate(2));
    }

    final hole = rectOf(_step.target);
    setState(() {
      _hole = hole;
      _holes = [?hole, for (final key in _step.also) ?rectOf(key)];
      _ready = true;
    });
  }

  void _next() => _isLast ? widget.onClose() : _go(_index + 1);
  void _back() => _go(_index - 1);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onClose();
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.enter) {
      _next();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _back();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scrim = Colors.black.withValues(alpha: 0.62);
    // A centered step animates the spotlight shut into the screen's middle.
    final size = MediaQuery.sizeOf(context);
    final holes = _holes.isEmpty
        ? [
            Rect.fromCenter(
              center: size.center(Offset.zero),
              width: 0,
              height: 0,
            ),
          ]
        : _holes;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            // Swallows every tap so the app underneath can't be used mid-tour.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: TweenAnimationBuilder<List<Rect>>(
                  tween: _HolesTween(begin: holes, end: holes),
                  duration: AppMotion.normal,
                  curve: Curves.easeOutCubic,
                  builder: (context, rects, _) => CustomPaint(
                    painter: _SpotlightPainter(
                      holes: _ready ? rects : const [],
                      scrim: scrim,
                      ring: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
            if (_ready)
              Positioned.fill(
                child: SafeArea(
                  child: CustomSingleChildLayout(
                    delegate: _PopoverLayout(
                      hole: _hole,
                      padding: MediaQuery.paddingOf(context),
                    ),
                    child: AnimatedSwitcher(
                      duration: AppMotion.normal,
                      child: _Popover(
                        key: ValueKey(_index),
                        step: _step,
                        index: _index,
                        count: widget.steps.length,
                        onBack: _index == 0 ? null : _back,
                        onNext: _next,
                        onSkip: widget.onClose,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Animates between two sets of spotlights. An area without a counterpart
/// grows out of (or shrinks into) the middle of the other set's first one.
class _HolesTween extends Tween<List<Rect>> {
  _HolesTween({required super.begin, required super.end});

  @override
  List<Rect> lerp(double t) {
    final from = begin!, to = end!;
    Rect point(List<Rect> rects) => rects.isEmpty
        ? Rect.zero
        : Rect.fromCenter(center: rects.first.center, width: 0, height: 0);
    return [
      for (var i = 0; i < math.max(from.length, to.length); i++)
        Rect.lerp(
          i < from.length ? from[i] : point(from),
          i < to.length ? to[i] : point(to),
          t,
        )!,
    ];
  }
}

/// Dims everything but [holes] and rings each in the accent color.
class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter({
    required this.holes,
    required this.scrim,
    required this.ring,
  });

  final List<Rect> holes;
  final Color scrim;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final rrects = [
      for (final hole in holes)
        if (hole.shortestSide >= 1)
          RRect.fromRectAndRadius(
            hole,
            Radius.circular(math.min(AppRadius.lg, hole.shortestSide / 2)),
          ),
    ];
    // Dim the whole screen in its own layer, then erase each spotlight out
    // of it, so the app shows through at full brightness. (Path.combine
    // cutouts don't render reliably on web.)
    final screen = Offset.zero & size;
    canvas.saveLayer(screen, Paint());
    canvas.drawRect(screen, Paint()..color = scrim);
    final clear = Paint()..blendMode = BlendMode.clear;
    for (final rrect in rrects) {
      canvas.drawRRect(rrect, clear);
    }
    canvas.restore();
    final ringPaint = Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (final rrect in rrects) {
      canvas.drawRRect(rrect, ringPaint);
    }
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      !listEquals(old.holes, holes) || old.scrim != scrim || old.ring != ring;
}

/// Places the popover beside the spotlight: below it, else above, else to
/// its right or left — whichever side has room — and centered when there's
/// no spotlight. Always kept inside the screen.
class _PopoverLayout extends SingleChildLayoutDelegate {
  const _PopoverLayout({required this.hole, required this.padding});

  /// In overlay coordinates; this layout sits inside a [SafeArea], so it's
  /// shifted by [padding] first.
  final Rect? hole;
  final EdgeInsets padding;

  static const _gap = 14.0;
  static const _margin = AppSpacing.lg;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints(
      maxWidth: math.min(380, constraints.maxWidth - 2 * _margin),
      maxHeight: math.max(
        160,
        math.min(560, constraints.maxHeight - 2 * _margin),
      ),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    double clampX(double x) =>
        x.clamp(_margin, math.max(_margin, size.width - child.width - _margin));
    double clampY(double y) => y.clamp(
      _margin,
      math.max(_margin, size.height - child.height - _margin),
    );

    final hole = this.hole?.shift(Offset(-padding.left, -padding.top));
    if (hole == null) {
      return Offset(
        (size.width - child.width) / 2,
        (size.height - child.height) / 2,
      );
    }

    final below = hole.bottom + _gap;
    final above = hole.top - _gap - child.height;
    final right = hole.right + _gap;
    final left = hole.left - _gap - child.width;
    // Targets in the side panel (or the panel itself) get the popover beside
    // them, so it doesn't cover the panel's other buttons; everything else
    // below or above.
    final preferSide =
        hole.height > size.height * 0.5 || hole.right < size.width * 0.3;

    final fitsBelow = below + child.height <= size.height - _margin;
    final fitsAbove = above >= _margin;
    final fitsRight = right + child.width <= size.width - _margin;
    final fitsLeft = left >= _margin;

    Offset vertical(double y) =>
        Offset(clampX(hole.center.dx - child.width / 2), y);
    Offset side(double x) =>
        Offset(x, clampY(hole.center.dy - child.height / 2));

    if (preferSide && fitsRight) return side(right);
    if (fitsBelow) return vertical(below);
    if (fitsAbove) return vertical(above);
    if (fitsRight) return side(right);
    if (fitsLeft) return side(left);
    return Offset(clampX(hole.center.dx - child.width / 2), clampY(below));
  }

  @override
  bool shouldRelayout(_PopoverLayout old) =>
      old.hole != hole || old.padding != padding;
}

class _Popover extends StatelessWidget {
  const _Popover({
    super.key,
    required this.step,
    required this.index,
    required this.count,
    required this.onBack,
    required this.onNext,
    required this.onSkip,
  });

  final TourStep step;
  final int index;
  final int count;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLast = index == count - 1;

    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.xs,
              0,
            ),
            child: Row(
              children: [
                if (step.icon != null) ...[
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      step.icon,
                      size: 20,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                ],
                Expanded(
                  child: Text(
                    step.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('tour-skip'),
                  onPressed: onSkip,
                  icon: const Icon(Icons.close),
                  tooltip: 'Skip tour'.tr,
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.body, style: theme.textTheme.bodyMedium),
                  for (final point in step.points)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Icon(
                              Icons.check_circle,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              point,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Text(
                  '{0} of {1}'.trf([index + 1, count]),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (onBack != null)
                  TextButton(
                    key: const ValueKey('tour-back'),
                    onPressed: onBack,
                    child: Text('Back'.tr),
                  ),
                const SizedBox(width: AppSpacing.xs),
                FilledButton(
                  key: const ValueKey('tour-next'),
                  onPressed: onNext,
                  child: Text(isLast ? 'Finish'.tr : 'Next'.tr),
                ),
              ],
            ),
          ),
          // Progress bar along the bottom edge.
          LinearProgressIndicator(
            value: (index + 1) / count,
            minHeight: 3,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ],
      ),
    );
  }
}
