import 'package:drift/drift.dart';

import '../../../core/db/account_scope.dart';
import '../../../core/db/local_database.dart';
import '../material_repository.dart';

final class SqliteFolderSourceStore implements FolderReconciliationRepository {
  const SqliteFolderSourceStore(this._scope, this._database);

  final AccountScope _scope;
  final LocalDatabase _database;

  @override
  Future<List<FolderSourceRecord>> listFolderSources(String bindingId) async {
    final rows = await _database
        .customSelect(
          '''SELECT relative_path, material_id, content_sha256, present
         FROM folder_source_entries
         WHERE owner_id = ? AND binding_id = ?
         ORDER BY relative_path''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(bindingId),
          ],
        )
        .get();
    return List.unmodifiable(
      rows.map(
        (row) => FolderSourceRecord(
          relativePath: row.read<String>('relative_path'),
          materialId: row.read<String>('material_id'),
          contentSha256: row.read<String>('content_sha256'),
          present: row.read<int>('present') == 1,
        ),
      ),
    );
  }

  @override
  Future<void> finishFolderScan({
    required String bindingId,
    required Set<String> inventoryPaths,
  }) async {
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final known = await _database
        .customSelect(
          '''SELECT relative_path FROM folder_source_entries
         WHERE owner_id = ? AND binding_id = ?''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(bindingId),
          ],
        )
        .get();
    final missing = known
        .map((row) => row.read<String>('relative_path'))
        .where((path) => !inventoryPaths.contains(path))
        .toList();
    if (missing.isEmpty) return;
    await _database.transaction(() async {
      await _database.batch((batch) {
        for (final path in missing) {
          batch.customStatement(
            '''UPDATE folder_source_entries SET present = 0, updated_at_ms = ?
               WHERE owner_id = ? AND binding_id = ? AND relative_path = ?''',
            [nowMs, _scope.ownerId, bindingId, path],
          );
        }
      });
    });
  }

  @override
  Future<void> saveFolderSource({
    required String bindingId,
    required String relativePath,
    required String materialId,
    required String contentSha256,
  }) async {
    await _database.customStatement(
      '''INSERT INTO folder_source_entries
           (owner_id, binding_id, relative_path, material_id, content_sha256,
            present, updated_at_ms)
         VALUES (?, ?, ?, ?, ?, 1, ?)
         ON CONFLICT (owner_id, binding_id, relative_path) DO UPDATE SET
           material_id = excluded.material_id,
           content_sha256 = excluded.content_sha256,
           present = 1,
           updated_at_ms = excluded.updated_at_ms''',
      [
        _scope.ownerId,
        bindingId,
        relativePath,
        materialId,
        contentSha256,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<void> addToFolderPlaylist({
    required String bindingId,
    required String materialId,
    required String title,
  }) async {
    final playlistId = 'folder-$bindingId';
    await _database.transaction(() async {
      await _database.customStatement(
        '''INSERT OR IGNORE INTO playlists
             (owner_id, id, title, source_binding_id, created_at_ms)
           VALUES (?, ?, ?, ?, ?)''',
        [
          _scope.ownerId,
          playlistId,
          title,
          bindingId,
          DateTime.now().toUtc().millisecondsSinceEpoch,
        ],
      );
      final exists = await _database
          .customSelect(
            '''SELECT 1 FROM playlist_entries
           WHERE owner_id = ? AND playlist_id = ? AND material_id = ?''',
            variables: [
              Variable.withString(_scope.ownerId),
              Variable.withString(playlistId),
              Variable.withString(materialId),
            ],
          )
          .get();
      if (exists.isNotEmpty) return;
      final next = await _database
          .customSelect(
            '''SELECT COALESCE(MAX(position), -1) + 1 AS next_position
           FROM playlist_entries WHERE owner_id = ? AND playlist_id = ?''',
            variables: [
              Variable.withString(_scope.ownerId),
              Variable.withString(playlistId),
            ],
          )
          .getSingle();
      await _database.customStatement(
        '''INSERT INTO playlist_entries
             (owner_id, playlist_id, material_id, position)
           VALUES (?, ?, ?, ?)''',
        [
          _scope.ownerId,
          playlistId,
          materialId,
          next.read<int>('next_position'),
        ],
      );
    });
  }
}
