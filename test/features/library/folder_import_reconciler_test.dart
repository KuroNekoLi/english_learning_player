import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:english_learning_player/core/db/account_database_service.dart';
import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/core/db/local_database.dart';
import 'package:english_learning_player/core/platform/folder_access_gateway.dart';
import 'package:english_learning_player/core/files/app_media_store.dart';
import 'package:english_learning_player/features/bookmarks/data/sqlite_bookmark_repository.dart';
import 'package:english_learning_player/features/bookmarks/domain/bookmark.dart';
import 'package:english_learning_player/features/library/data/sqlite_material_repository.dart';
import 'package:english_learning_player/features/library/services/audio_import_service.dart';
import 'package:english_learning_player/features/library/services/folder_import_reconciler.dart';
import 'package:english_learning_player/features/subtitles/services/subtitle_import_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:english_learning_player/core/platform/folder_access_gateway_provider.dart';
import 'package:english_learning_player/features/library/folder_source_view_model.dart';
import 'package:english_learning_player/features/library/library_view_model.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory root;
  late Directory staging;
  late AccountDatabaseService storage;
  late AccountScope scope;
  late SqliteMaterialRepository materials;
  late LocalDatabase database;
  late _StagedFolderGateway gateway;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('elp-wp12-');
    staging = Directory('${root.path}/staging')..createSync();
    storage = AccountDatabaseService(supportDirectory: root);
    scope = AccountScope('wp12-user');
    database = await storage.open(scope);
    materials = SqliteMaterialRepository(scope: scope, database: database);
    gateway = _StagedFolderGateway(staging);
    addTearDown(gateway.changes.close);
  });

  tearDown(() async {
    await materials.close();
    await root.delete(recursive: true);
  });

  FolderImportReconciler reconciler() => FolderImportReconciler(
    gateway: gateway,
    repository: materials,
    materials: materials,
    audioImporter: AudioImportService(
      repository: materials,
      mediaStore: AppMediaStore(storage: storage, scope: scope),
    ),
    subtitleImporter: SubtitleImportService(repository: materials),
    ownerId: scope.ownerId,
  );

  test(
    'restored grant and watcher import into the normal library and outbox',
    () async {
      gateway.put('A/Lesson.mp3', [1, 2, 3]);
      gateway.put('B/Lesson.mp3', [4, 5, 6]);
      final container = ProviderContainer(
        overrides: [
          folderAccessGatewayProvider.overrideWithValue(gateway),
          accountScopeProvider.overrideWithValue(scope),
          accountDatabaseServiceProvider.overrideWith((ref) async => storage),
          localDatabaseProvider.overrideWith((ref) async => database),
        ],
      );
      addTearDown(container.dispose);
      await usingState(
        container,
        () => container.read(folderSourceViewModelProvider),
      );
      expect(await materials.listMaterials(), hasLength(2));

      gateway.put('B/Lesson.en.srt', _srt('Second folder only'));
      final imported = usingState(container, gateway.notifyChange);
      await imported;
      final sources = await materials.listFolderSources(
        '$macFolderBindingId-${scope.storageKey}',
      );
      final a = sources.singleWhere((it) => it.relativePath.startsWith('A/'));
      final b = sources.singleWhere((it) => it.relativePath.startsWith('B/'));
      expect(await materials.listSubtitleTracks(a.materialId), isEmpty);
      expect(
        (await materials.listSubtitleTracks(
          b.materialId,
        )).single.cues.single.text,
        'Second folder only\n',
      );
      expect(await staging.list().toList(), isEmpty);
      expect(
        await database
            .customSelect(
              "SELECT op_id FROM sync_outbox WHERE entity_type = 'material'",
            )
            .get(),
        hasLength(2),
      );
    },
  );

  test(
    'late subtitle is imported once and restored after database reopen',
    () async {
      gateway.put('Lesson.mp3', [1, 2, 3]);
      final first = await reconciler().reconcile();
      expect(first.importedAudio, 1);
      expect(first.importedSubtitles, 0);
      final materialId = (await materials.listMaterials()).single.id;
      final outboxCount = await database
          .customSelect(
            "SELECT COUNT(*) AS count FROM sync_outbox WHERE owner_id = ? AND entity_type = 'material'",
            variables: [Variable.withString(scope.ownerId)],
          )
          .getSingle();
      expect(outboxCount.read<int>('count'), 1);
      final playlistCount = await database
          .customSelect(
            'SELECT COUNT(*) AS count FROM playlist_entries WHERE owner_id = ?',
            variables: [Variable.withString(scope.ownerId)],
          )
          .getSingle();
      expect(playlistCount.read<int>('count'), 1);

      gateway.put('Lesson.en.srt', _srt('Hello'));
      gateway.put('Lesson.zh-TW.srt', _srt('你好'));
      final late = await reconciler().reconcile();
      expect(late.importedAudio, 0);
      expect(late.importedSubtitles, 2);
      expect(await materials.listSubtitleTracks(materialId), hasLength(2));
      expect((await reconciler().reconcile()).importedSubtitles, 0);

      await materials.close();
      materials = SqliteMaterialRepository(
        scope: scope,
        database: database = await storage.open(scope),
      );
      expect(await materials.listSubtitleTracks(materialId), hasLength(2));
    },
  );

  test(
    'unique same-content rename reuses material; source removal keeps bookmark',
    () async {
      gateway.put('lesson.mp3', [4, 5, 6]);
      gateway.put('lesson.en.srt', _srt('A sentence'));
      await reconciler().reconcile();
      final material = (await materials.listMaterials()).single;
      final track = (await materials.listSubtitleTracks(material.id)).single;
      await SqliteBookmarkRepository(
        scope: scope,
        database: database,
      ).addBookmark(
        Bookmark(
          id: 'favorite-1',
          ownerId: scope.ownerId,
          materialId: material.id,
          anchor: BookmarkCueAnchor(
            trackId: track.id,
            trackRevision: track.revision,
            languageTag: track.languageTag,
            cueId: track.cues.single.id,
            cueText: track.cues.single.text,
            startMs: track.cues.single.startMs,
            endMs: track.cues.single.endMs,
          ),
          createdAt: DateTime.utc(2026),
        ),
      );

      gateway.remove('lesson.mp3');
      gateway.put('renamed.mp3', [4, 5, 6]);
      final rename = await reconciler().reconcile();
      expect(rename.renamedAudio, 1);
      expect(await materials.listMaterials(), hasLength(1));
      expect(
        (await materials.listFolderSources('primary-icloud-source'))
            .singleWhere((entry) => entry.relativePath == 'renamed.mp3')
            .materialId,
        material.id,
      );

      gateway.remove('renamed.mp3');
      final removed = await reconciler().reconcile();
      expect(removed.missingSourceEntries, 1);
      expect(await materials.listMaterials(), hasLength(1));
      expect(
        (await SqliteBookmarkRepository(
          scope: scope,
          database: database,
        ).listBookmarks()),
        hasLength(1),
      );
    },
  );

  test('ambiguous rename does not merge learning materials', () async {
    gateway.put('old-a.mp3', [7, 7]);
    gateway.put('old-b.mp3', [7, 7]);
    await reconciler().reconcile();
    gateway.remove('old-a.mp3');
    gateway.remove('old-b.mp3');
    gateway.put('newer.mp3', [7, 7]);
    final result = await reconciler().reconcile();
    expect(result.renamedAudio, 0);
    expect(await materials.listMaterials(), hasLength(3));
  });

  test('failed scan does not mark existing source as missing', () async {
    gateway.put('lesson.mp3', [6, 6, 6]);
    await reconciler().reconcile();
    gateway.failScan = true;
    await expectLater(
      reconciler().reconcile(),
      throwsA(isA<FolderAccessException>()),
    );
    final sources = await materials.listFolderSources('primary-icloud-source');
    expect(sources.single.present, isTrue);
  });

  test('pending iCloud download remains a present source', () async {
    gateway.put('lesson.mp3', [5, 4, 3]);
    await reconciler().reconcile();
    gateway.pendingPaths.add('lesson.mp3');
    final result = await reconciler().reconcile();
    expect(result.pendingDownload, 1);
    expect(result.missingSourceEntries, 0);
    expect(
      (await materials.listFolderSources(
        'primary-icloud-source',
      )).single.present,
      isTrue,
    );
  });

  test('schema v5 upgrades without losing existing materials', () async {
    gateway.put('lesson.mp3', [3, 2, 1]);
    await reconciler().reconcile();
    final id = (await materials.listMaterials()).single.id;
    await database.customStatement('DROP TABLE folder_source_entries');
    await database.customStatement('DROP TABLE playlist_entries');
    await database.customStatement('DROP TABLE playlists');
    await database.customStatement('PRAGMA user_version = 5');
    await materials.close();
    materials = SqliteMaterialRepository(
      scope: scope,
      database: database = await storage.open(scope),
    );
    expect((await materials.listMaterials()).single.id, id);
    expect(await materials.listFolderSources('primary-icloud-source'), isEmpty);
  });
}

