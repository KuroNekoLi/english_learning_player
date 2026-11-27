import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/account_scope.dart';
import '../../../core/db/local_database.dart';
import '../domain/library_change.dart';
import '../domain/library_structure.dart';
import '../library_folder_repository.dart';
import 'sqlite_library_changes.dart';

final class SqliteLibraryFolderRepository implements LibraryFolderRepository {
  const SqliteLibraryFolderRepository(this._scope, this._database);

  final AccountScope _scope;
  final LocalDatabase _database;
  SqliteLibraryChanges get _changes =>
      SqliteLibraryChanges(_database, _scope.ownerId);

  Future<LibraryStructure> _structure() async =>
      LibraryStructure(await _changes.read());

  Future<Set<String>> _localIds() async {
    final rows = await _database
        .customSelect(
          'SELECT id FROM materials WHERE owner_id = ?',
          variables: [Variable.withString(_scope.ownerId)],
        )
        .get();
    return rows.map((row) => row.read<String>('id')).toSet();
  }

  Future<bool> _materialExists(String id) async =>
      (await _database
          .customSelect(
            'SELECT 1 FROM materials WHERE owner_id = ? AND id = ?',
            variables: [
              Variable.withString(_scope.ownerId),
              Variable.withString(id),
            ],
          )
          .getSingleOrNull()) !=
      null;

  @override
  Future<List<LibraryFolder>> listFolders() => _database.transaction(() async {
    final structure = await _structure();
    final counts = <String, int>{};
    for (final id in await _localIds()) {
      if (structure.removedMaterials.contains(id)) continue;
      for (final folder in structure.foldersFor(id)) {
        counts.update(folder, (count) => count + 1, ifAbsent: () => 1);
      }
    }
    return [
      for (final entry in structure.names.entries)
        if (structure.folderExists(entry.key))
          LibraryFolder(
            id: entry.key,
            title: entry.value,
            parentId: structure.parentOf(entry.key),
            materialCount: counts[entry.key] ?? 0,
          ),
    ]..sort((a, b) {
      final order = a.title.compareTo(b.title);
      return order != 0 ? order : a.id.compareTo(b.id);
    });
  });

  @override
  Future<Set<String>> materialIds(String folderId) =>
      _database.transaction(() async {
        final structure = await _structure();
        return {
          for (final id in await _localIds())
            if (!structure.removedMaterials.contains(id))
              if (structure.foldersFor(id).contains(folderId)) id,
        };
      });

  @override
  Future<Set<String>> assignedMaterialIds() => _database.transaction(() async {
    final structure = await _structure();
    return {
      for (final id in await _localIds())
        if (structure.foldersFor(id).isNotEmpty) id,
    };
  });

  @override
  Future<void> createFolder(String title, {String? id, String? parentId}) =>
      _database.transaction(() async {
        final folderId = id ?? const Uuid().v4();
        await _changes.edit(LibraryField.folderName, folderId, title.trim());
        if (parentId != null) {
          await _changes.edit(LibraryField.folderParent, folderId, parentId);
        }
      });

  @override
  Future<void> renameFolder(String folderId, String title) =>
      _editFolder(folderId, LibraryField.folderName, title.trim());

  @override
  Future<void> deleteFolder(String folderId) =>
      _editFolder(folderId, LibraryField.folderDeleted, '1');

  Future<void> _editFolder(String id, LibraryField field, String value) =>
      _database.transaction(() async {
        _requireFolder(await _structure(), id);
        await _changes.edit(field, id, value);
      });

  @override
  Future<void> moveFolder(
    String folderId,
    String? destination,
  ) => _database.transaction(() async {
    final structure = await _structure();
    _requireFolder(structure, folderId);
    _requireFolder(structure, destination);
    var parent = destination;
    while (parent != null) {
      if (parent == folderId) throw ArgumentError('Invalid folder destination');
      parent = structure.parentOf(parent);
    }
    await _changes.edit(LibraryField.folderParent, folderId, destination ?? '');
  });

  @override
  Future<void> addMaterial(String folderId, String materialId) =>
      _updatePlacement(materialId, folderId, add: true);

  @override
  Future<void> moveMaterial(
    String materialId,
    String? destination, {
    String? sourceFolderId,
  }) => _updatePlacement(materialId, destination, source: sourceFolderId);

  Future<void> _updatePlacement(
    String id,
    String? destination, {
    bool add = false,
    String? source,
  }) => _database.transaction(() async {
    final structure = await _structure();
    if (add &&
        (!await _materialExists(id) || !structure.folderExists(destination!))) {
      return;
    }
    await _requireMaterial(structure, id);
    _requireFolder(structure, destination);
    final placements = structure.placementsForEdit(id);
    if (add && placements.contains(destination)) return;
    if (!add) {
      if (source != null) {
        _requireFolder(structure, source);
        if (!placements.remove(source)) {
          throw StateError('Material is no longer in folder');
        }
      } else {
        placements.clear();
      }
    }
    // Moving to root removes all memberships so the item is visible there.
    if (destination == null) {
      placements.clear();
    } else {
      placements.add(destination);
    }
    await _changes.edit(
      LibraryField.materialFolders,
      id,
      jsonEncode(placements.toList()..sort()),
    );
  });

  @override
  Future<void> renameMaterial(String materialId, String title) =>
      _editMaterial(materialId, LibraryField.materialTitle, title.trim());

  @override
  Future<void> deleteMaterial(String materialId) =>
      _editMaterial(materialId, LibraryField.materialDeleted, '1');

  Future<void> _editMaterial(String id, LibraryField field, String value) =>
      _database.transaction(() async {
        await _requireMaterial(await _structure(), id);
        await _changes.edit(field, id, value);
      });

  void _requireFolder(LibraryStructure structure, String? id) {
    if (id != null && !structure.folderExists(id)) {
      throw StateError('Folder unavailable');
    }
  }

  Future<void> _requireMaterial(LibraryStructure structure, String id) async {
    if (structure.removedMaterials.contains(id) || !await _materialExists(id)) {
      throw StateError('Material unavailable');
    }
  }
}
