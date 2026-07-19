import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// Fades + slides [child] in, delayed by `index * AppMotion.stagger`, so a
/// grid/list of cards reveals in sequence instead of popping in all at
/// once.
///
/// The delay is encoded as an [Interval] on a single [AnimationController]
/// (ticker-driven) rather than a `Future.delayed`/`Timer`, so it never
/// leaves a pending timer behind for widget tests that don't settle time.
/// Skips the animation (shows immediately) when the platform requests
/// reduced motion.
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();

    final delay = AppMotion.stagger * widget.index;
    final total = delay + AppMotion.normal;
    _controller = AnimationController(vsync: this, duration: total);

    final startFraction = delay.inMicroseconds / total.inMicroseconds;
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Interval(startFraction.clamp(0.0, 1.0), 1.0, curve: Curves.easeOut),
    );
    _opacity = curved;
    _offset = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero).animate(curved);

    final reduceMotion = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (reduceMotion) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}
