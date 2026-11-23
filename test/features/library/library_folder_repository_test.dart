import 'dart:io';

import 'package:drift/native.dart';
import 'package:english_learning_player/core/db/local_database.dart';
import 'package:english_learning_player/core/sync/sqlite_sync_outbox.dart';
import 'package:english_learning_player/features/library/data/sqlite_library_changes.dart';
import 'package:english_learning_player/features/library/domain/library_change.dart';
import 'package:english_learning_player/core/db/account_database_service.dart';
import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/features/library/data/sqlite_library_folder_repository.dart';
import 'package:english_learning_player/features/library/data/sqlite_material_repository.dart';
import 'package:english_learning_player/features/library/material_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'manual folders persist, deduplicate entries and stay account scoped',
    () async {
      final root = await Directory.systemTemp.createTemp('elp-manual-folders-');
      addTearDown(() => root.delete(recursive: true));
      final storage = AccountDatabaseService(supportDirectory: root);
      final owner = AccountScope('folder-owner');
      final database = await storage.open(owner);
      final materialRepository = SqliteMaterialRepository(
        scope: owner,
        database: database,
      );
      final folders = SqliteLibraryFolderRepository(owner, database);
      late String folderId;
      try {
        await materialRepository.insertAudio(
          asset: const StoredAudioAsset(
            id: 'asset',
            sha256: 'hash',
            byteLength: 10,
            mediaType: 'audio/mpeg',
            relativePath: 'media/lesson.mp3',
          ),
          sourceKey: 'lesson-source',
          title: 'Lesson',
          materialId: 'lesson',
          createdAt: DateTime.utc(2026),
        );
        await materialRepository.addToFolderPlaylist(
          bindingId: 'icloud',
          materialId: 'lesson',
          title: 'iCloud',
        );
        await expectLater(
          () => folders.createFolder('  '),
          throwsArgumentError,
        );
        await folders.createFolder(' 精聽 ');
        final folder = (await folders.listFolders()).single;
        folderId = folder.id;
        expect(folder.title, '精聽');
        expect(folder.materialCount, 0);
        await folders.addMaterial(folderId, 'lesson');
        await folders.addMaterial(folderId, 'lesson');
        expect((await folders.listFolders()).single.materialCount, 1);
        expect(await folders.materialIds(folderId), {'lesson'});
        final other = SqliteLibraryFolderRepository(
          AccountScope('another-owner'),
          database,
        );
        await other.addMaterial(folderId, 'lesson');
        expect(await other.listFolders(), isEmpty);
        expect(await other.materialIds(folderId), isEmpty);
        expect(await folders.materialIds('folder-icloud'), isEmpty);
      } finally {
        await database.close();
      }

      final reopened = await storage.open(owner);
      addTearDown(reopened.close);
      final restored = SqliteLibraryFolderRepository(owner, reopened);
      expect((await restored.listFolders()).single.id, folderId);
      expect(await restored.materialIds(folderId), {'lesson'});
    },
  );
  test(
    'v8 upgrade queues manual folders and memberships without source bindings',
    () async {
      final root = await Directory.systemTemp.createTemp('elp-folders-v8-');
      addTearDown(() => root.delete(recursive: true));
      final scope = AccountScope('owner');
      final storage = AccountDatabaseService(supportDirectory: root);
      final old = await storage.open(scope);
      await _insert(SqliteMaterialRepository(scope: scope, database: old));
      await old.customStatement(
        "INSERT INTO playlists VALUES ('owner', 'manual', '原有分類', NULL, 0)",
      );
      await old.customStatement(
        "INSERT INTO playlists VALUES ('owner', 'icloud', '唯讀來源', 'local-binding', 0)",
      );
      await old.customStatement(
        "INSERT INTO playlist_entries VALUES ('owner', 'manual', 'lesson', 0)",
      );
      await old.customStatement(
        "INSERT INTO playlist_entries VALUES ('owner', 'icloud', 'lesson', 0)",
      );
      await old.customStatement('DROP TABLE library_changes');
      await old.customStatement('PRAGMA user_version = 8');
      await old.close();

      final db = await storage.open(scope);
      addTearDown(db.close);
      final folders = SqliteLibraryFolderRepository(scope, db);
      expect((await folders.listFolders()).single.title, '原有分類');
      expect(await folders.materialIds('manual'), {'lesson'});
      expect(await folders.materialIds('icloud'), isEmpty);
      final pending = await SqliteLibraryChanges(
        db,
        scope.ownerId,
      ).read(pendingOnly: true);
      expect(
        pending.map((change) => change.field),
        unorderedEquals([
          LibraryField.folderName,
          LibraryField.materialFolders,
        ]),
      );
    },
  );

  test('rename, move and delete keep tombstones, membership and audio references consistent', () async {
    final db = LocalDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final scope = AccountScope('owner');
    final folders = SqliteLibraryFolderRepository(scope, db);
    final materials = SqliteMaterialRepository(scope: scope, database: db);
    final changes = SqliteLibraryChanges(db, scope.ownerId);
    await _insert(materials);
    await folders.createFolder('Parent');
    await folders.createFolder('Child');
    final [child, parent] = await folders.listFolders();
    await folders.moveFolder(child.id, parent.id);
    await expectLater(
      folders.moveFolder(parent.id, child.id),
      throwsArgumentError,
    );
    await folders.moveMaterial('lesson', child.id);
    expect(await folders.materialIds(child.id), {'lesson'});
    expect(await folders.assignedMaterialIds(), {'lesson'});

    await folders.renameMaterial('lesson', '第一版');
    final sent = (await changes.read()).singleWhere(
      (change) => change.field == LibraryField.materialTitle,
    );
    await folders.renameMaterial('lesson', '第二版');
    await changes.acknowledge(sent);
    final queued = (await changes.read(pendingOnly: true))
        .singleWhere((change) => change.field == LibraryField.materialTitle);
    expect(queued.value, '第二版');
    expect((await materials.listMaterials()).single.title, '第二版');

    await folders.deleteFolder(child.id);
    expect(await folders.materialIds(parent.id), {'lesson'});
    await folders.deleteFolder(parent.id);
    expect(await folders.assignedMaterialIds(), isEmpty);
    expect(await materials.listMaterials(), hasLength(1));

    await folders.deleteMaterial('lesson');
    await changes.merge([sent]);
    expect(await materials.listMaterials(), isEmpty);
    expect(await changes.materialDeleted('lesson'), isTrue);
    expect(
      await SqliteSyncOutbox(scope: scope, db: db).hasDueMedia(DateTime.now()),
      isFalse,
    );
    expect(
      await db.customSelect('SELECT id FROM media_assets').get(),
      hasLength(1),
    );
  });
}

Future<void> _insert(SqliteMaterialRepository repository) =>
    repository.insertAudio(
      asset: const StoredAudioAsset(
        id: 'asset',
        sha256: 'hash',
        byteLength: 10,
        mediaType: 'audio/mpeg',
        relativePath: 'media/lesson.mp3',
      ),
      sourceKey: 'lesson-source',
      title: 'Lesson',
      materialId: 'lesson',
      createdAt: DateTime.utc(2026),
    );
