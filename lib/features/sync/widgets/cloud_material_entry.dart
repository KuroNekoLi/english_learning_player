import 'package:flutter/material.dart';

import '../../../core/sync/sync_contracts.dart';
import '../../progress/domain/progress_models.dart';

final class CloudMaterialEntry extends StatelessWidget {
  const CloudMaterialEntry({
    super.key,
    required this.material,
    required this.conflicts,
    required this.isLocal,
    required this.autoSyncEnabled,
    this.downloadProgress,
    required this.onDownload,
    required this.onResolve,
  });

  final CloudMaterialMetadata material;
  final List<ProgressCandidate> conflicts;
  final bool isLocal;
  final bool autoSyncEnabled;
  final CloudDownloadProgress? downloadProgress;
  final VoidCallback? onDownload;
  final ValueChanged<ProgressCandidate>? onResolve;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ListTile(title: Text(material.title), trailing: _downloadStatus(context)),
      for (final candidate in conflicts)
        TextButton(
          onPressed: onResolve == null ? null : () => onResolve!(candidate),
          child: Text('選擇「${material.title}」的續播位置'),
        ),
    ],
  );

  Widget _downloadStatus(BuildContext context) {
    if (isLocal && downloadProgress == null) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(Icons.download_done), SizedBox(width: 4), Text('已下載')],
      );
    }
    final progress = downloadProgress;
    if (progress == null) {
      if (autoSyncEnabled) return const Text('等待同步');
      return TextButton(onPressed: onDownload, child: const Text('下載'));
    }
    return switch (progress.phase) {
      CloudDownloadPhase.queued => const Text('等待下載'),
      CloudDownloadPhase.audio => _activeStatus('正在下載', progress.fraction),
      CloudDownloadPhase.subtitles => _activeStatus('正在下載字幕', null),
      CloudDownloadPhase.failed => TextButton(
        onPressed: onDownload,
        child: const Text('重新同步'),
      ),
    };
  }

  Widget _activeStatus(String label, double? fraction) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(value: fraction, strokeWidth: 2),
      ),
      const SizedBox(width: 8),
      Text(label),
    ],
  );
}
