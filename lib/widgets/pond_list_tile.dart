import 'package:flutter/material.dart';

import '../models/pond.dart';
import '../theme/app_spacing.dart';
import 'status_badge.dart';

class PondListTile extends StatelessWidget {
  const PondListTile({
    super.key,
    required this.pond,
    required this.onTap,
    required this.onRename,
    required this.onEditLocation,
    required this.onRemove,
    this.status,
  });

  final Pond pond;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onEditLocation;
  final VoidCallback onRemove;

  /// Worst-of-5 status from the pond's latest mock reading, if known yet —
  /// gives an at-a-glance health signal without opening the dashboard.
  final ReadingStatus? status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = status?.colorOf(context) ?? theme.colorScheme.primary;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: statusColor.withValues(alpha: 0.14),
                child: Icon(Icons.water, color: statusColor),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(pond.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    if (status != null)
                      StatusBadge(status: status!)
                    else
                      Text('Tap to view latest readings', style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Pond options',
                onSelected: (value) {
                  if (value == 'rename') onRename();
                  if (value == 'location') onEditLocation();
                  if (value == 'remove') onRemove();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'location', child: Text('Edit location')),
                  PopupMenuItem(value: 'remove', child: Text('Remove')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
