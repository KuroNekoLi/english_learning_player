import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:english_learning_player/core/db/account_database_service.dart';
import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/features/bookmarks/data/sqlite_bookmark_repository.dart';
import 'package:english_learning_player/features/bookmarks/domain/bookmark.dart';
import 'package:english_learning_player/features/bookmarks/domain/bookmark_resolver.dart';
import 'package:english_learning_player/features/library/data/sqlite_material_repository.dart';
import 'package:english_learning_player/features/library/material_repository.dart';
import 'package:english_learning_player/features/subtitles/domain/subtitle_models.dart';
import 'package:english_learning_player/features/subtitles/services/subtitle_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory root;
  late AccountDatabaseService storage;
  late AccountScope scope;
  late SqliteMaterialRepository materials;
  late SqliteBookmarkRepository bookmarks;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('elp-wp07-');
    storage = AccountDatabaseService(supportDirectory: root);
    scope = AccountScope('bookmark-owner');
    final database = await storage.open(scope);
    materials = SqliteMaterialRepository(scope: scope, database: database);
    bookmarks = SqliteBookmarkRepository(
      scope: scope,
      database: database,
      clock: () => DateTime.utc(2026, 11, 12),
    );
    await _createMaterial(materials);
  });

  tearDown(() async {
    await materials.close();
    await root.delete(recursive: true);
  });

  test(
    'bookmark survives database reopen and relocates after subtitle update',
    () async {
      final importer = SubtitleImportService(repository: materials);
      final first = await importer.importBytes(
        ownerId: scope.ownerId,
        materialId: 'material-1',
        languageTag: 'en',
        sourceName: 'lesson.en.srt',
        bytes: _srt([(1000, 2000, 'A sentence to keep.')]),
        manual: true,
        revision: 1,
        offsetMs: 100,
      );
      final oldCue = first.track.cues.single;
      final originalBookmark = await bookmarks.addBookmark(
        _bookmark(first.track, oldCue, id: 'bookmark-1'),
      );

      final updated = await importer.importBytes(
        ownerId: scope.ownerId,
        materialId: 'material-1',
        languageTag: 'en',
        sourceName: 'lesson.en.srt',
        bytes: _srt([
          (0, 800, 'New lead-in.'),
          (3000, 4000, 'A sentence to keep.'),
        ]),
        manual: true,
        revision: 2,
        offsetMs: 0,
      );
      expect(updated.track.cues.last.id, isNot(oldCue.id));

      await materials.close();
      final reopened = await storage.open(scope);
      materials = SqliteMaterialRepository(scope: scope, database: reopened);
      bookmarks = SqliteBookmarkRepository(scope: scope, database: reopened);

      final restored = (await bookmarks.listBookmarks()).single;
      expect(restored.id, originalBookmark.id);
      expect(restored.anchor.cueId, oldCue.id);
      final latestEnglish = (await materials.listSubtitleTracks('material-1'))
          .singleWhere((track) => track.isSelected);
      final resolution = const BookmarkResolver().resolve(restored, [
        latestEnglish,
      ]);

      expect(resolution.status, BookmarkResolutionStatus.resolved);
      expect(resolution.track?.revision, 2);
      expect(resolution.cue?.id, updated.track.cues.last.id);
      expect(resolution.cue?.text, 'A sentence to keep.');
      expect(await materials.listMaterials(), hasLength(1));
    },
  );

  test(
    'bookmarks are account scoped and removed entries stay hidden',
    () async {
      final track = _track(
        ownerId: scope.ownerId,
        id: 'en-track',
        revision: 1,
        cue: const SubtitleCue(
          id: 'cue-1',
          sequence: 1,
          startMs: 0,
          endMs: 1000,
          text: 'Local sentence.',
        ),
      );
      final bookmark = await bookmarks.addBookmark(
        _bookmark(track, track.cues.single, id: 'bookmark-local'),
      );
      await bookmarks.removeBookmark(bookmark.id);
      await bookmarks.removeBookmark(bookmark.id);
      expect(await bookmarks.listBookmarks(), isEmpty);
      await bookmarks.addBookmark(
        _bookmark(track, track.cues.single, id: 'bookmark-active'),
      );

      final otherScope = AccountScope('another-bookmark-owner');
      final otherDatabase = await storage.open(otherScope);
      final otherMaterials = SqliteMaterialRepository(
        scope: otherScope,
        database: otherDatabase,
      );
      final otherBookmarks = SqliteBookmarkRepository(
        scope: otherScope,
        database: otherDatabase,
      );
      await _createMaterial(otherMaterials);
      final otherBookmark = _bookmark(
        _track(
          ownerId: otherScope.ownerId,
          id: 'en-track',
          revision: 1,
          cue: track.cues.single,
        ),
        track.cues.single,
        id: 'other-owner-bookmark',
      );
      await expectLater(
        bookmarks.addBookmark(otherBookmark),
        throwsArgumentError,
      );
      await otherBookmarks.addBookmark(otherBookmark);
      expect(await bookmarks.listBookmarks(), hasLength(1));
      expect(await otherBookmarks.listBookmarks(), hasLength(1));
      await otherMaterials.close();
    },
  );

  test(
    'migrates schema v2 to v3 without losing material or subtitles',
    () async {
      final imported = await SubtitleImportService(repository: materials)
          .importBytes(
            ownerId: scope.ownerId,
            materialId: 'material-1',
            languageTag: 'en',
            sourceName: 'lesson.en.srt',
            bytes: _srt([(0, 1000, 'Existing cue.')]),
            manual: true,
          );
      final database = await storage.open(scope);
      await database.customStatement('DROP TABLE bookmarks');
      await database.customStatement('PRAGMA user_version = 2');
      await materials.close();
      await database.close();

      final upgraded = await storage.open(scope);
      materials = SqliteMaterialRepository(scope: scope, database: upgraded);
      bookmarks = SqliteBookmarkRepository(scope: scope, database: upgraded);
      expect((await materials.listMaterials()).single.id, 'material-1');
      expect(
        (await materials.listSubtitleTracks('material-1'))
            .single
            .cues
            .single
            .text,
        'Existing cue.',
      );
      expect(await bookmarks.listBookmarks(), isEmpty);
      expect(imported.track.revision, 1);
    },
  );

  test('ambiguous duplicate text and timing stays unresolved', () {
    final anchorTrack = _track(
      ownerId: scope.ownerId,
      id: 'old-track',
      revision: 1,
      cue: const SubtitleCue(
        id: 'old-cue',
        sequence: 1,
        startMs: 1000,
        endMs: 2000,
        text: 'Repeat this sentence.',
      ),
    );
    final bookmark = _bookmark(anchorTrack, anchorTrack.cues.single, id: 'b');
    final changedTrack = SubtitleTrack(
      id: 'new-track',
      ownerId: scope.ownerId,
      materialId: 'material-1',
      languageTag: 'en',
      sourceName: 'new.en.srt',
      originalBytes: const [],
      revision: 2,
      offsetMs: 0,
      selectionMode: SubtitleSelectionMode.automatic,
      isSelected: true,
      cues: const [
        SubtitleCue(
          id: 'new-a',
          sequence: 1,
          startMs: 1000,
          endMs: 2000,
          text: 'Repeat this sentence.',
        ),
        SubtitleCue(
          id: 'new-b',
          sequence: 2,
          startMs: 1000,
          endMs: 2000,
          text: 'Repeat this sentence.',
        ),
      ],
    );
    expect(
      const BookmarkResolver().resolve(bookmark, [changedTrack]).status,
      BookmarkResolutionStatus.ambiguous,
    );
    final noMatchingTrack = changedTrack.copyWith(isSelected: false);
    expect(
      const BookmarkResolver().resolve(bookmark, [noMatchingTrack]).status,
      BookmarkResolutionStatus.missing,
    );
  });
}

