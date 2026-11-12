import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/library/library_view_model.dart';
import '../features/library/material_repository.dart';
import '../features/library/services/audio_import_service.dart';
import '../features/bookmarks/bookmarks_page.dart';
import '../features/player/player_page.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  Future<void> _importAudio(BuildContext context, WidgetRef ref) async {
    final picker = ref.read(audioFilePickerProvider);
    final source = await picker.pickAudio();
    if (source == null || !context.mounted) return;
    try {
      final importer = await ref.read(audioImportServiceProvider.future);
      final ImportResult result = await importer.importAudio(source);
      ref.invalidate(libraryViewModelProvider);
      if (context.mounted && result.wasDuplicate) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('此音訊已在教材庫')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('音訊匯入失敗')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryViewModelProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('教材庫'),
        actions: [
          IconButton(
            tooltip: '我的收藏',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const BookmarksPage()),
            ),
            icon: const Icon(Icons.bookmarks_outlined),
          ),
          IconButton(
            tooltip: '匯入音訊',
            onPressed: library.isLoading
                ? null
                : () => _importAudio(context, ref),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final content = _libraryContent(context, ref, library);
          if (constraints.maxWidth < 900) return content;
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
              Expanded(child: content),
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
  ) => Center(
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
        data: (materials) => materials.isEmpty
            ? const Center(child: Text('目前沒有教材'))
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
