import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/media_selection_import_service.dart';
import 'audio_transfer_tile.dart';

final class ImportingAudioTile extends StatelessWidget {
  const ImportingAudioTile({super.key, required this.progress});

  final MediaFileImportProgress progress;

  @override
  Widget build(BuildContext context) {
    final fraction = progress.fraction;
    final statusText = switch (progress.status) {
      MediaFileImportStatus.pending => '等待匯入',
      MediaFileImportStatus.importing =>
        fraction == null ? '正在匯入音訊' : '正在匯入音訊 · ${(fraction * 100).round()}%',
      MediaFileImportStatus.completed => '匯入完成',
      MediaFileImportStatus.failed => '匯入失敗',
    };

    return AudioTransferTile(
      title: p.basenameWithoutExtension(progress.sourceName),
      statusText: statusText,
      progress: progress.status == MediaFileImportStatus.pending ? 0 : fraction,
      failed: progress.status == MediaFileImportStatus.failed,
      completed: progress.status == MediaFileImportStatus.completed,
    );
  }
}
