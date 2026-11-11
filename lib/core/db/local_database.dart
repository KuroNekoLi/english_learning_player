import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

class LocalDatabase extends GeneratedDatabase {
  LocalDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, Object?>> get allSchemaEntities => const [];

  @override
  List<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('''
        CREATE TABLE media_assets (
          owner_id TEXT NOT NULL,
          id TEXT NOT NULL,
          sha256 TEXT NOT NULL,
          byte_length INTEGER NOT NULL CHECK (byte_length > 0),
          media_type TEXT NOT NULL CHECK (media_type IN ('audio/mpeg', 'audio/mp4')),
          relative_path TEXT NOT NULL,
          created_at_ms INTEGER NOT NULL,
          PRIMARY KEY (owner_id, id),
          UNIQUE (owner_id, sha256)
        )
      ''');
      await customStatement('''
        CREATE TABLE materials (
          owner_id TEXT NOT NULL,
          id TEXT NOT NULL,
          audio_asset_id TEXT NOT NULL,
          title TEXT NOT NULL,
          status TEXT NOT NULL CHECK (status = 'localReady'),
          created_at_ms INTEGER NOT NULL,
          PRIMARY KEY (owner_id, id),
          FOREIGN KEY (owner_id, audio_asset_id)
            REFERENCES media_assets (owner_id, id)
        )
      ''');
      await customStatement(
        'CREATE INDEX materials_created_at '
        'ON materials (owner_id, created_at_ms DESC)',
      );
      await customStatement('''
        CREATE TABLE material_sources (
          owner_id TEXT NOT NULL,
          source_key TEXT NOT NULL,
          asset_id TEXT NOT NULL,
          material_id TEXT NOT NULL,
          PRIMARY KEY (owner_id, source_key, asset_id),
          FOREIGN KEY (owner_id, asset_id)
            REFERENCES media_assets (owner_id, id),
          FOREIGN KEY (owner_id, material_id)
            REFERENCES materials (owner_id, id)
        )
      ''');
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static LocalDatabase open(File file) =>
      LocalDatabase(NativeDatabase.createInBackground(file));
}
