import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/account_scope.dart';
import '../../../core/db/local_database.dart';
import '../library_folder_repository.dart';

final class SqliteLibraryFolderRepository implements LibraryFolderRepository {
  const SqliteLibraryFolderRepository(this._scope, this._database);

  final AccountScope _scope;
  final LocalDatabase _database;

  @override
  Future<List<LibraryFolder>> listFolders() async {
    final rows = await _database
        .customSelect(
          '''
      SELECT p.id, p.title, COUNT(e.material_id) AS material_count
      FROM playlists p
      LEFT JOIN playlist_entries e
        ON e.owner_id = p.owner_id AND e.playlist_id = p.id
      WHERE p.owner_id = ? AND p.source_binding_id IS NULL
      GROUP BY p.id, p.title, p.created_at_ms
      ORDER BY p.created_at_ms DESC, p.id
      ''',
          variables: [Variable.withString(_scope.ownerId)],
        )
        .get();
    return List.unmodifiable(
      rows.map(
        (row) => LibraryFolder(
          id: row.read<String>('id'),
          title: row.read<String>('title'),
          materialCount: row.read<int>('material_count'),
        ),
      ),
    );
  }

  @override
  Future<void> createFolder(String title) {
    final name = title.trim();
    if (name.isEmpty) throw ArgumentError('The folder name is empty.');
    return _database.customStatement(
      '''INSERT INTO playlists (owner_id, id, title, created_at_ms)
         VALUES (?, ?, ?, ?)''',
      [
        _scope.ownerId,
        const Uuid().v4(),
        name,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<Set<String>> materialIds(String folderId) async {
    final rows = await _database
        .customSelect(
          '''SELECT e.material_id FROM playlist_entries e
         JOIN playlists p ON p.owner_id = e.owner_id AND p.id = e.playlist_id
         WHERE e.owner_id = ? AND e.playlist_id = ? AND p.source_binding_id IS NULL''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(folderId),
          ],
        )
        .get();
    return Set.unmodifiable(rows.map((row) => row.read<String>('material_id')));
  }

  @override
  Future<void> addMaterial(String folderId, String materialId) =>
      _database.customStatement(
        '''
        INSERT INTO playlist_entries (owner_id, playlist_id, material_id, position)
        SELECT p.owner_id, p.id, m.id,
          (SELECT COALESCE(MAX(e.position), -1) + 1 FROM playlist_entries e
           WHERE e.owner_id = p.owner_id AND e.playlist_id = p.id)
        FROM playlists p
        JOIN materials m ON m.owner_id = p.owner_id AND m.id = ?
        WHERE p.owner_id = ? AND p.id = ? AND p.source_binding_id IS NULL
        ON CONFLICT (owner_id, playlist_id, material_id) DO NOTHING
        ''',
        [materialId, _scope.ownerId, folderId],
      );
}
