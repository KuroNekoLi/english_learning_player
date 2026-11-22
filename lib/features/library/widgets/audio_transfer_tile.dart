import 'package:flutter/material.dart';

final class AudioTransferTile extends StatelessWidget {
  const AudioTransferTile({
    super.key,
    required this.title,
    required this.statusText,
    required this.progress,
    this.failed = false,
    this.completed = false,
  });

  final String title;
  final String statusText;
  final double? progress;
  final bool failed;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        minVerticalPadding: 12,
        leading: SizedBox.square(
          dimension: 56,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Icon(
                    Icons.audiotrack_rounded,
                    size: 30,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (failed)
                Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                  size: 42,
                )
              else if (!completed)
                SizedBox.square(
                  dimension: 54,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 3,
                    backgroundColor: theme.colorScheme.onSurface.withValues(
                      alpha: 0.14,
                    ),
                    semanticsLabel: '教材下載進度',
                  ),
                )
              else
                Icon(
                  Icons.check_circle,
                  color: theme.colorScheme.primary,
                  size: 25,
                ),
            ],
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(statusText),
      ),
    );
  }
}
