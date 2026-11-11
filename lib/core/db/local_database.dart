import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

class LocalDatabase extends GeneratedDatabase {
  LocalDatabase(super.executor);

  @override
  int get schemaVersion => 2;

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
      await _createSubtitleSchema();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) await _createSubtitleSchema();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> _createSubtitleSchema() async {
    await customStatement('''
      CREATE TABLE subtitle_tracks (
        owner_id TEXT NOT NULL,
        id TEXT NOT NULL,
        material_id TEXT NOT NULL,
        language_tag TEXT NOT NULL,
        source_name TEXT NOT NULL,
        original_srt BLOB NOT NULL,
        revision INTEGER NOT NULL CHECK (revision > 0),
        offset_ms INTEGER NOT NULL,
        selection_mode TEXT NOT NULL CHECK (selection_mode IN ('automatic', 'manual')),
        is_selected INTEGER NOT NULL CHECK (is_selected IN (0, 1)),
        PRIMARY KEY (owner_id, id),
        FOREIGN KEY (owner_id, material_id)
          REFERENCES materials (owner_id, id)
      )
    ''');
    await customStatement('''
      CREATE UNIQUE INDEX subtitle_selected_language
      ON subtitle_tracks (
        owner_id,
        material_id,
        CASE
          WHEN lower(language_tag) LIKE 'en%' THEN 'en'
          WHEN lower(language_tag) LIKE 'zh%' THEN 'zh'
          ELSE lower(language_tag)
        END
      )
      WHERE is_selected = 1
    ''');
    await customStatement('''
      CREATE TABLE subtitle_cues (
        owner_id TEXT NOT NULL,
        track_id TEXT NOT NULL,
        cue_id TEXT NOT NULL,
        ordinal INTEGER NOT NULL CHECK (ordinal >= 0),
        sequence INTEGER NOT NULL,
        start_ms INTEGER NOT NULL CHECK (start_ms >= 0),
        end_ms INTEGER NOT NULL CHECK (end_ms > start_ms),
        text TEXT NOT NULL,
        PRIMARY KEY (owner_id, track_id, cue_id),
        UNIQUE (owner_id, track_id, ordinal),
        FOREIGN KEY (owner_id, track_id)
          REFERENCES subtitle_tracks (owner_id, id) ON DELETE CASCADE
      )
    ''');
    await customStatement(
      'CREATE INDEX subtitle_cues_timeline '
      'ON subtitle_cues (owner_id, track_id, start_ms, end_ms)',
    );
  }

  static LocalDatabase open(File file) =>
      LocalDatabase(NativeDatabase.createInBackground(file));
}
