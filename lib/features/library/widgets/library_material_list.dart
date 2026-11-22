import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sync/sync_contracts.dart';
import '../library_folder_repository.dart';
import '../material_repository.dart';
import '../services/media_selection_import_service.dart';
import 'audio_transfer_tile.dart';
import 'importing_audio_tile.dart';
import 'library_item_menu.dart';

final class LibraryMaterialList extends StatefulWidget {
  const LibraryMaterialList({
    super.key,
    required this.library,
    required this.materials,
    required this.gridMode,
    this.importProgress = const [],
    this.downloadProgress = const [],
    this.folders = const [],
    this.onOpenFolder,
    this.onFolderAction,
    this.onMaterialAction,
    this.onRetryFolders,
    this.emptyMessage = '目前沒有教材',
    required this.onRetry,
    required this.onOpen,
  });

  final AsyncValue<List<LearningMaterial>> library;
  final List<LearningMaterial> materials;
  final bool gridMode;
  final List<MediaFileImportProgress> importProgress;
  final List<CloudDownloadProgress> downloadProgress;
  final List<LibraryFolder> folders;
  final ValueChanged<LibraryFolder>? onOpenFolder;
  final void Function(LibraryFolder, LibraryItemAction)? onFolderAction;
  final void Function(LearningMaterial, LibraryItemAction)? onMaterialAction;
  final VoidCallback? onRetryFolders;
  final String emptyMessage;
  final VoidCallback onRetry;
  final ValueChanged<LearningMaterial> onOpen;

  @override
  State<LibraryMaterialList> createState() => _LibraryMaterialListState();
}

final class _LibraryMaterialListState extends State<LibraryMaterialList> {
  bool _selecting = false;
  final Set<String> _selectedMaterialIds = {};

  void _toggleSelection(LearningMaterial material) {
    setState(() {
      if (!_selectedMaterialIds.add(material.id)) {
        _selectedMaterialIds.remove(material.id);
      }
    });
  }

  void _startSelection(LearningMaterial material) {
    setState(() {
      _selecting = true;
      _selectedMaterialIds.add(material.id);
    });
  }

  void _stopSelection() {
    setState(() {
      _selecting = false;
      _selectedMaterialIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: widget.library.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: widget.onRetry,
            child: const Text('無法讀取教材，重試'),
          ),
        ),
        data: (_) => _content(),
      ),
    ),
  );

  Widget _content() {
    final localIds = widget.materials.map((material) => material.id).toSet();
    final pendingDownloads = widget.downloadProgress
        .where((progress) => !localIds.contains(progress.materialId))
        .toList();
    final itemCount =
        widget.folders.length +
        (widget.onRetryFolders == null ? 0 : 1) +
        widget.importProgress.length +
        pendingDownloads.length +
        widget.materials.length;
    if (itemCount == 0) return Center(child: Text(widget.emptyMessage));
    const padding = EdgeInsets.all(16);
    final list = widget.gridMode
        ? GridView.builder(
            padding: padding,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 360,
              mainAxisExtent: 124,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: itemCount,
            itemBuilder: (context, index) => _itemAt(index, pendingDownloads),
          )
        : ListView.builder(
            padding: padding,
            itemCount: itemCount,
            itemBuilder: (context, index) => _itemAt(index, pendingDownloads),
          );
    if (!_selecting) return list;
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: ListTile(
            dense: true,
            title: Text('已選取 ${_selectedMaterialIds.length} 個教材'),
            trailing: TextButton(
              onPressed: _stopSelection,
              child: const Text('完成'),
            ),
          ),
        ),
        Expanded(child: list),
      ],
    );
  }

  Widget _itemAt(int index, List<CloudDownloadProgress> pendingDownloads) {
    if (widget.onRetryFolders != null) {
      if (index == 0) {
        return TextButton(
          onPressed: widget.onRetryFolders,
          child: const Text('無法讀取資料夾，重試'),
        );
      }
      index--;
    }
    if (index < widget.folders.length) {
      final folder = widget.folders[index];
      return Card(
        child: ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(folder.title),
          subtitle: Text('${folder.materialCount} 個教材'),
          trailing: widget.onFolderAction == null
              ? null
              : LibraryItemMenu(
                  folder: true,
                  onSelected: (action) =>
                      widget.onFolderAction?.call(folder, action),
                ),
          minVerticalPadding: 12,
          onTap: () => widget.onOpenFolder?.call(folder),
        ),
      );
    }
    index -= widget.folders.length;
    if (index < widget.importProgress.length) {
      return ImportingAudioTile(progress: widget.importProgress[index]);
    }
    final downloadIndex = index - widget.importProgress.length;
    if (downloadIndex < pendingDownloads.length) {
      return _downloadTile(pendingDownloads[downloadIndex]);
    }
    final materialIndex = downloadIndex - pendingDownloads.length;
    return _materialTile(widget.materials[materialIndex]);
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
    downloadProgress: widget.downloadProgress
        .where((progress) => progress.materialId == material.id)
        .firstOrNull,
    selecting: _selecting,
    selected: _selectedMaterialIds.contains(material.id),
    onSelected: () => _toggleSelection(material),
    onAction: (action) {
      if (action == LibraryItemAction.multiSelect) {
        _startSelection(material);
      } else {
        widget.onMaterialAction?.call(material, action);
      }
    },
    onTap: () =>
        _selecting ? _toggleSelection(material) : widget.onOpen(material),
  );
}

final class _MaterialTile extends StatelessWidget {
  const _MaterialTile({
    required this.material,
    required this.downloadProgress,
    required this.selecting,
    required this.selected,
    required this.onSelected,
    required this.onAction,
    required this.onTap,
  });

  final LearningMaterial material;
  final CloudDownloadProgress? downloadProgress;
  final bool selecting;
  final bool selected;
  final VoidCallback onSelected;
  final ValueChanged<LibraryItemAction> onAction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      onTap: onTap,
      minVerticalPadding: 12,
      leading: selecting
          ? Checkbox(value: selected, onChanged: (_) => onSelected())
          : _leading(context),
      title: Text(material.title),
      subtitle: Text(_statusLabel),
      trailing: selecting ? null : LibraryItemMenu(onSelected: onAction),
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
