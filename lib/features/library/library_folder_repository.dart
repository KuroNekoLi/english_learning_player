final class LibraryFolder {
  const LibraryFolder({
    required this.id,
    required this.title,
    required this.materialCount,
  });

  final String id;
  final String title;
  final int materialCount;
}

abstract interface class LibraryFolderRepository {
  Future<List<LibraryFolder>> listFolders();
  Future<void> createFolder(String title);
  Future<Set<String>> materialIds(String folderId);
  Future<void> addMaterial(String folderId, String materialId);
}
