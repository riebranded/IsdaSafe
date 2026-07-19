import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_spacing.dart';

/// Single brand seed — Material 3 derives harmonious light/dark tonal
/// palettes from one seed, so both themes should share it (only
/// `brightness` differs).
const _seedColor = Color(0xFF15803D); // deep aquaculture green

/// Status (severity) colors are a separate, fixed vocabulary from the brand
/// palette — they mean "healthy / needs attention / unsafe" and must never
/// be reinterpreted as decoration. They always ship with an icon + label, never
/// color alone (see [StatusColors] usage in `status_badge.dart`).
///
/// This is the *only* place these colors are defined — read them via
/// `Theme.of(context).extension<StatusColors>()!`.
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({
    required this.good,
    required this.warning,
    required this.critical,
  });

  final Color good;
  final Color warning;
  final Color critical;

  /// Tuned for ~4.5:1 contrast as text/icons on a light surface.
  static const light = StatusColors(
    good: Color(0xFF15803D),
    warning: Color(0xFF92400E),
    critical: Color(0xFFB91C1C),
  );

  /// Lighter, desaturated-away-from-neon tones so status text stays legible
  /// (and doesn't vibrate) on a dark surface.
  static const dark = StatusColors(
    good: Color(0xFF4ADE80),
    warning: Color(0xFFFBBF24),
    critical: Color(0xFFF87171),
  );

  @override
  StatusColors copyWith({Color? good, Color? warning, Color? critical}) {
    return StatusColors(
      good: good ?? this.good,
      warning: warning ?? this.warning,
      critical: critical ?? this.critical,
    );
  }

  @override
  StatusColors lerp(ThemeExtension<StatusColors>? other, double t) {
    if (other is! StatusColors) return this;
    return StatusColors(
      good: Color.lerp(good, other.good, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      critical: Color.lerp(critical, other.critical, t)!,
    );
  }
}

class AppTheme {
  const AppTheme._();

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: brightness,
    );
    final statusColors = isDark ? StatusColors.dark : StatusColors.light;
    final textTheme = _buildTextTheme(brightness);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      side: BorderSide(color: colorScheme.outlineVariant),
    );

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: colorScheme.surface,
      extensions: [statusColors],
      dividerColor: colorScheme.outlineVariant,
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: colorScheme.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: colorScheme.surfaceContainerLow,
        shape: shape,
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
        minVerticalPadding: AppSpacing.md,
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        backgroundColor: colorScheme.surfaceContainerHigh,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        elevation: 3,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        extendedTextStyle: textTheme.labelLarge,
      ),
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant, space: 1, thickness: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: colorScheme.primary),
      visualDensity: VisualDensity.standard,
    );
  }

  /// Lexend for display/headline/title roles (distinctive, highly legible —
  /// designed to reduce reading errors), Source Sans 3 for body/label roles
  /// (neutral, workhorse readability at small sizes).
  static TextTheme _buildTextTheme(Brightness brightness) {
    final base = ThemeData(brightness: brightness).textTheme;
    final body = GoogleFonts.sourceSans3TextTheme(base);
    final heading = GoogleFonts.lexendTextTheme(base);

    return body.copyWith(
      displayLarge: heading.displayLarge?.copyWith(fontWeight: FontWeight.w600),
      displayMedium: heading.displayMedium?.copyWith(fontWeight: FontWeight.w600),
      displaySmall: heading.displaySmall?.copyWith(fontWeight: FontWeight.w600),
      headlineLarge: heading.headlineLarge?.copyWith(fontWeight: FontWeight.w600),
      headlineMedium: heading.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
      headlineSmall: heading.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      titleLarge: heading.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: heading.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: heading.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

extension StatusColorsContext on BuildContext {
  /// Shorthand for `Theme.of(context).extension<StatusColors>()!`.
  StatusColors get statusColors => Theme.of(this).extension<StatusColors>()!;
}
