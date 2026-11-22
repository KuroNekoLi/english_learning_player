import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/library/library_folder_repository.dart';
import '../features/library/library_folder_view_model.dart';
import '../features/library/library_view_model.dart';
import '../features/library/widgets/library_material_list.dart';
import '../features/library/widgets/library_material_picker.dart';
import '../features/library/widgets/library_item_actions.dart';
import '../features/player/player_page.dart';

void openLibraryFolder(BuildContext context, LibraryFolder folder) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => LibraryFolderPage(folder: folder)),
  );
}

final class LibraryFolderPage extends ConsumerStatefulWidget {
  const LibraryFolderPage({super.key, required this.folder});

  final LibraryFolder folder;

  @override
  ConsumerState<LibraryFolderPage> createState() => _LibraryFolderPageState();
}

final class _LibraryFolderPageState extends ConsumerState<LibraryFolderPage> {
  bool _adding = false;

  Future<void> _addMaterial() async {
    setState(() => _adding = true);
    try {
      final all = ref.read(libraryViewModelProvider).requireValue;
      final current = ref
          .read(folderMaterialsProvider(widget.folder.id))
          .requireValue;
      final ids = current.map((material) => material.id).toSet();
      final material = await pickLibraryMaterial(
        context,
        title: '加入教材',
        materials: all.where((material) => !ids.contains(material.id)).toList(),
        emptyMessage: all.isEmpty ? '請先在教材庫匯入或下載教材。' : '所有教材都已加入此資料夾。',
      );
      if (material == null || !mounted) return;
      await ref
          .read(libraryFoldersProvider.notifier)
          .add(widget.folder.id, material);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('無法加入教材，請稍後重試。')));
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = folderMaterialsProvider(widget.folder.id);
    final materials = ref.watch(provider);
    final folders = ref.watch(libraryFoldersProvider);
    final current = folders.value
        ?.where((item) => item.id == widget.folder.id)
        .firstOrNull;
    if (folders.hasValue && current == null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.folder.title)),
        body: const Center(child: Text('這個資料夾已移除。')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(current?.title ?? widget.folder.title),
        actions: [
          IconButton(
            tooltip: '加入教材',
            onPressed: _adding || !materials.hasValue ? null : _addMaterial,
            icon: const Icon(Icons.playlist_add),
          ),
        ],
      ),
      body: LibraryMaterialList(
        library: materials,
        materials: materials.value ?? const [],
        gridMode: false,
        folders: (folders.value ?? const [])
            .where((item) => item.parentId == widget.folder.id)
            .toList(),
        onOpenFolder: (folder) => openLibraryFolder(context, folder),
        emptyMessage: '此資料夾尚無教材',
        onFolderAction: (folder, action) =>
            handleFolderLibraryAction(context, ref, folder, action),
        onMaterialAction: (material, action) => handleMaterialLibraryAction(
          context,
          ref,
          material,
          action,
          sourceFolderId: widget.folder.id,
        ),
        onRetry: () {
          ref.invalidate(libraryViewModelProvider);
          ref.invalidate(provider);
        },
        onOpen: (material) => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PlayerPage(material: material),
          ),
        ),
      ),
    );
  }
}
