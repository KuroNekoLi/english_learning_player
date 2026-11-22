import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/sync_contracts.dart';
import '../material_repository.dart';
import '../services/media_selection_import_service.dart';
import 'audio_transfer_tile.dart';
import 'importing_audio_tile.dart';

final class LibraryMaterialList extends StatelessWidget {
  const LibraryMaterialList({
    super.key,
    required this.library,
    required this.materials,
    required this.gridMode,
    this.importProgress = const [],
    this.downloadProgress = const [],
    required this.onRetry,
    required this.onOpen,
  });

  final AsyncValue<List<LearningMaterial>> library;
  final List<LearningMaterial> materials;
  final bool gridMode;
  final List<MediaFileImportProgress> importProgress;
  final List<CloudDownloadProgress> downloadProgress;
  final VoidCallback onRetry;
  final ValueChanged<LearningMaterial> onOpen;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: library.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(onPressed: onRetry, child: const Text('無法讀取教材，重試')),
        ),
        data: (_) =>
            materials.isEmpty &&
                importProgress.isEmpty &&
                downloadProgress.isEmpty
            ? const Center(child: Text('目前沒有教材'))
            : gridMode
            ? GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 360,
                  mainAxisExtent: 124,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount:
                    _pendingDownloadProgress(materials).length +
                    importProgress.length +
                    materials.length,
                itemBuilder: (context, index) => _itemAt(index, materials),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount:
                    _pendingDownloadProgress(materials).length +
                    importProgress.length +
                    materials.length,
                itemBuilder: (context, index) => _itemAt(index, materials),
              ),
      ),
    ),
  );

  List<CloudDownloadProgress> _pendingDownloadProgress(
    List<LearningMaterial> materials,
  ) {
    final localIds = materials.map((material) => material.id).toSet();
    return downloadProgress
        .where((progress) => !localIds.contains(progress.materialId))
        .toList();
  }

  Widget _itemAt(int index, List<LearningMaterial> materials) {
    final pendingDownloads = _pendingDownloadProgress(materials);
    if (index < importProgress.length) {
      return ImportingAudioTile(progress: importProgress[index]);
    }
    final downloadIndex = index - importProgress.length;
    if (downloadIndex < pendingDownloads.length) {
      return _downloadTile(pendingDownloads[downloadIndex]);
    }
    final materialIndex = downloadIndex - pendingDownloads.length;
    return _materialTile(materials[materialIndex]);
  }

  Widget _downloadTile(CloudDownloadProgress progress) => AudioTransferTile(
    title: progress.title,
    statusText: switch (progress.phase) {
      CloudDownloadPhase.queued => '等待下載',
      CloudDownloadPhase.audio => _audioStatus(progress),
      CloudDownloadPhase.subtitles => '正在下載字幕',
      CloudDownloadPhase.failed =>
        progress.audioCached ? '教材同步未完成，請至帳號與同步重試' : '下載失敗，請至帳號與同步重試',
    },
    progress: switch (progress.phase) {
      CloudDownloadPhase.queued => 0,
      CloudDownloadPhase.audio => progress.fraction,
      CloudDownloadPhase.subtitles => 1,
      CloudDownloadPhase.failed => null,
    },
    failed: progress.phase == CloudDownloadPhase.failed,
  );

  String _audioStatus(CloudDownloadProgress progress) {
    final fraction = progress.fraction;
    return fraction == null
        ? '正在下載音訊'
        : '正在下載音訊 · ${(fraction * 100).round()}%';
  }

  Widget _materialTile(LearningMaterial material) => _MaterialTile(
    material: material,
    downloadProgress: downloadProgress
        .where((progress) => progress.materialId == material.id)
        .firstOrNull,
    onTap: () => onOpen(material),
  );
}

final class _MaterialTile extends StatelessWidget {
  const _MaterialTile({
    required this.material,
    required this.downloadProgress,
    required this.onTap,
  });

  final LearningMaterial material;
  final CloudDownloadProgress? downloadProgress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      onTap: onTap,
      minVerticalPadding: 12,
      leading: _leading(context),
      title: Text(material.title),
      subtitle: Text(_statusLabel),
      trailing: const Icon(Icons.chevron_right),
    ),
  );

  Widget _leading(BuildContext context) {
    if (downloadProgress == null) {
      return const CircleAvatar(child: Icon(Icons.headphones_rounded));
    }
    final progress = downloadProgress!;
    final theme = Theme.of(context);
    return SizedBox.square(
      dimension: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const CircleAvatar(child: Icon(Icons.headphones_rounded)),
          if (progress.phase == CloudDownloadPhase.failed)
            Icon(Icons.error_outline, color: theme.colorScheme.error)
          else if (progress.phase == CloudDownloadPhase.subtitles)
            const SizedBox.square(
              dimension: 48,
              child: CircularProgressIndicator(
                value: null,
                strokeWidth: 2.5,
                semanticsLabel: '字幕下載進度',
              ),
            ),
        ],
      ),
    );
  }

  String get _statusLabel {
    final progress = downloadProgress;
    if (progress != null) {
      return switch (progress.phase) {
        CloudDownloadPhase.queued => '等待下載字幕',
        CloudDownloadPhase.audio => '音訊下載中',
        CloudDownloadPhase.subtitles => '正在下載字幕',
        CloudDownloadPhase.failed => '教材同步未完成，請至帳號與同步重試',
      };
    }
    return _statusLabelForMaterial(material.status);
  }

  String _statusLabelForMaterial(MaterialStatus status) => switch (status) {
    MaterialStatus.importing => '匯入中',
    MaterialStatus.localReady => '已下載，可離線播放',
    MaterialStatus.uploading => '同步中',
    MaterialStatus.cloudReady => '已同步',
    MaterialStatus.error => '需要檢查',
    MaterialStatus.archived => '已封存',
  };
}
