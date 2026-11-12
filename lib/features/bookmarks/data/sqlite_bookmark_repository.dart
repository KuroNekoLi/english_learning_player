import 'package:drift/drift.dart';

import '../../../core/db/account_scope.dart';
import '../../../core/db/local_database.dart';
import '../bookmark_repository.dart';
import '../domain/bookmark.dart';

final class SqliteBookmarkRepository implements BookmarkRepository {
  const SqliteBookmarkRepository({
    required AccountScope scope,
    required LocalDatabase database,
    DateTime Function()? clock,
  }) : _scope = scope,
       _database = database,
       _clock = clock ?? DateTime.now;

  final AccountScope _scope;
  final LocalDatabase _database;
  final DateTime Function() _clock;

  @override
  Future<List<Bookmark>> listBookmarks() async {
    final rows = await _database
        .customSelect(
          '''
          SELECT id, owner_id, material_id, track_id, track_revision,
                 language_tag, cue_id, cue_text, start_ms, end_ms,
                 created_at_ms, deleted_at_ms
          FROM bookmarks
          WHERE owner_id = ? AND deleted_at_ms IS NULL
          ORDER BY created_at_ms DESC, id ASC
          ''',
          variables: [Variable.withString(_scope.ownerId)],
        )
        .get();
    return List.unmodifiable(rows.map(_bookmarkFromRow));
  }

  @override
  Future<Bookmark?> findForAnchor({
    required String materialId,
    required BookmarkCueAnchor anchor,
  }) async {
    final rows = await _database
        .customSelect(
          '''
          SELECT id, owner_id, material_id, track_id, track_revision,
                 language_tag, cue_id, cue_text, start_ms, end_ms,
                 created_at_ms, deleted_at_ms
          FROM bookmarks
          WHERE owner_id = ? AND material_id = ? AND track_id = ?
            AND track_revision = ? AND cue_id = ? AND deleted_at_ms IS NULL
          LIMIT 1
          ''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(materialId),
            Variable.withString(anchor.trackId),
            Variable.withInt(anchor.trackRevision),
            Variable.withString(anchor.cueId),
          ],
        )
        .get();
    return rows.isEmpty ? null : _bookmarkFromRow(rows.single);
  }

  @override
  Future<Bookmark> addBookmark(Bookmark bookmark) async {
    if (bookmark.ownerId != _scope.ownerId) {
      throw ArgumentError.value(bookmark.ownerId, 'bookmark.ownerId');
    }
    final anchor = bookmark.anchor;
    return _database.transaction(() async {
      final existing = await findForAnchor(
        materialId: bookmark.materialId,
        anchor: anchor,
      );
      if (existing != null) return existing;
      await _database.customStatement(
        '''
        INSERT INTO bookmarks
          (owner_id, id, material_id, track_id, track_revision, language_tag,
           cue_id, cue_text, start_ms, end_ms, created_at_ms, deleted_at_ms)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
        ''',
        [
          _scope.ownerId,
          bookmark.id,
          bookmark.materialId,
          anchor.trackId,
          anchor.trackRevision,
          anchor.languageTag,
          anchor.cueId,
          anchor.cueText,
          anchor.startMs,
          anchor.endMs,
          bookmark.createdAt.millisecondsSinceEpoch,
        ],
      );
      return bookmark;
    });
  }

  @override
  Future<void> removeBookmark(String bookmarkId) async {
    await _database.customStatement(
      '''
      UPDATE bookmarks SET deleted_at_ms = ?
      WHERE owner_id = ? AND id = ? AND deleted_at_ms IS NULL
      ''',
      [_clock().millisecondsSinceEpoch, _scope.ownerId, bookmarkId],
    );
  }

  Bookmark _bookmarkFromRow(QueryRow row) => Bookmark(
    id: row.read<String>('id'),
    ownerId: row.read<String>('owner_id'),
    materialId: row.read<String>('material_id'),
    anchor: BookmarkCueAnchor(
      trackId: row.read<String>('track_id'),
      trackRevision: row.read<int>('track_revision'),
      languageTag: row.read<String>('language_tag'),
      cueId: row.read<String>('cue_id'),
      cueText: row.read<String>('cue_text'),
      startMs: row.read<int>('start_ms'),
      endMs: row.read<int>('end_ms'),
    ),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('created_at_ms'),
      isUtc: true,
    ),
    deletedAt: row.readNullable<int>('deleted_at_ms') == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('deleted_at_ms'),
            isUtc: true,
          ),
  );
}
