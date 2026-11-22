import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/library/library_view_model.dart';
import '../features/library/library_folder_view_model.dart';
import '../features/library/material_repository.dart';
import '../features/library/services/media_selection_import_service.dart';
import '../features/library/widgets/library_actions_menu.dart';
import '../features/library/widgets/library_material_list.dart';
import '../features/auth/web/web_account_page.dart';
import '../features/player/player_page.dart';
import '../features/sync/firebase_sync_view_model.dart';
import 'library_folder_page.dart';

final class WebLibraryPage extends ConsumerStatefulWidget {
  const WebLibraryPage({super.key});

  @override
  ConsumerState<WebLibraryPage> createState() => _WebLibraryPageState();
}

final class _WebLibraryPageState extends ConsumerState<WebLibraryPage> {
  bool _importing = false;
  List<MediaFileImportProgress> _importProgress = const [];

  Future<void> _importMedia() async {
    setState(() {
      _importing = true;
      _importProgress = const [];
    });
    try {
      final result = await ref.read(libraryImportProvider)(
        onProgress: (progress) {
          if (mounted) setState(() => _importProgress = progress);
        },
      );
      if (result == null || !mounted) return;
      final message =
          '音訊 ${result.importedMaterials.length} 個、'
          '字幕 ${result.subtitlesImported} 條；'
          '失敗 ${result.audioFailures + result.subtitleFailures}、'
          '未配對 SRT ${result.unmatchedSubtitles}、'
          '歧義 ${result.ambiguousSubtitles}。';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('匯入失敗，請確認檔案格式與瀏覽器儲存空間。')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _importProgress = const [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryViewModelProvider);
    final folders = ref.watch(libraryFoldersProvider);
    final downloadProgress = ref.watch(
      firebaseSyncViewModelProvider.select(
        (state) => state.downloadProgress.values.toList(growable: false),
      ),
    );
    final materials = library.asData?.value ?? const <LearningMaterial>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('教材庫'),
        actions: [
          LibraryActionsMenu(onImportMedia: _importing ? null : _importMedia),
          IconButton(
            tooltip: '帳號與同步',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const WebAccountPage()),
            ),
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: LibraryMaterialList(
            library: library,
            materials: materials,
            gridMode: false,
            importProgress: _importProgress,
            downloadProgress: downloadProgress,
            folders: folders.value ?? const [],
            onOpenFolder: (folder) => openLibraryFolder(context, folder),
            onRetryFolders: folders.hasError
                ? () => ref.invalidate(libraryFoldersProvider)
                : null,
            onRetry: () => ref.invalidate(libraryViewModelProvider),
            onOpen: (material) => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PlayerPage(material: material),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