Bookmark _bookmark(SubtitleTrack track, SubtitleCue cue, {required String id}) {
  final start = cue.startMs + track.offsetMs;
  final end = cue.endMs + track.offsetMs;
  return Bookmark(
    id: id,
    ownerId: track.ownerId,
    materialId: track.materialId,
    anchor: BookmarkCueAnchor(
      trackId: track.id,
      trackRevision: track.revision,
      languageTag: track.languageTag,
      cueId: cue.id,
      cueText: cue.text,
      startMs: start < 0 ? 0 : start,
      endMs: end,
    ),
    createdAt: DateTime.utc(2026, 11, 12),
  );
}

SubtitleTrack _track({
  required String ownerId,
  required String id,
  required int revision,
  required SubtitleCue cue,
}) => SubtitleTrack(
  id: id,
  ownerId: ownerId,
  materialId: 'material-1',
  languageTag: 'en',
  sourceName: 'lesson.en.srt',
  originalBytes: const [],
  revision: revision,
  offsetMs: 0,
  selectionMode: SubtitleSelectionMode.automatic,
  isSelected: true,
  cues: [cue],
);

List<int> _srt(List<(int, int, String)> cues) => utf8.encode(
  cues.indexed
      .map((entry) {
        final (index, cue) = entry;
        return '${index + 1}\n${_stamp(cue.$1)} --> ${_stamp(cue.$2)}\n${cue.$3}';
      })
      .join('\n\n'),
);

String _stamp(int milliseconds) {
  final hours = milliseconds ~/ 3600000;
  final minutes = milliseconds ~/ 60000 % 60;
  final seconds = milliseconds ~/ 1000 % 60;
  final millis = milliseconds % 1000;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')},${millis.toString().padLeft(3, '0')}';
}

Future<void> _createMaterial(SqliteMaterialRepository repository) async {
  await repository.insertAudio(
    asset: const StoredAudioAsset(
      id: 'asset-1',
      sha256: 'bookmark-audio-hash',
      byteLength: 12,
      mediaType: 'audio/mpeg',
      relativePath: 'media/bookmark.mp3',
    ),
    sourceKey: 'bookmark-source',
    title: 'Bookmark lesson',
    materialId: 'material-1',
    createdAt: DateTime.utc(2026, 11, 12),
  );
}
