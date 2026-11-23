import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/db/account_database_providers.dart';
import '../../subtitles/services/subtitle_import_service.dart';
import '../library_dependencies.dart';
import '../library_folder_repository.dart';
import '../library_folder_view_model.dart';
import '../library_view_model.dart';
import '../material_repository.dart';
import 'library_item_dialogs.dart';
import 'library_item_menu.dart';

Future<void> handleMaterialLibraryAction(
  BuildContext context,
  WidgetRef ref,
  LearningMaterial material,
  LibraryItemAction action, {
  String? sourceFolderId,
}) async {
  final owner = ref.read(accountScopeProvider).ownerId;
  if (owner != material.ownerId) return;
  switch (action) {
    case LibraryItemAction.importSubtitles:
      try {
        final count = await ref.read(librarySubtitleImportProvider)(material);
        if (!context.mounted || count == null) return;
        _showMessage(context, '「${material.title}」已匯入 $count 條字幕軌。');
      } on SubtitleLanguageDetectionException {
        if (context.mounted) {
          _showMessage(context, '無法辨識字幕語言，請檢查 SRT 內容與檔名。');
        }
      } catch (_) {
        if (context.mounted) {
          _showMessage(context, '字幕匯入失敗，請確認檔案是有效的 SRT。');
        }
      }
    case LibraryItemAction.information:
      final tracks = await ref
          .read(materialRepositoryProvider.future)
          .then((repository) => repository.listSubtitleTracks(material.id));
      if (!context.mounted || !_isCurrent(ref, owner)) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('教材資訊'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('名稱：${material.title}'),
              Text('狀態：${_materialStatusLabel(material.status)}'),
              Text('字幕軌：${tracks.length}'),
              Text('建立時間：${material.createdAt.toLocal()}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('關閉'),
            ),
          ],
        ),
      );
    case LibraryItemAction.rename:
    case LibraryItemAction.move:
    case LibraryItemAction.delete:
      await _editItem(
        context,
        ref,
        owner,
        action,
        material.title,
        sourceFolderId: sourceFolderId,
        rename: (vm, title) => vm.renameMaterial(material, title),
        move: (vm, destination) => vm.moveMaterial(
          material,
          destination,
          sourceFolderId: sourceFolderId,
        ),
        delete: (vm) => vm.deleteMaterial(material),
      );
    case LibraryItemAction.multiSelect:
    case LibraryItemAction.generateSubtitles:
      return;
  }
}

Future<void> handleFolderLibraryAction(
  BuildContext context,
  WidgetRef ref,
  LibraryFolder folder,
  LibraryItemAction action,
) async {
  if (action == LibraryItemAction.information) {
    await showLibraryFolderInformation(context, folder);
    return;
  }
  await _editItem(
    context,
    ref,
    ref.read(accountScopeProvider).ownerId,
    action,
    folder.title,
    folderId: folder.id,
    sourceFolderId: folder.parentId,
    rename: (vm, title) => vm.renameFolder(folder.id, title),
    move: (vm, destination) => vm.moveFolder(folder.id, destination),
    delete: (vm) => vm.deleteFolder(folder.id),
  );
}

Future<void> _editItem(
  BuildContext context,
  WidgetRef ref,
  String owner,
  LibraryItemAction action,
  String title, {
  String? folderId,
  String? sourceFolderId,
  required Future<void> Function(LibraryFolderViewModel, String) rename,
  required Future<void> Function(LibraryFolderViewModel, String?) move,
  required Future<void> Function(LibraryFolderViewModel) delete,
}) async {
  LibraryFolderViewModel viewModel() =>
      ref.read(libraryFoldersProvider.notifier);
  try {
    switch (action) {
      case LibraryItemAction.rename:
        final value = await showDialog<String>(
          context: context,
          builder: (_) => RenameLibraryItemDialog(title),
        );
        if (value == null || !context.mounted || !_isCurrent(ref, owner)) {
          return;
        }
        await rename(viewModel(), value);
      case LibraryItemAction.move:
        final folders = await ref.read(libraryFoldersProvider.future);
        if (!context.mounted || !_isCurrent(ref, owner)) return;
        final destination = await pickLibraryDestination(
          context,
          folders,
          folderId,
          sourceFolderId,
        );
        if (destination == null ||
            !context.mounted ||
            !_isCurrent(ref, owner)) {
          return;
        }
        await move(viewModel(), destination.id);
      case LibraryItemAction.delete:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('刪除「$title」？'),
            content: Text(
              folderId == null
                  ? '教材將從教材庫移除。已開啟同步的裝置也會移除這份教材，學習紀錄會保留。'
                  : '資料夾內的教材與子資料夾會移到上一層。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('刪除'),
              ),
            ],
          ),
        );
        if (confirmed != true || !context.mounted || !_isCurrent(ref, owner)) {
          return;
        }
        await delete(viewModel());
      default:
        return;
    }
  } catch (_) {
    if (context.mounted && _isCurrent(ref, owner)) {
      _showMessage(context, '無法完成這項操作，請重新整理教材庫後再試。');
    }
  }
}

bool _isCurrent(WidgetRef ref, String owner) =>
    ref.read(accountScopeProvider).ownerId == owner;

Future<void> showLibraryFolderInformation(
  BuildContext context,
  LibraryFolder folder,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('資料夾資訊'),
    content: Text('名稱：${folder.title}\n教材數：${folder.materialCount}'),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('關閉'),
      ),
    ],
  ),
);

String _materialStatusLabel(MaterialStatus status) => switch (status) {
  MaterialStatus.importing => '匯入中',
  MaterialStatus.localReady => '已下載，可離線播放',
  MaterialStatus.uploading => '同步中',
  MaterialStatus.cloudReady => '已同步',
  MaterialStatus.error => '需要檢查',
  MaterialStatus.archived => '已封存',
};

void _showMessage(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
