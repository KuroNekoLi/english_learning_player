final class LibraryFolder {
  const LibraryFolder({
    required this.id,
    required this.title,
    required this.materialCount,
    this.parentId,
  });

  final String id;
  final String title;
  final int materialCount;
  final String? parentId;
}

abstract interface class LibraryFolderRepository {
  Future<List<LibraryFolder>> listFolders();
  Future<void> createFolder(String title, {String? id, String? parentId});
  Future<Set<String>> materialIds(String folderId);
  Future<Set<String>> assignedMaterialIds();
  Future<void> addMaterial(String folderId, String materialId);
  Future<void> renameFolder(String folderId, String title);
  Future<void> moveFolder(String folderId, String? destination);
  Future<void> deleteFolder(String folderId);
  Future<void> renameMaterial(String materialId, String title);
  Future<void> moveMaterial(
    String materialId,
    String? destination, {
    String? sourceFolderId,
  });
  Future<void> deleteMaterial(String materialId);
}
