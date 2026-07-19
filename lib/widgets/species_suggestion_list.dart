import 'package:flutter/material.dart';

import '../models/species_match.dart';
import '../theme/app_spacing.dart';
import 'species_suggestion_card.dart';
import 'staggered_entrance.dart';

class SpeciesSuggestionList extends StatelessWidget {
  const SpeciesSuggestionList({super.key, required this.results});

  final List<SpeciesMatchResult> results;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, result) in results.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
            child: StaggeredEntrance(index: index, child: SpeciesSuggestionCard(result: result)),
          ),
      ],
    );
  }
}
