import 'package:english_learning_player/features/library/library_folder_repository.dart';

final class FakeLibraryFolderRepository implements LibraryFolderRepository {
  final _folders = <String, String>{};
  final _members = <String, Set<String>>{};

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
        materialCount: _members[key]?.length ?? 0,
      ),
  ];

  @override
  Future<Set<String>> materialIds(String folderId) async =>
      Set.of(_members[folderId] ?? const {});

  @override
  Future<void> addMaterial(String folderId, String materialId) async {
    (_members[folderId] ??= {}).add(materialId);
  }
}
