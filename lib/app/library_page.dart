import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/library/library_view_model.dart';
import '../features/library/folder_source_panel.dart';
import '../features/library/folder_source_view_model.dart';
import '../features/library/material_repository.dart';
import '../features/library/services/media_selection_import_service.dart';
import '../features/subtitles/services/subtitle_import_service.dart';
import '../features/bookmarks/bookmarks_page.dart';
import '../features/player/player_page.dart';
import '../features/sync/firebase_sync_dependencies.dart';
import '../features/sync/firebase_sync_panel.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  final _searchController = TextEditingController();
  bool _searching = false;
  bool _gridMode = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _importAudio(BuildContext context) async {
    final owner = ref.read(accountScopeProvider).ownerId;
    final picker = ref.read(audioFilePickerProvider);
    final files = await picker.pickMediaFiles();
    if (files.isEmpty ||
        !context.mounted ||
        ref.read(accountScopeProvider).ownerId != owner) {
      return;
    }
    try {
      final importer = await ref.read(audioImportServiceProvider.future);
      final repository = await ref.read(materialRepositoryProvider.future);
      if (!context.mounted || ref.read(accountScopeProvider).ownerId != owner) {
        return;
      }
      final result = await MediaSelectionImportService(
        ownerId: owner,
        repository: repository,
        audioImporter: importer,
        subtitleImporter: SubtitleImportService(repository: repository),
      ).importFiles(files);
      ref.invalidate(libraryViewModelProvider);
      if (!context.mounted) return;
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('音訊匯入失敗')));
      }
    }
  }

  void _openSourceManagement() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const _SourceManagementPage()),
    );
  }

  void _selectAddAction(String action) {
    switch (action) {
      case 'media':
        _importAudio(context);
      case 'folder':
        ref.read(folderSourceViewModelProvider.notifier).connect();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(libraryViewModelProvider);
    final materials = library.asData?.value ?? const <LearningMaterial>[];
    final query = _searchController.text.trim().toLowerCase();
    final visibleMaterials = materials
        .where((material) => material.title.toLowerCase().contains(query))
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
          MenuAnchor(
            menuChildren: [
              MenuItemButton(
                leadingIcon: const Icon(Icons.download_outlined),
                onPressed: library.isLoading
                    ? null
                    : () => _selectAddAction('media'),
                child: const Text('匯入媒體'),
              ),
              const MenuItemButton(
                leadingIcon: Icon(Icons.photo_library_outlined),
                onPressed: null,
                child: Text('從相簿匯入（尚未提供）'),
              ),
              MenuItemButton(
                leadingIcon: const Icon(Icons.drive_folder_upload_outlined),
                onPressed: () => _selectAddAction('folder'),
                child: const Text('匯入資料夾'),
              ),
              const MenuItemButton(
                leadingIcon: Icon(Icons.subtitles_outlined),
                onPressed: null,
                child: Text('匯入字幕（尚未提供）'),
              ),
              const MenuItemButton(
                leadingIcon: Icon(Icons.create_new_folder_outlined),
                onPressed: null,
                child: Text('新增資料夾（尚未提供）'),
              ),
            ],
            builder: (context, controller, child) => IconButton(
              tooltip: '新增',
              onPressed: () => controller.open(),
              icon: const Icon(Icons.add),
            ),
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
                child: _libraryContent(
                  context,
                  ref,
                  library,
                  visibleMaterials,
                  gridMode: _gridMode,
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

  Widget _libraryContent(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<LearningMaterial>> library,
    List<LearningMaterial> materials, {
    required bool gridMode,
  }) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: library.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(libraryViewModelProvider),
            child: const Text('無法讀取教材，重試'),
          ),
        ),
        data: (_) => materials.isEmpty
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
                itemCount: materials.length,
                itemBuilder: (context, index) => _MaterialTile(
                  material: materials[index],
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlayerPage(material: materials[index]),
                    ),
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: materials.length,
                itemBuilder: (context, index) => _MaterialTile(
                  material: materials[index],
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PlayerPage(material: materials[index]),
                    ),
                  ),
                ),
              ),
      ),
    ),
  );
}

final class _SourceManagementPage extends ConsumerWidget {
  const _SourceManagementPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: const Text('設定與來源管理')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const FolderSourcePanel(),
        if (ref.watch(firebaseEndpointProvider) != null)
          const FirebaseSyncPanel(),
        ListTile(
          leading: const Icon(Icons.bookmarks_outlined),
          title: const Text('我的收藏'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const BookmarksPage()),
          ),
        ),
      ],
    ),
  );
}

final class _MaterialTile extends StatelessWidget {
  const _MaterialTile({required this.material, required this.onTap});

  final LearningMaterial material;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: ListTile(
      onTap: onTap,
      minVerticalPadding: 12,
      leading: const CircleAvatar(child: Icon(Icons.headphones_rounded)),
      title: Text(material.title),
      subtitle: Text(_statusLabel(material.status)),
      trailing: const Icon(Icons.chevron_right),
    ),
  );

  String _statusLabel(MaterialStatus status) => switch (status) {
    MaterialStatus.importing => '匯入中',
    MaterialStatus.localReady => '已下載，可離線播放',
    MaterialStatus.uploading => '同步中',
    MaterialStatus.cloudReady => '已同步',
    MaterialStatus.error => '需要檢查',
    MaterialStatus.archived => '已封存',
  };
}
