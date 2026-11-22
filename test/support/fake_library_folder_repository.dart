import 'package:english_learning_player/features/library/library_folder_repository.dart';

final class FakeLibraryFolderRepository implements LibraryFolderRepository {
  final _folders = <String, String>{};
  final _parents = <String, String?>{};
  final _members = <String, Set<String>>{};
  final titles = <String, String>{};
  final deleted = <String>{};

  @override
  Future<void> createFolder(String title) async {
    _folders['folder-${_folders.length}'] = title;
  }

  @override
  Future<List<LibraryFolder>> listFolders() async => [
    for (final MapEntry(:key, :value) in _folders.entries)
      LibraryFolder(
        id: key,
        title: value,
        parentId: _parents[key],
        materialCount: _members[key]?.length ?? 0,
      ),
  ];

  @override
  Future<Set<String>> materialIds(String folderId) async =>
      Set.of(_members[folderId] ?? const {});

  @override
  Future<Set<String>> assignedMaterialIds() async =>
      _members.values.expand((ids) => ids).toSet();

  @override
  Future<void> addMaterial(String folderId, String materialId) async {
    (_members[folderId] ??= {}).add(materialId);
  }

  @override
  Future<void> renameFolder(String folderId, String title) async {
    _folders[folderId] = title;
  }

  @override
  Future<void> moveFolder(String folderId, String? destination) async {
    _parents[folderId] = destination;
  }

  @override
  Future<void> deleteFolder(String folderId) async {
    _folders.remove(folderId);
    _members.remove(folderId);
  }

  @override
  Future<void> renameMaterial(String materialId, String title) async {
    titles[materialId] = title;
  }

  @override
  Future<void> moveMaterial(
    String materialId,
    String? destination, {
    String? sourceFolderId,
  }) async {
    if (destination == null) {
      for (final ids in _members.values) {
        ids.remove(materialId);
      }
      return;
    }
    _members[sourceFolderId]?.remove(materialId);
    await addMaterial(destination, materialId);
  }

  @override
  Future<void> deleteMaterial(String materialId) async {
    deleted.add(materialId);
    await moveMaterial(materialId, null);
  }
}
