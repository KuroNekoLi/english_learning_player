import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:english_learning_player/core/db/account_database_service.dart';
import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/core/files/app_media_store.dart';
import 'package:english_learning_player/features/library/data/sqlite_material_repository.dart';
import 'package:english_learning_player/features/library/domain/audio_import_source.dart';
import 'package:english_learning_player/features/library/material_repository.dart';
import 'package:english_learning_player/features/library/services/audio_import_service.dart';
import 'package:english_learning_player/features/library/services/media_selection_import_service.dart';
import 'package:english_learning_player/features/subtitles/domain/subtitle_models.dart';
import 'package:english_learning_player/features/subtitles/services/subtitle_import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Reopening a closed file-backed DB is an intentional persistence assertion.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory root;
  late AccountDatabaseService storage;
  late AccountScope accountA;
  late AccountScope accountB;
  late SqliteMaterialRepository repositoryA;
  late SqliteMaterialRepository repositoryB;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('elp-wp02-');
    storage = AccountDatabaseService(supportDirectory: root);
    accountA = AccountScope('user-a');
    accountB = AccountScope('user-b');
    repositoryA = SqliteMaterialRepository(
      scope: accountA,
      database: await storage.open(accountA),
    );
    repositoryB = SqliteMaterialRepository(
      scope: accountB,
      database: await storage.open(accountB),
    );
  });

  tearDown(() async {
    await repositoryA.close();
    await repositoryB.close();
    await root.delete(recursive: true);
  });

  AudioImportService service(
    AccountScope scope,
    SqliteMaterialRepository repository,
  ) => AudioImportService(
    repository: repository,
    mediaStore: AppMediaStore(storage: storage, scope: scope),
  );

  AudioImportSource bytes(
    String name,
    List<int> value, {
    String sourceKey = 'same-source',
  }) => AudioImportSource(
    sourceKey: sourceKey,
    name: name,
    byteLength: value.length,
    openRead: () async* {
      yield value.sublist(0, value.length ~/ 2);
      yield value.sublist(value.length ~/ 2);
    },
  );

  test(
    'imports streamed M4A and reloads it after reopening the database',
    () async {
      final imported = await service(
        accountA,
        repositoryA,
      ).importAudio(bytes('lesson.m4a', [1, 2, 3, 4, 5]));

      expect(imported.wasDuplicate, isFalse);
      expect(imported.material.title, 'lesson');
      expect(imported.material.status, MaterialStatus.localReady);
      expect(await repositoryA.listMaterials(), hasLength(1));

      await repositoryA.close();
      repositoryA = SqliteMaterialRepository(
        scope: accountA,
        database: await storage.open(accountA),
      );
      final restored = (await repositoryA.listMaterials()).single;
      expect(restored.id, imported.material.id);
      expect(restored.ownerId, imported.material.ownerId);
      expect(restored.audioAssetId, imported.material.audioAssetId);
      expect(restored.title, imported.material.title);

      final mediaFiles = storage.mediaDirectory(accountA).listSync();
      expect(mediaFiles.whereType<File>(), hasLength(1));
      expect(await mediaFiles.whereType<File>().single.length(), 5);
    },
  );

  test(
    'imports selected audio with matching English and Chinese SRT files',
    () async {
      final audio = service(accountA, repositoryA);
      final selection = MediaSelectionImportService(
        ownerId: accountA.ownerId,
        repository: repositoryA,
        audioImporter: audio,
        subtitleImporter: SubtitleImportService(repository: repositoryA),
      );
      final result = await selection.importFiles([
        bytes('lesson.m4a', [1, 2, 3]),
        bytes('lesson.en.srt', _srt('Hello')),
        bytes('lesson.zh-TW.srt', _srt('你好')),
      ]);

      expect(result.importedMaterials, hasLength(1));
      expect(result.subtitlesImported, 2);
      final tracks = await repositoryA.listSubtitleTracks(
        result.importedMaterials.single.id,
      );
      expect(tracks.map((track) => track.languageTag), ['en', 'zh-TW']);
      expect(tracks.map((track) => track.cues.single.text), [
        'Hello\n',
        '你好\n',
      ]);
    },
  );

  test('imports explicitly selected bilingual SRT regardless of stem and reports progress', () async {
    final selection = MediaSelectionImportService(
      ownerId: accountA.ownerId,
      repository: repositoryA,
      audioImporter: service(accountA, repositoryA),
      subtitleImporter: SubtitleImportService(repository: repositoryA),
    );
    final progressSnapshots = <List<MediaFileImportProgress>>[];
    final result = await selection.importFiles([
      bytes('lesson.m4a', [1, 2, 3, 4], sourceKey: 'lesson-audio'),
      bytes(
        'captions-from-another-source.srt',
        _bilingualSrt('A sentence to learn.', '這是一句雙語字幕。'),
        sourceKey: 'lesson-subtitle',
      ),
    ], onProgress: progressSnapshots.add);

    expect(result.importedMaterials, hasLength(1));
    expect(result.subtitlesImported, 2);
    expect(result.unmatchedSubtitles, 0);
    final tracks = await repositoryA.listSubtitleTracks(
      result.importedMaterials.single.id,
    );
    expect(tracks.map((track) => track.languageTag), ['en', 'zh-TW']);
    expect(tracks.map((track) => track.cues.single.text), [
      'A sentence to learn.',
      '這是一句雙語字幕。',
    ]);
    expect(
      tracks.every(
        (track) => track.selectionMode == SubtitleSelectionMode.manual,
      ),
      isTrue,
    );
    expect(progressSnapshots.first.single.sourceName, 'lesson.m4a');
    expect(
      progressSnapshots.any(
        (snapshot) =>
            snapshot.single.bytesCopied > 0 &&
            snapshot.single.status == MediaFileImportStatus.importing,
      ),
      isTrue,
    );
    expect(
      progressSnapshots.last.single.status,
      MediaFileImportStatus.completed,
    );
    expect(progressSnapshots.last.single.fraction, 1);
  });

  test(
    'subtitle-only selection attaches to an existing matching lesson',
    () async {
      final lesson = await service(
        accountA,
        repositoryA,
      ).importAudio(bytes('lesson.mp3', [1, 2, 3]));
      final result = await MediaSelectionImportService(
        ownerId: accountA.ownerId,
        repository: repositoryA,
        audioImporter: service(accountA, repositoryA),
        subtitleImporter: SubtitleImportService(repository: repositoryA),
      ).importFiles([bytes('lesson.en.srt', _srt('Late subtitle'))]);

      expect(result.subtitlesImported, 1);
      expect(
        (await repositoryA.listSubtitleTracks(lesson.material.id))
            .single
            .cues
            .single
            .text,
        'Late subtitle\n',
      );
    },
  );

  test('deduplicates the same content for one account', () async {
    final importer = service(accountA, repositoryA);
    final first = await importer.importAudio(bytes('first.mp3', [10, 20, 30]));
    final second = await importer.importAudio(
      bytes('renamed.MP3', [10, 20, 30]),
    );

    expect(second.wasDuplicate, isTrue);
    expect(second.material.id, first.material.id);
    expect(second.material.title, first.material.title);
    expect(await repositoryA.listMaterials(), hasLength(1));
    expect(storage.mediaDirectory(accountA).listSync(), hasLength(1));
  });

  test('same bytes from another source create a separate material', () async {
    final importer = service(accountA, repositoryA);
    final first = await importer.importAudio(
      bytes('first.mp3', [1, 3, 5], sourceKey: 'source-one'),
    );
    final second = await importer.importAudio(
      bytes('second.mp3', [1, 3, 5], sourceKey: 'source-two'),
    );

    expect(second.wasDuplicate, isFalse);
    expect(second.material.id, isNot(first.material.id));
    expect(second.material.audioAssetId, first.material.audioAssetId);
    expect(await repositoryA.listMaterials(), hasLength(2));
    expect(storage.mediaDirectory(accountA).listSync(), hasLength(1));
  });

  test('isolates databases and media between accounts', () async {
    final first = await service(
      accountA,
      repositoryA,
    ).importAudio(bytes('lesson.mp3', [40, 50, 60]));
    final second = await service(
      accountB,
      repositoryB,
    ).importAudio(bytes('lesson.mp3', [40, 50, 60]));

    expect(second.wasDuplicate, isFalse);
    expect(second.material.id, isNot(first.material.id));
    expect(await repositoryA.listMaterials(), hasLength(1));
    expect(await repositoryB.listMaterials(), hasLength(1));
    expect(
      storage.mediaDirectory(accountA).path,
      isNot(storage.mediaDirectory(accountB).path),
    );
  });

  test(
    'rejects unsupported or empty files without creating a material',
    () async {
      final importer = service(accountA, repositoryA);
      await expectLater(
        importer.importAudio(bytes('lesson.wav', [1, 2])),
        throwsFormatException,
      );
      await expectLater(
        importer.importAudio(bytes('empty.m4a', [])),
        throwsA(isA<AudioImportException>()),
      );
      expect(await repositoryA.listMaterials(), isEmpty);
    },
  );

  test('removes partial file when source stream fails', () async {
    final source = AudioImportSource(
      sourceKey: 'broken-source',
      name: 'broken.mp3',
      openRead: () async* {
        yield [1, 2];
        throw const FormatException('read failed');
      },
    );

    await expectLater(
      service(accountA, repositoryA).importAudio(source),
      throwsFormatException,
    );
    expect(await repositoryA.listMaterials(), isEmpty);
    expect(storage.mediaDirectory(accountA).listSync(), isEmpty);
  });

  test('scope rejects empty owner identifiers and hashes path components', () {
    expect(() => AccountScope('  '), throwsArgumentError);
    expect(AccountScope('../user').storageKey, isNot('../user'));
  });
}

List<int> _srt(String text) =>
    utf8.encode('1\n00:00:01,000 --> 00:00:02,000\n$text\n');

List<int> _bilingualSrt(String english, String chinese) =>
    utf8.encode('1\n00:00:01,000 --> 00:00:02,000\n$english\n$chinese\n');
