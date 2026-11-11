import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/library/library_view_model.dart';

class LibraryPage extends ConsumerWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(libraryViewModelProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('教材庫')),
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
