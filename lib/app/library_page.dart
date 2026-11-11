import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/library/library_view_model.dart';
import '../features/library/services/audio_import_service.dart';

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
            tooltip: '匯入音訊',
            onPressed: library.isLoading
                ? null
                : () => _importAudio(context, ref),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: library.when(
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
                itemCount: materials.length,
                itemBuilder: (context, index) =>
                    ListTile(title: Text(materials[index].title)),
              ),
      ),
    );
  }
}
