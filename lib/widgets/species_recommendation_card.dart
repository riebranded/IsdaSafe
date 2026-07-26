import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/species_recommendation.dart';
import '../providers/dashboard_provider.dart';
import '../services/fish_species_catalog.dart';
import '../theme/app_spacing.dart';

/// Shows the AI-predicted species for a pond's current readings, backed by
/// the Render-hosted `/predict` endpoint (see [DashboardProvider]). Renders
/// its own loading/error/success state independently of the rest of the
/// dashboard, since the free-tier server can take up to ~a minute to respond
/// after being idle.
class SpeciesRecommendationCard extends StatelessWidget {
  const SpeciesRecommendationCard({
    super.key,
    required this.recommendation,
    required this.loading,
    required this.error,
  });

  final SpeciesRecommendation? recommendation;
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
                    const Text('Asking the model for a recommendation…'),
                    const SizedBox(height: 2),
                    Text(
                      'This can take up to a minute if the server has been idle.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                        onPressed: () => context.read<DashboardProvider>().retryRecommendation(),
                        child: const Text('Retry'),
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
    if (result == null) return const SizedBox.shrink();

    final localName = FishSpeciesCatalog.byName(result.species)?.localName;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Icon(Icons.set_meal, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localName != null && localName != result.species
                        ? '${result.species} ($localName)'
                        : result.species,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Recommended for current pond conditions',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (result.confidence != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  '${(result.confidence! * 100).toStringAsFixed(0)}% confidence',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
