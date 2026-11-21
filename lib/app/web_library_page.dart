import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/library/library_view_model.dart';
import '../features/library/material_repository.dart';
import '../features/library/widgets/library_material_list.dart';
import '../features/player/player_page.dart';

final class WebLibraryPage extends ConsumerWidget {
  const WebLibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryViewModelProvider);
    final materials = library.asData?.value ?? const <LearningMaterial>[];
    return Scaffold(
      appBar: AppBar(
        title: const Text('教材庫'),
        actions: [
          IconButton(
            tooltip: '匯入音訊與 SRT',
            onPressed: () async {
              try {
                final result = await ref.read(libraryImportProvider)();
                if (result == null || !context.mounted) return;
                final message =
                    '音訊 ${result.importedMaterials.length} 個、'
                    '字幕 ${result.subtitlesImported} 條；'
                    '失敗 ${result.audioFailures + result.subtitleFailures}。';
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(message)));
              } catch (_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('匯入失敗，請確認檔案格式與瀏覽器儲存空間。')),
                  );
                }
              }
            },
            icon: const Icon(Icons.add),
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
