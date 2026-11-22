import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/account_database_providers.dart';
import 'data/sqlite_library_folder_repository.dart';
import 'library_folder_repository.dart';
import 'library_view_model.dart';
import 'material_repository.dart';

final libraryFolderRepositoryProvider =
    FutureProvider.autoDispose<LibraryFolderRepository>((ref) async {
      final scope = ref.watch(accountScopeProvider);
      final database = await ref.watch(localDatabaseProvider.future);
      return SqliteLibraryFolderRepository(scope, database);
    });

final libraryFoldersProvider =
    AsyncNotifierProvider.autoDispose<
      LibraryFolderViewModel,
      List<LibraryFolder>
    >(LibraryFolderViewModel.new, retry: (_, _) => null);

final folderMaterialsProvider = FutureProvider.autoDispose
    .family<List<LearningMaterial>, String>((ref, folderId) async {
      final library = ref.watch(libraryViewModelProvider.future);
      final repository = await ref.watch(
        libraryFolderRepositoryProvider.future,
      );
      final ids = await repository.materialIds(folderId);
      return (await library)
          .where((material) => ids.contains(material.id))
          .toList();
    }, retry: (_, _) => null);

final libraryAssignedMaterialsProvider =
    FutureProvider.autoDispose<Set<String>>((ref) async {
      final repository = await ref.watch(
        libraryFolderRepositoryProvider.future,
      );
      return repository.assignedMaterialIds();
    }, retry: (_, _) => null);

final class LibraryFolderViewModel extends AsyncNotifier<List<LibraryFolder>> {
  @override
  Future<List<LibraryFolder>> build() async {
    final repository = await ref.watch(libraryFolderRepositoryProvider.future);
    return repository.listFolders();
  }

  Future<void> create(String title) =>
      _write((repository) => repository.createFolder(title));

  Future<void> add(String folderId, LearningMaterial material) => _write(
    (repository) => repository.addMaterial(folderId, material.id),
    expectedOwner: material.ownerId,
  );

  Future<void> renameFolder(String id, String title) =>
      _write((repository) => repository.renameFolder(id, title));

  Future<void> moveFolder(String id, String? destination) =>
      _write((repository) => repository.moveFolder(id, destination));

  Future<void> deleteFolder(String id) =>
      _write((repository) => repository.deleteFolder(id));

  Future<void> renameMaterial(LearningMaterial item, String title) => _write(
    (repository) => repository.renameMaterial(item.id, title),
    expectedOwner: item.ownerId,
  );

  Future<void> moveMaterial(
    LearningMaterial item,
    String? destination, {
    String? sourceFolderId,
  }) => _write(
    (repository) => repository.moveMaterial(
      item.id,
      destination,
      sourceFolderId: sourceFolderId,
    ),
    expectedOwner: item.ownerId,
  );

  Future<void> deleteMaterial(LearningMaterial item) => _write(
    (repository) => repository.deleteMaterial(item.id),
    expectedOwner: item.ownerId,
  );

  Future<void> _write(
    Future<void> Function(LibraryFolderRepository) action, {
    String? expectedOwner,
  }) async {
    final owner = ref.read(accountScopeProvider).ownerId;
    if (expectedOwner != null && expectedOwner != owner) return;
    bool isCurrent() =>
        ref.mounted && ref.read(accountScopeProvider).ownerId == owner;
    final repository = await ref.read(libraryFolderRepositoryProvider.future);
    if (!isCurrent()) return;
    await action(repository);
    if (!isCurrent()) return;
    ref.invalidate(libraryViewModelProvider);
    ref.invalidate(folderMaterialsProvider);
    ref.invalidate(libraryAssignedMaterialsProvider);
    ref.invalidateSelf();
  }
}
