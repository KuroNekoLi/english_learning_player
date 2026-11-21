import 'dart:io';

import 'package:drift/native.dart';
import 'package:english_learning_player/core/db/local_database.dart';
import 'package:english_learning_player/features/sync/sync_preference.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'v7 upgrade is opt-in and persists decisions per owner and project',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'sync-preferences-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/test.sqlite');
      final old = LocalDatabase(NativeDatabase(file));
      await old.customStatement('DROP TABLE sync_preferences');
      await old.customStatement('PRAGMA user_version = 7');
      await old.close();

      const alice = (uid: 'alice', project: 'sync-test');
      const bob = (uid: 'bob', project: 'sync-test');
      const otherProject = (uid: 'alice', project: 'other-project');

      final db = LocalDatabase(NativeDatabase(file));
      final store = SyncPreferenceStore(db);
      expect(await store.read(alice), SyncPreference.undecided);
      await store.write(alice, SyncPreference.enabled);
      await store.write(bob, SyncPreference.disabled);
      await db.close();

      final reopened = LocalDatabase(NativeDatabase(file));
      addTearDown(reopened.close);
      final saved = SyncPreferenceStore(reopened);
      expect(await saved.read(alice), SyncPreference.enabled);
      expect(await saved.read(bob), SyncPreference.disabled);
      expect(await saved.read(otherProject), SyncPreference.undecided);
      await saved.write(alice, SyncPreference.disabled);
      expect(await saved.read(alice), SyncPreference.disabled);
    },
  );
}
