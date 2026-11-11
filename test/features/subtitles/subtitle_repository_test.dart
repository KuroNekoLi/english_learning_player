import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:english_learning_player/core/db/account_database_service.dart';
import 'package:english_learning_player/core/db/account_scope.dart';
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
  late SqliteMaterialRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('elp-subtitles-');
    storage = AccountDatabaseService(supportDirectory: root);
    scope = AccountScope('subtitle-owner');
    repository = SqliteMaterialRepository(
      scope: scope,
      database: await storage.open(scope),
    );
    await _createMaterial(repository);
  });

  tearDown(() async {
    await repository.close();
    await root.delete(recursive: true);
  });

  test(
    'preserves exact original bytes and cues after database reopen',
    () async {
      final bytes = [
        0xef,
        0xbb,
        0xbf,
        ...'1\r\n00:00:01,000 --> 00:00:02,000\r\nFirst\r\nsecond'.codeUnits,
      ];
      final result = await _importer(repository).importBytes(
        ownerId: scope.ownerId,
        materialId: 'material-1',
        languageTag: 'en',
        sourceName: '/private/authorized/lesson.en.srt',
        bytes: bytes,
        manual: true,
        offsetMs: 250,
      );
      expect(result.track.isSelected, isTrue);
      expect(result.track.originalBytes, bytes);

      await repository.close();
      repository = SqliteMaterialRepository(
        scope: scope,
        database: await storage.open(scope),
      );
      final restored = (await repository.listSubtitleTracks(
        'material-1',
      )).single;

      expect(restored.originalBytes, bytes);
      expect(restored.sourceName, 'lesson.en.srt');
      expect(restored.selectionMode, SubtitleSelectionMode.manual);
      expect(restored.offsetMs, 250);
      expect(restored.cues.single.sequence, 1);
      expect(restored.cues.single.text, 'First\nsecond');
      expect(restored.cues.single.startMs, 1000);
      expect(restored.cues.single.endMs, 2000);
      expect((await repository.listMaterials()).single.id, 'material-1');
    },
  );

  test('automatic tracks cannot replace a manual selection', () async {
    final importer = _importer(repository);
    final automatic = await importer.importBytes(
      ownerId: scope.ownerId,
      materialId: 'material-1',
      languageTag: 'en',
      sourceName: 'lesson.en.srt',
      bytes: _srt('Auto one'),
      manual: false,
    );
    final manual = await importer.importBytes(
      ownerId: scope.ownerId,
      materialId: 'material-1',
      languageTag: 'en-US',
      sourceName: 'personal.srt',
      bytes: _srt('Chosen by user'),
      manual: true,
    );
    final laterAutomatic = await importer.importBytes(
      ownerId: scope.ownerId,
      materialId: 'material-1',
      languageTag: 'en',
      sourceName: 'lesson.en-US.srt',
      bytes: _srt('Auto two'),
      manual: false,
    );
    final tracks = await repository.listSubtitleTracks('material-1');

    expect(automatic.track.isSelected, isTrue);
    expect(manual.track.isSelected, isTrue);
    expect(laterAutomatic.track.isSelected, isFalse);
    expect(tracks.where((track) => track.isSelected), hasLength(1));
    expect(tracks.singleWhere((track) => track.isSelected).id, manual.track.id);
    expect(
      tracks.singleWhere((track) => track.id == automatic.track.id).isSelected,
      isFalse,
    );
  });

  test(
    'a language track can be imported after initially being absent',
    () async {
      final importer = _importer(repository);
      await importer.importBytes(
        ownerId: scope.ownerId,
        materialId: 'material-1',
        languageTag: 'en',
        sourceName: 'lesson.en.srt',
        bytes: _srt('English'),
        manual: false,
      );
      expect(await repository.listSubtitleTracks('material-1'), hasLength(1));

      await importer.importBytes(
        ownerId: scope.ownerId,
        materialId: 'material-1',
        languageTag: 'zh-TW',
        sourceName: 'lesson.zh-TW.srt',
        bytes: _srt('中文'),
        manual: false,
      );
      final tracks = await repository.listSubtitleTracks('material-1');
      expect(
        tracks.map((track) => track.languageTag),
        containsAll(['en', 'zh-TW']),
      );
    },
  );

  test(
    'migrates a WP-02 v1 database without losing existing materials',
    () async {
      await repository.close();
      final versionOne = await storage.open(scope);
      await versionOne.customStatement('DROP TABLE subtitle_cues');
      await versionOne.customStatement('DROP TABLE subtitle_tracks');
      await versionOne.customStatement('PRAGMA user_version = 1');
      await versionOne.close();

      repository = SqliteMaterialRepository(
        scope: scope,
        database: await storage.open(scope),
      );
      expect((await repository.listMaterials()).single.id, 'material-1');
      expect(await repository.listSubtitleTracks('material-1'), isEmpty);
    },
  );
}

SubtitleImportService _importer(SqliteMaterialRepository repository) =>
    SubtitleImportService(repository: repository);

List<int> _srt(String line) =>
    utf8.encode('1\n00:00:00,000 --> 00:00:01,000\n$line');

Future<void> _createMaterial(SqliteMaterialRepository repository) async {
  await repository.insertAudio(
    asset: const StoredAudioAsset(
      id: 'asset-1',
      sha256: 'audio-hash',
      byteLength: 10,
      mediaType: 'audio/mpeg',
      relativePath: 'media/audio.mp3',
    ),
    sourceKey: 'source-1',
    title: 'Lesson',
    materialId: 'material-1',
    createdAt: DateTime.utc(2026),
  );
}