List<int> _srt(String text) =>
    '1\n00:00:01,000 --> 00:00:02,000\n$text\n'.codeUnits;

Future<void> usingState(
  ProviderContainer container,
  void Function() trigger,
) async {
  final settled = Completer<void>();
  var started = false;
  final listener = container.listen(folderSourceViewModelProvider, (_, next) {
    if (next.isBusy) started = true;
    if (started && !next.isBusy && !settled.isCompleted) settled.complete();
  }, fireImmediately: true);
  try {
    trigger();
    await settled.future.timeout(const Duration(seconds: 5));
    expect(container.read(folderSourceViewModelProvider).error, isNull);
  } finally {
    listener.close();
  }
}

final class _StagedFolderGateway implements FolderAccessGateway {
  _StagedFolderGateway(this.directory);

  final Directory directory;
  final Map<String, List<int>> contents = {};
  final Set<String> pendingPaths = {};
  final changes = StreamController<void>.broadcast();
  void notifyChange() => changes.add(null);
  bool failScan = false;

  void put(String path, List<int> bytes) => contents[path] = bytes;
  void remove(String path) => contents.remove(path);

  @override
  Future<FolderHandle?> pickFolder(String bindingId) async =>
      (bindingId: bindingId, displayLabel: 'fixture');
  @override
  Future<GrantStatus> restoreGrant(String bindingId) async => GrantStatus.valid;
  @override
  Future<List<FolderEntry>> scan(String bindingId) async {
    if (failScan) throw const FolderAccessException(FolderFailure.transientIo);
    return [
      for (final path in contents.keys)
        (
          relativePath: path,
          status: pendingPaths.contains(path)
              ? FolderEntryStatus.pendingDownload
              : FolderEntryStatus.available,
          byteLength: contents[path]!.length,
          modifiedAt: DateTime.utc(2026),
        ),
    ];
  }

  @override
  Stream<void> watch(String bindingId) => changes.stream;
  @override
  Future<Uri> stageFile(String bindingId, String relativePath) async {
    final bytes = contents[relativePath];
    if (bytes == null) {
      throw const FolderAccessException(FolderFailure.notFound);
    }
    final target = File(
      '${directory.path}/${Uri.encodeComponent(relativePath)}',
    );
    await target.writeAsBytes(bytes, flush: true);
    return target.uri;
  }

  @override
  Future<void> disconnect(String bindingId) async {}
}
