import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/media_selection_import_service.dart';

final class ImportingAudioTile extends StatelessWidget {
  const ImportingAudioTile({super.key, required this.progress});

  final MediaFileImportProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = progress.fraction;
    final statusText = switch (progress.status) {
      MediaFileImportStatus.pending => '等待匯入',
      MediaFileImportStatus.importing =>
        fraction == null ? '正在匯入音訊' : '正在匯入音訊 · ${(fraction * 100).round()}%',
      MediaFileImportStatus.completed => '匯入完成',
      MediaFileImportStatus.failed => '匯入失敗',
    };

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
              if (progress.status == MediaFileImportStatus.failed)
                Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                  size: 42,
                )
              else if (progress.status != MediaFileImportStatus.completed)
                SizedBox.square(
                  dimension: 54,
                  child: CircularProgressIndicator(
                    value: progress.status == MediaFileImportStatus.pending
                        ? 0
                        : fraction,
                    strokeWidth: 3,
                    backgroundColor: theme.colorScheme.onSurface.withValues(
                      alpha: 0.14,
                    ),
                    semanticsLabel: '音訊匯入進度',
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
        title: Text(
          p.basenameWithoutExtension(progress.sourceName),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(statusText),
      ),
    );
  }
}
