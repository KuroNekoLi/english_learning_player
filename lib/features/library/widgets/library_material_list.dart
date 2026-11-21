import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../material_repository.dart';
import '../services/media_selection_import_service.dart';
import 'importing_audio_tile.dart';

final class LibraryMaterialList extends StatelessWidget {
  const LibraryMaterialList({
    super.key,
    required this.library,
    required this.materials,
    required this.gridMode,
    this.importProgress = const [],
    required this.onRetry,
    required this.onOpen,
  });

  final AsyncValue<List<LearningMaterial>> library;
  final List<LearningMaterial> materials;
  final bool gridMode;
  final List<MediaFileImportProgress> importProgress;
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
        data: (_) => materials.isEmpty && importProgress.isEmpty
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
                itemCount: importProgress.length + materials.length,
                itemBuilder: (context, index) => index < importProgress.length
                    ? ImportingAudioTile(progress: importProgress[index])
                    : _materialTile(index - importProgress.length),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: importProgress.length + materials.length,
                itemBuilder: (context, index) => index < importProgress.length
                    ? ImportingAudioTile(progress: importProgress[index])
                    : _materialTile(index - importProgress.length),
              ),
      ),
    ),
  );

  Widget _materialTile(int index) => _MaterialTile(
    material: materials[index],
    onTap: () => onOpen(materials[index]),
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
