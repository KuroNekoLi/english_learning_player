import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:uuid/uuid.dart';

class LocalDatabase extends GeneratedDatabase {
  LocalDatabase(super.executor);

  @override
  int get schemaVersion => 4;

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
      await _createBookmarkSchema();
      await _createSyncSchema();
    },
    onUpgrade: (migrator, from, to) async {
      if (from < 2) await _createSubtitleSchema();
      if (from < 3) await _createBookmarkSchema();
      if (from < 4) {
        await _createSyncSchema();
        await _backfillMaterialSyncOperations();
      }
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

  Future<void> _createBookmarkSchema() async {
    await customStatement('''
      CREATE TABLE bookmarks (
        owner_id TEXT NOT NULL,
        id TEXT NOT NULL,
        material_id TEXT NOT NULL,
        track_id TEXT NOT NULL,
        track_revision INTEGER NOT NULL CHECK (track_revision > 0),
        language_tag TEXT NOT NULL,
        cue_id TEXT NOT NULL,
        cue_text TEXT NOT NULL,
        start_ms INTEGER NOT NULL CHECK (start_ms >= 0),
        end_ms INTEGER NOT NULL CHECK (end_ms > start_ms),
        created_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER,
        PRIMARY KEY (owner_id, id),
        FOREIGN KEY (owner_id, material_id)
          REFERENCES materials (owner_id, id)
      )
    ''');
    await customStatement('''
      CREATE UNIQUE INDEX bookmarks_active_anchor
      ON bookmarks (owner_id, material_id, track_id, track_revision, cue_id)
      WHERE deleted_at_ms IS NULL
    ''');
    await customStatement(
      'CREATE INDEX bookmarks_material_created '
      'ON bookmarks (owner_id, material_id, created_at_ms DESC)',
    );
  }

  Future<void> _createSyncSchema() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_outbox (
        owner_id TEXT NOT NULL,
        op_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload_version INTEGER NOT NULL CHECK (payload_version > 0),
        payload_json TEXT NOT NULL,
        payload_hash TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0 CHECK (attempts >= 0),
        next_retry_at_ms INTEGER NOT NULL,
        lease_until_ms INTEGER,
        state TEXT NOT NULL CHECK (state IN ('queued', 'leased', 'waitingForAuth', 'needsAttention', 'completed')),
        last_error TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        PRIMARY KEY (owner_id, op_id)
      )
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS sync_outbox_due
      ON sync_outbox (owner_id, state, next_retry_at_ms, created_at_ms)
    ''');
    await customStatement('''
      CREATE INDEX IF NOT EXISTS sync_outbox_entity
      ON sync_outbox (owner_id, entity_type, entity_id, state)
    ''');
    await customStatement('''
      CREATE TABLE IF NOT EXISTS material_sync_state (
        owner_id TEXT NOT NULL,
        material_id TEXT NOT NULL,
        state TEXT NOT NULL CHECK (state IN ('localReady', 'uploading', 'cloudReady', 'error')),
        last_error TEXT,
        last_synced_at_ms INTEGER,
        PRIMARY KEY (owner_id, material_id),
        FOREIGN KEY (owner_id, material_id)
          REFERENCES materials (owner_id, id) ON DELETE CASCADE
      )
    ''');
  }

  Future<void> _backfillMaterialSyncOperations() async {
    final rows = await customSelect('''
      SELECT m.owner_id, m.id AS material_id, m.title, a.id AS asset_id,
             a.sha256, a.byte_length, a.media_type, m.created_at_ms
      FROM materials m JOIN media_assets a
        ON a.owner_id = m.owner_id AND a.id = m.audio_asset_id
    ''').get();
    const uuid = Uuid();
    for (final row in rows) {
      final ownerId = row.read<String>('owner_id');
      final materialId = row.read<String>('material_id');
      final createdAtMs = row.read<int>('created_at_ms');
      final payload = jsonEncode({
        'schemaVersion': 1,
        'materialId': materialId,
        'title': row.read<String>('title'),
        'assetId': row.read<String>('asset_id'),
        'sha256': row.read<String>('sha256'),
        'byteLength': row.read<int>('byte_length'),
        'mediaType': row.read<String>('media_type'),
      });
      final existingOperations = await customSelect(
        '''SELECT 1 FROM sync_outbox
           WHERE owner_id = ? AND entity_type = 'material' AND entity_id = ? LIMIT 1''',
        variables: [
          Variable.withString(ownerId),
          Variable.withString(materialId),
        ],
      ).get();
      if (existingOperations.isNotEmpty) continue;
      await customStatement(
        '''
        INSERT OR IGNORE INTO material_sync_state
          (owner_id, material_id, state, last_error, last_synced_at_ms)
        VALUES (?, ?, 'localReady', NULL, NULL)
      ''',
        [ownerId, materialId],
      );
      await customStatement(
        '''
        INSERT INTO sync_outbox
          (owner_id, op_id, entity_type, entity_id, operation, payload_version,
           payload_json, payload_hash, attempts, next_retry_at_ms, state,
           created_at_ms, updated_at_ms)
        VALUES (?, ?, 'material', ?, 'uploadMaterial', 1, ?, ?, 0, ?, 'queued', ?, ?)
      ''',
        [
          ownerId,
          uuid.v4(),
          materialId,
          payload,
          sha256.convert(utf8.encode(payload)).toString(),
          createdAtMs,
          createdAtMs,
          createdAtMs,
        ],
      );
    }
  }

  static LocalDatabase open(File file) =>
      LocalDatabase(NativeDatabase.createInBackground(file));
}
