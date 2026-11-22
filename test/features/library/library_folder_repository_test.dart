import 'dart:io';

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
}
