import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:english_learning_player/core/db/account_database_service.dart';
import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/core/files/app_media_store.dart';
import 'package:english_learning_player/features/library/data/sqlite_material_repository.dart';
import 'package:english_learning_player/features/library/domain/audio_import_source.dart';
import 'package:english_learning_player/features/library/material_repository.dart';
import 'package:english_learning_player/features/library/services/audio_import_service.dart';
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
