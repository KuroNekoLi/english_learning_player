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
    'splits a bilingual SRT into selectable English and Chinese tracks',
    () async {
      final bytes = utf8.encode(
        '1\n00:00:00,070 --> 00:00:02,470\n'
        'So, I want you to imagine this scenario.\n'
        '我想請你想像這樣一個情境。\n\n'
        '2\n00:00:02,920 --> 00:00:04,310\n'
        'You step out your front door.\n'
        '你走出家門。',
      );
      final tracks = await _importer(repository).importBilingualBytes(
        ownerId: scope.ownerId,
        materialId: 'material-1',
        sourceName: 'Why_We_Refuse_to_Double_Back.srt',
        bytes: bytes,
        manual: true,
      );

      expect(tracks, hasLength(2));
      final savedTracks = tracks!;
      final english = savedTracks.singleWhere(
        (track) => track.languageTag == 'en',
      );
      final chinese = savedTracks.singleWhere(
        (track) => track.languageTag == 'zh-TW',
      );
      expect(english.cues.map((cue) => cue.text), [
        'So, I want you to imagine this scenario.',
        'You step out your front door.',
      ]);
      expect(chinese.cues.map((cue) => cue.text), ['我想請你想像這樣一個情境。', '你走出家門。']);
      expect(english.isSelected, isTrue);
      expect(chinese.isSelected, isTrue);
      expect(english.originalBytes, bytes);
      expect(chinese.originalBytes, bytes);
      expect(await repository.listSubtitleTracks('material-1'), hasLength(2));
    },
  );

  test(
    'auto-detects SRT language and bilingual tracks on manual import',
    () async {
      final importer = _importer(repository);
      final english = await importer.importAutoDetectedBytes(
        ownerId: scope.ownerId,
        materialId: 'material-1',
        sourceName: 'English lesson.srt',
        bytes: _srt('A sentence to learn.'),
        manual: true,
      );
      final chinese = await importer.importAutoDetectedBytes(
        ownerId: scope.ownerId,
        materialId: 'material-1',
        sourceName: 'Chinese lesson.srt',
        bytes: _srt('這是一句中文字幕。'),
        manual: true,
      );
      final bilingualBytes = utf8.encode(
        '1\n00:00:00,000 --> 00:00:01,000\nA bilingual sentence.\n這是一句雙語字幕。',
      );
      final bilingual = await importer.importAutoDetectedBytes(
        ownerId: scope.ownerId,
        materialId: 'material-1',
        sourceName: 'Bilingual lesson.srt',
        bytes: bilingualBytes,
        manual: true,
      );

      expect(english.single.languageTag, 'en');
      expect(chinese.single.languageTag, 'zh-TW');
      expect(bilingual.map((track) => track.languageTag), ['en', 'zh-TW']);
      expect(bilingual.every((track) => track.isSelected), isTrue);
      for (final track in bilingual) {
        expect(track.originalBytes, orderedEquals(bilingualBytes));
      }
    },
  );

  test('does not guess when mixed language content cannot be split', () async {
    await expectLater(
      _importer(repository).importAutoDetectedBytes(
        ownerId: scope.ownerId,
        materialId: 'material-1',
        sourceName: 'mixed.srt',
        bytes: _srt('Learn English 學習中文'),
        manual: true,
      ),
      throwsA(isA<SubtitleLanguageDetectionException>()),
    );
    expect(await repository.listSubtitleTracks('material-1'), isEmpty);
  });

  test(
    'leaves ordinary multiline subtitle files as a single language track',
    () async {
      final result = await _importer(repository).importBilingualBytes(
        ownerId: scope.ownerId,
        materialId: 'material-1',
        sourceName: 'lesson.srt',
        bytes: _srt('A long subtitle line\ncontinues on the next line'),
        manual: true,
      );
      expect(result, isNull);
      expect(await repository.listSubtitleTracks('material-1'), isEmpty);
    },
  );

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
      await versionOne.customStatement('DROP TABLE bookmarks');
      await versionOne.customStatement('DROP TABLE material_sync_state');
      await versionOne.customStatement('DROP TABLE sync_outbox');
      await versionOne.customStatement('DROP TABLE subtitle_cues');
      await versionOne.customStatement('DROP TABLE subtitle_tracks');
      await versionOne.customStatement('PRAGMA user_version = 1');
      await versionOne.close();

      final upgraded = await storage.open(scope);
      repository = SqliteMaterialRepository(scope: scope, database: upgraded);
      expect((await repository.listMaterials()).single.id, 'material-1');
      expect(await repository.listSubtitleTracks('material-1'), isEmpty);
      final outboxRows = await upgraded
          .customSelect(
            "SELECT state, entity_id FROM sync_outbox WHERE entity_type = 'material'",
          )
          .get();
      expect(outboxRows, hasLength(1));
      expect(outboxRows.single.read<String>('state'), 'queued');
      expect(outboxRows.single.read<String>('entity_id'), 'material-1');
    },
  );

  test('v6 upgrade queues existing local subtitle tracks exactly once', () async {
    final selected = await _importer(repository).importBytes(
      ownerId: scope.ownerId,
      materialId: 'material-1',
      languageTag: 'en',
      sourceName: 'lesson.en.srt',
      bytes: _srt('Old selection'),
      manual: true,
    );
    await repository.close();
    final versionSix = await storage.open(scope);
    await versionSix.customStatement(
      "DELETE FROM sync_outbox WHERE entity_type = 'subtitle'",
    );
    await versionSix.customStatement('PRAGMA user_version = 6');
    await versionSix.close();

    for (var opens = 0; opens < 2; opens++) {
      final upgraded = await storage.open(scope);
      repository = SqliteMaterialRepository(scope: scope, database: upgraded);
      final operation = await upgraded
          .customSelect(
            "SELECT owner_id, entity_id, state FROM sync_outbox WHERE entity_type = 'subtitle'",
          )
          .getSingle();
      expect(operation.read<String>('state'), 'queued');
      expect(operation.read<String>('owner_id'), scope.ownerId);
      expect(operation.read<String>('entity_id'), 'material-1');
      final restored = (await repository.listSubtitleTracks(
        'material-1',
      )).single;
      expect(restored.id, selected.track.id);
      expect(restored.originalBytes, selected.track.originalBytes);
      if (opens == 0) await repository.close();
    }
  });

  test('subtitle track changes roll back if they cannot be enqueued', () async {
    await repository.close();
    final db = await storage.open(scope);
    repository = SqliteMaterialRepository(scope: scope, database: db);
    await db.customStatement('''
      CREATE TRIGGER reject_subtitle_outbox BEFORE INSERT ON sync_outbox
      WHEN NEW.entity_type = 'subtitle'
      BEGIN SELECT RAISE(ABORT, 'test rejects subtitle publication'); END
    ''');
    await expectLater(
      _importer(repository).importBytes(
        ownerId: scope.ownerId,
        materialId: 'material-1',
        languageTag: 'en',
        sourceName: 'lesson.en.srt',
        bytes: _srt('Local update'),
        manual: true,
      ),
      throwsA(anything),
    );
    expect(await repository.listSubtitleTracks('material-1'), isEmpty);
  });
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
