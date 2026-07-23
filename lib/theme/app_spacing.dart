/// Spacing scale (4pt grid). Use these instead of hardcoding gap sizes.
class AppSpacing {
  const AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner-radius scale. 16 is the default for cards/sheets/dialogs.
class AppRadius {
  const AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}

/// Screens ≥1024px wide (Material's documented desktop/web threshold) get
/// wide-layout treatment (e.g. [AppShell]'s persistent sidebar, or a fixed
/// column count in [ReadingGrid]) instead of the mobile/responsive fallback.
const double kWideLayoutBreakpoint = 1024;

/// Shared motion durations/curves so every animation in the app shares the
/// same rhythm.
class AppMotion {
  const AppMotion._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);

  /// Per-item delay when staggering a list/grid entrance.
  static const Duration stagger = Duration(milliseconds: 40);
}
