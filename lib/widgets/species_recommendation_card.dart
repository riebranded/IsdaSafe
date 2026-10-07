import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/fish_species.dart';
import '../models/metric_type.dart';
import '../models/sensor_reading.dart';
import '../models/species_recommendation.dart';
import '../providers/dashboard_provider.dart';
import '../services/fish_species_catalog.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';
import '../l10n/tr.dart';

/// Shows the AI-predicted species for a pond's current readings, backed by
/// the Render-hosted `/predict` endpoint (see [DashboardProvider]). Renders
/// its own loading/error/success state independently of the rest of the
/// dashboard, since the free-tier server can take up to ~a minute to respond
/// after being idle.
class SpeciesRecommendationCard extends StatelessWidget {
  const SpeciesRecommendationCard({
    super.key,
    required this.recommendation,
    required this.readings,
    required this.loading,
    required this.error,
  });

  final SpeciesRecommendation? recommendation;

  /// The pond's current readings, which each species is judged against.
  final Map<MetricType, SensorReading> readings;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (loading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Asking the model for a recommendation…'.tr),
                    const SizedBox(height: 2),
                    Text(
                      'This can take up to a minute if the server has been idle.'.tr,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (error != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(error!, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => context
                            .read<DashboardProvider>()
                            .retryRecommendation(),
                        child: Text('Retry'.tr),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    final result = recommendation;
    final picked = result == null
        ? null
        : FishSpeciesCatalog.species
              .where(
                (f) =>
                    f.name == result.species || f.localName == result.species,
              )
              .firstOrNull;

    // Every species gets its own verdict for the current readings, best fit
    // first; the model's own pick (if any) leads among equals.
    final fits =
        [
          for (final species in FishSpeciesCatalog.species)
            (species: species, fit: species.fitFor(readings)),
        ]..sort((a, b) {
          final byLevel = a.fit.level.index.compareTo(b.fit.level.index);
          if (byLevel != 0) return byLevel;
          return (b.species == picked ? 1 : 0) - (a.species == picked ? 1 : 0);
        });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          children: [
            for (final (i, entry) in fits.indexed) ...[
              if (i > 0)
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
              _SpeciesRow(
                species: entry.species,
                fit: entry.fit,
                aiPick: entry.species == picked,
                confidence: entry.species == picked ? result?.confidence : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One species and its verdict: "Tilapia" with a Suitable / Partly suitable /
/// Not suitable chip, the reasons beneath when it isn't a full fit, and an
/// "AI pick" tag on the species the model chose.
class _SpeciesRow extends StatelessWidget {
  const _SpeciesRow({
    required this.species,
    required this.fit,
    required this.aiPick,
    required this.confidence,
  });

  final FishSpecies species;
  final SpeciesFit fit;
  final bool aiPick;
  final double? confidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.statusColors;
    final color = switch (fit.level) {
      Suitability.suitable => colors.good,
      Suitability.partial => colors.warning,
      Suitability.unsuitable => colors.critical,
    };
    final icon = switch (fit.level) {
      Suitability.suitable => Icons.check_circle,
      Suitability.partial => Icons.error_outline,
      Suitability.unsuitable => Icons.cancel_outlined,
    };
    final name = species.localName != species.name
        ? '${species.name} (${species.localName})'
        : species.name;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(Icons.set_meal, size: 20, color: scheme.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (aiPick)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          confidence == null
                              ? 'AI pick'.tr
                              : 'AI pick · {0}%'.trf([(confidence! * 100).toStringAsFixed(0)]),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                if (fit.issues.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    fit.issues.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  fit.level.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
