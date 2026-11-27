import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/dictionary/widgets/word_bank_page.dart';
import '../features/library/library_view_model.dart';
import '../features/library/folder_source_view_model.dart';
import '../features/library/library_folder_view_model.dart';
import '../features/library/material_repository.dart';
import '../features/library/services/media_selection_import_service.dart';
import '../features/library/widgets/library_actions_menu.dart';
import '../features/library/widgets/library_item_actions.dart';
import '../features/library/widgets/library_material_list.dart';
import '../features/library/widgets/source_management_page.dart';
import '../features/player/player_page.dart';
import '../features/sync/firebase_sync_view_model.dart';
import 'library_folder_page.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _searchController = TextEditingController();
  bool _searching = false;
  bool _gridMode = false;
  bool _importing = false;
  List<MediaFileImportProgress> _importProgress = const [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _importAudio(BuildContext context) async {
    setState(() {
      _importing = true;
      _importProgress = const [];
    });
    try {
      final result = await ref.read(libraryImportProvider)(
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _importProgress = progress);
        },
      );
      if (result == null || !context.mounted) return;
      if (result.audioFailures > 0 || result.subtitleFailures > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '音訊失敗 ${result.audioFailures}，字幕失敗 ${result.subtitleFailures}，'
              '字幕歧義 ${result.ambiguousSubtitles}',
            ),
          ),
        );
      } else if (result.ambiguousSubtitles > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('字幕檔名有歧義 ${result.ambiguousSubtitles} 組，未自動匯入'),
          ),
        );
      } else if (result.unmatchedSubtitles > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('音訊已匯入，${result.unmatchedSubtitles} 個 SRT 未能依檔名配對。'),
          ),
        );
      } else if (result.subtitlesImported > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('音訊與 ${result.subtitlesImported} 條字幕軌已匯入。')),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('音訊匯入失敗')));
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

  void _openSourceManagement() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SourceManagementPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryViewModelProvider);
    final folderSource = ref.watch(folderSourceViewModelProvider);
    final folders = ref.watch(libraryFoldersProvider);
    final assigned =
        ref.watch(libraryAssignedMaterialsProvider).value ?? const <String>{};
    final downloadProgress = ref.watch(
      firebaseSyncViewModelProvider.select(
        (state) => state.downloadProgress.values.toList(growable: false),
      ),
    );
    final materials = library.asData?.value ?? const <LearningMaterial>[];
    final query = _searchController.text.trim().toLowerCase();
    final visibleMaterials = materials
        .where(
          (material) => query.isEmpty
              ? !assigned.contains(material.id)
              : material.title.toLowerCase().contains(query),
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜尋教材',
                  border: InputBorder.none,
                ),
                onChanged: (_) => setState(() {}),
              )
            : const Text('教材庫'),
        actions: [
          const OpenWordBankButton(),
          IconButton(
            tooltip: '播放紀錄（尚未提供）',
            onPressed: null,
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: _searching ? '關閉搜尋' : '搜尋',
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _searchController.clear();
            }),
            icon: Icon(_searching ? Icons.close : Icons.search),
          ),
          LibraryActionsMenu(
            onImportMedia: library.isLoading || _importing
                ? null
                : () => _importAudio(context),
            onImportFolder: () =>
                ref.read(folderSourceViewModelProvider.notifier).connect(),
          ),
          IconButton(
            tooltip: _gridMode ? '切換為清單' : '切換為網格',
            onPressed: () => setState(() => _gridMode = !_gridMode),
            icon: Icon(_gridMode ? Icons.view_list : Icons.grid_view),
          ),
          IconButton(
            tooltip: '設定與來源管理',
            onPressed: _openSourceManagement,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final body = Column(
            children: [
              Expanded(
                child: LibraryMaterialList(
                  library: library,
                  materials: visibleMaterials,
                  gridMode: _gridMode,
                  importProgress: [
                    ..._importProgress,
                    ...folderSource.importProgress,
                  ],
                  downloadProgress: downloadProgress,
                  folders: (folders.value ?? const [])
                      .where(
                        (folder) => query.isEmpty
                            ? folder.parentId == null
                            : folder.title.toLowerCase().contains(query),
                      )
                      .toList(),
                  onOpenFolder: (folder) => openLibraryFolder(context, folder),
                  onFolderAction: (folder, action) =>
                      handleFolderLibraryAction(context, ref, folder, action),
                  onMaterialAction: (material, action) =>
                      handleMaterialLibraryAction(
                        context,
                        ref,
                        material,
                        action,
                      ),
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
            ],
          );
          if (constraints.maxWidth < 900) return body;
          return Row(
            children: [
              SizedBox(
                width: 260,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.headphones_rounded,
                        size: 44,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'English Learning',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '離線教材庫',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ],
          );
        },
      ),
    );
  }
}
