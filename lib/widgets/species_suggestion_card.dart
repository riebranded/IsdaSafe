import 'package:flutter/material.dart';

import '../models/species_match.dart';
import '../theme/app_spacing.dart';
import 'status_badge.dart';

ReadingStatus _statusFor(MatchVerdict verdict) {
  switch (verdict) {
    case MatchVerdict.suitable:
      return ReadingStatus.normal;
    case MatchVerdict.marginal:
      return ReadingStatus.warning;
    case MatchVerdict.unsuitable:
      return ReadingStatus.critical;
  }
}

class SpeciesSuggestionCard extends StatelessWidget {
  const SpeciesSuggestionCard({super.key, required this.result});

  final SpeciesMatchResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _statusFor(result.verdict);
    final matchCount = result.details.where((d) => d.inRange).length;

    return Card(
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        title: Text(
          '${result.species.name} (${result.species.localName})',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            '$matchCount of ${result.details.length} conditions met',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        trailing: StatusBadge(status: status),
        childrenPadding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final detail in result.details)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    detail.inRange ? Icons.check : Icons.close,
                    size: 16,
                    color: detail.inRange
                        ? ReadingStatus.normal.colorOf(context)
                        : ReadingStatus.critical.colorOf(context),
                  ),
                  const SizedBox(width: AppSpacing.xs + 2),
                  Expanded(
                    child: Text(detail.note, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
