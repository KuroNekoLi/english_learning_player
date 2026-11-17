import 'package:drift/drift.dart';

import '../../../core/db/account_scope.dart';
import '../../../core/db/local_database.dart';
import '../../../core/sync/sqlite_sync_outbox.dart';
import '../material_repository.dart';
import '../../subtitles/domain/subtitle_models.dart';

final class SqliteMaterialRepository
    implements
        MaterialRepository,
        FolderReconciliationRepository,
        CloudMaterialCacheRepository {
  const SqliteMaterialRepository({
    required AccountScope scope,
    required LocalDatabase database,
  }) : _scope = scope,
       _database = database;

  final AccountScope _scope;
  final LocalDatabase _database;

  Future<void> close() => _database.close();

  @override
  Future<List<FolderSourceRecord>> listFolderSources(String bindingId) async {
    final rows = await _database
        .customSelect(
          '''SELECT relative_path, material_id, content_sha256, present
         FROM folder_source_entries
         WHERE owner_id = ? AND binding_id = ?
         ORDER BY relative_path''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(bindingId),
          ],
        )
        .get();
    return List.unmodifiable(
      rows.map(
        (row) => FolderSourceRecord(
          relativePath: row.read<String>('relative_path'),
          materialId: row.read<String>('material_id'),
          contentSha256: row.read<String>('content_sha256'),
          present: row.read<int>('present') == 1,
        ),
      ),
    );
  }

  @override
  Future<void> finishFolderScan({
    required String bindingId,
    required Set<String> inventoryPaths,
  }) async {
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final known = await _database
        .customSelect(
          '''SELECT relative_path FROM folder_source_entries
         WHERE owner_id = ? AND binding_id = ?''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(bindingId),
          ],
        )
        .get();
    final missing = known
        .map((row) => row.read<String>('relative_path'))
        .where((path) => !inventoryPaths.contains(path))
        .toList();
    if (missing.isEmpty) return;
    await _database.transaction(() async {
      await _database.batch((batch) {
        for (final path in missing) {
          batch.customStatement(
            '''UPDATE folder_source_entries SET present = 0, updated_at_ms = ?
               WHERE owner_id = ? AND binding_id = ? AND relative_path = ?''',
            [nowMs, _scope.ownerId, bindingId, path],
          );
        }
      });
    });
  }

  @override
  Future<void> saveFolderSource({
    required String bindingId,
    required String relativePath,
    required String materialId,
    required String contentSha256,
  }) async {
    await _database.customStatement(
      '''INSERT INTO folder_source_entries
           (owner_id, binding_id, relative_path, material_id, content_sha256,
            present, updated_at_ms)
         VALUES (?, ?, ?, ?, ?, 1, ?)
         ON CONFLICT (owner_id, binding_id, relative_path) DO UPDATE SET
           material_id = excluded.material_id,
           content_sha256 = excluded.content_sha256,
           present = 1,
           updated_at_ms = excluded.updated_at_ms''',
      [
        _scope.ownerId,
        bindingId,
        relativePath,
        materialId,
        contentSha256,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  @override
  Future<void> addToFolderPlaylist({
    required String bindingId,
    required String materialId,
    required String title,
  }) async {
    final playlistId = 'folder-$bindingId';
    await _database.transaction(() async {
      await _database.customStatement(
        '''INSERT OR IGNORE INTO playlists
             (owner_id, id, title, source_binding_id, created_at_ms)
           VALUES (?, ?, ?, ?, ?)''',
        [
          _scope.ownerId,
          playlistId,
          title,
          bindingId,
          DateTime.now().toUtc().millisecondsSinceEpoch,
        ],
      );
      final exists = await _database
          .customSelect(
            '''SELECT 1 FROM playlist_entries
           WHERE owner_id = ? AND playlist_id = ? AND material_id = ?''',
            variables: [
              Variable.withString(_scope.ownerId),
              Variable.withString(playlistId),
              Variable.withString(materialId),
            ],
          )
          .get();
      if (exists.isNotEmpty) return;
      final next = await _database
          .customSelect(
            '''SELECT COALESCE(MAX(position), -1) + 1 AS next_position
           FROM playlist_entries WHERE owner_id = ? AND playlist_id = ?''',
            variables: [
              Variable.withString(_scope.ownerId),
              Variable.withString(playlistId),
            ],
          )
          .getSingle();
      await _database.customStatement(
        '''INSERT INTO playlist_entries
             (owner_id, playlist_id, material_id, position)
           VALUES (?, ?, ?, ?)''',
        [
          _scope.ownerId,
          playlistId,
          materialId,
          next.read<int>('next_position'),
        ],
      );
    });
  }

  @override
  Future<List<LearningMaterial>> listMaterials() async {
    final rows = await _database
        .customSelect(
          '''
      SELECT m.id, m.owner_id, m.title, m.audio_asset_id,
             COALESCE(ms.state, m.status) AS status,
             m.created_at_ms, a.byte_length
      FROM materials AS m
      JOIN media_assets AS a
        ON a.owner_id = m.owner_id AND a.id = m.audio_asset_id
      LEFT JOIN material_sync_state AS ms
        ON ms.owner_id = m.owner_id AND ms.material_id = m.id
      WHERE m.owner_id = ?
      ORDER BY m.created_at_ms DESC, m.id ASC
      ''',
          variables: [Variable.withString(_scope.ownerId)],
        )
        .get();

    return List.unmodifiable(
      rows.map(
        (row) => LearningMaterial(
          id: row.read<String>('id'),
          ownerId: row.read<String>('owner_id'),
          title: row.read<String>('title'),
          audioAssetId: row.read<String>('audio_asset_id'),
          status: MaterialStatus.values.byName(row.read<String>('status')),
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('created_at_ms'),
            isUtc: true,
          ),
          durationMs: null,
        ),
      ),
    );
  }

  @override
  Future<StoredAudioAsset?> audioAssetForMaterial(String materialId) async {
    final rows = await _database
        .customSelect(
          '''
          SELECT a.id, a.sha256, a.byte_length, a.media_type, a.relative_path
          FROM materials AS m
          JOIN media_assets AS a
            ON a.owner_id = m.owner_id AND a.id = m.audio_asset_id
          WHERE m.owner_id = ? AND m.id = ?
          LIMIT 1
          ''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(materialId),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    final row = rows.single;
    return StoredAudioAsset(
      id: row.read<String>('id'),
      sha256: row.read<String>('sha256'),
      byteLength: row.read<int>('byte_length'),
      mediaType: row.read<String>('media_type'),
      relativePath: row.read<String>('relative_path'),
    );
  }

  @override
  Future<InsertMaterialResult> insertAudio({
    required StoredAudioAsset asset,
    required String sourceKey,
    required String title,
    required String materialId,
    required DateTime createdAt,
  }) async => _database.transaction(() async {
    final storedCreatedAt = DateTime.fromMillisecondsSinceEpoch(
      createdAt.millisecondsSinceEpoch,
      isUtc: true,
    );
    final existing = await _database
        .customSelect(
          '''
      SELECT m.id, m.owner_id, m.title, m.audio_asset_id, m.status,
             m.created_at_ms
      FROM material_sources AS s
      JOIN materials AS m
        ON m.owner_id = s.owner_id AND m.id = s.material_id
      JOIN media_assets AS a
        ON a.owner_id = s.owner_id AND a.id = s.asset_id
      WHERE s.owner_id = ? AND s.source_key = ? AND a.sha256 = ?
      ''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(sourceKey),
            Variable.withString(asset.sha256),
          ],
        )
        .get();
    if (existing.isNotEmpty) {
      return InsertMaterialResult(
        material: _materialFromRow(existing.single),
        wasDuplicate: true,
      );
    }

    final assetId = await _ensureAsset(asset, storedCreatedAt);
    await _database.customStatement(
      '''
      INSERT INTO materials
        (owner_id, id, audio_asset_id, title, status, created_at_ms)
      VALUES (?, ?, ?, ?, 'localReady', ?)
      ''',
      [
        _scope.ownerId,
        materialId,
        assetId,
        title,
        storedCreatedAt.millisecondsSinceEpoch,
      ],
    );
    await _database.customStatement(
      '''
      INSERT INTO material_sources (owner_id, source_key, asset_id, material_id)
      VALUES (?, ?, ?, ?)
      ''',
      [_scope.ownerId, sourceKey, assetId, materialId],
    );
    final payload = SqliteSyncOutbox.canonicalMaterialPayload(
      materialId: materialId,
      title: title,
      assetId: assetId,
      sha256: asset.sha256,
      byteLength: asset.byteLength,
      mediaType: asset.mediaType,
    );
    await SqliteSyncOutbox.enqueueMaterialInTransaction(
      db: _database,
      ownerId: _scope.ownerId,
      materialId: materialId,
      payloadJson: payload,
      nowMs: storedCreatedAt.millisecondsSinceEpoch,
    );
    return InsertMaterialResult(
      material: LearningMaterial(
        id: materialId,
        ownerId: _scope.ownerId,
        title: title,
        audioAssetId: assetId,
        status: MaterialStatus.localReady,
        createdAt: storedCreatedAt,
      ),
      wasDuplicate: false,
    );
  });

  Future<String> _ensureAsset(
    StoredAudioAsset asset,
    DateTime createdAt, {
    bool requireMatchingMetadata = false,
  }) async {
    final assets = await _database
        .customSelect(
          '''SELECT id, byte_length, media_type, relative_path FROM media_assets
             WHERE owner_id = ? AND sha256 = ?''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(asset.sha256),
          ],
        )
        .get();
    if (assets.isNotEmpty) {
      final existing = assets.single;
      if (requireMatchingMetadata &&
          (existing.read<int>('byte_length') != asset.byteLength ||
              existing.read<String>('media_type') != asset.mediaType ||
              existing.read<String>('relative_path') != asset.relativePath)) {
        throw StateError('Downloaded asset conflicts with local media.');
      }
      return existing.read<String>('id');
    }
    await _database.customStatement(
      '''
        INSERT INTO media_assets
          (owner_id, id, sha256, byte_length, media_type, relative_path, created_at_ms)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ''',
      [
        _scope.ownerId,
        asset.id,
        asset.sha256,
        asset.byteLength,
        asset.mediaType,
        asset.relativePath,
        createdAt.millisecondsSinceEpoch,
      ],
    );
    return asset.id;
  }

  @override
  Future<LearningMaterial> cacheCloudAudio({
    required String materialId,
    required StoredAudioAsset asset,
    required String title,
    required DateTime cachedAt,
  }) => _database.transaction(() async {
    final existing = await _database
        .customSelect(
          '''
      SELECT m.id, m.owner_id, m.title, m.audio_asset_id, m.created_at_ms,
             COALESCE(ms.state, m.status) AS status,
             a.sha256, a.byte_length, a.media_type
      FROM materials m JOIN media_assets a
        ON a.owner_id = m.owner_id AND a.id = m.audio_asset_id
      LEFT JOIN material_sync_state ms
        ON ms.owner_id = m.owner_id AND ms.material_id = m.id
      WHERE m.owner_id = ? AND m.id = ?
      ''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(materialId),
          ],
        )
        .getSingleOrNull();
    if (existing != null) {
      if (existing.read<String>('sha256') != asset.sha256 ||
          existing.read<int>('byte_length') != asset.byteLength ||
          existing.read<String>('media_type') != asset.mediaType) {
        throw StateError('Downloaded material conflicts with local media.');
      }
      return _materialFromRow(existing);
    }

    final assetId = await _ensureAsset(
      asset,
      cachedAt,
      requireMatchingMetadata: true,
    );
    await _database.customStatement(
      '''
      INSERT INTO materials (owner_id, id, audio_asset_id, title, status, created_at_ms)
      VALUES (?, ?, ?, ?, 'localReady', ?)
      ''',
      [
        _scope.ownerId,
        materialId,
        assetId,
        title,
        cachedAt.millisecondsSinceEpoch,
      ],
    );
    await _database.customStatement(
      '''
      INSERT INTO material_sync_state (owner_id, material_id, state, last_synced_at_ms)
      VALUES (?, ?, 'cloudReady', ?)
      ''',
      [_scope.ownerId, materialId, cachedAt.millisecondsSinceEpoch],
    );
    return LearningMaterial(
      id: materialId,
      ownerId: _scope.ownerId,
      title: title,
      audioAssetId: assetId,
      status: MaterialStatus.cloudReady,
      createdAt: cachedAt,
    );
  });

  @override
  Future<SubtitleTrack> saveSubtitleTrack(
    SubtitleTrack track, {
    required bool manual,
  }) async {
    if (track.ownerId != _scope.ownerId) {
      throw ArgumentError.value(track.ownerId, 'track.ownerId');
    }
    final languageKey = _languageKey(track.languageTag);
    return _database.transaction(() async {
      final existing = await _database
          .customSelect(
            'SELECT selection_mode FROM subtitle_tracks '
            'WHERE owner_id = ? AND id = ?',
            variables: [
              Variable.withString(_scope.ownerId),
              Variable.withString(track.id),
            ],
          )
          .get();
      if (existing.isNotEmpty &&
          existing.single.read<String>('selection_mode') == 'manual' &&
          !manual) {
        return (await listSubtitleTracks(
          track.materialId,
        )).firstWhere((item) => item.id == track.id);
      }

      var selected = manual;
      if (manual) {
        await _database.customStatement(
          '''
          UPDATE subtitle_tracks SET is_selected = 0
          WHERE owner_id = ? AND material_id = ?
            AND CASE
              WHEN lower(language_tag) LIKE 'en%' THEN 'en'
              WHEN lower(language_tag) LIKE 'zh%' THEN 'zh'
              ELSE lower(language_tag)
            END = ?
          ''',
          [_scope.ownerId, track.materialId, languageKey],
        );
      } else {
        final manualSelection = await _database
            .customSelect(
              '''
              SELECT 1 FROM subtitle_tracks
              WHERE owner_id = ? AND material_id = ?
                AND CASE
                  WHEN lower(language_tag) LIKE 'en%' THEN 'en'
                  WHEN lower(language_tag) LIKE 'zh%' THEN 'zh'
                  ELSE lower(language_tag)
                END = ?
                AND selection_mode = 'manual' AND is_selected = 1
              LIMIT 1
              ''',
              variables: [
                Variable.withString(_scope.ownerId),
                Variable.withString(track.materialId),
                Variable.withString(languageKey),
              ],
            )
            .get();
        selected = manualSelection.isEmpty;
        if (selected) {
          await _database.customStatement(
            '''
            UPDATE subtitle_tracks SET is_selected = 0
            WHERE owner_id = ? AND material_id = ?
              AND CASE
                WHEN lower(language_tag) LIKE 'en%' THEN 'en'
                WHEN lower(language_tag) LIKE 'zh%' THEN 'zh'
                ELSE lower(language_tag)
              END = ?
            ''',
            [_scope.ownerId, track.materialId, languageKey],
          );
        }
      }

      await _database.customStatement(
        '''
        INSERT INTO subtitle_tracks
          (owner_id, id, material_id, language_tag, source_name, original_srt,
           revision, offset_ms, selection_mode, is_selected)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (owner_id, id) DO UPDATE SET
          material_id = excluded.material_id,
          language_tag = excluded.language_tag,
          source_name = excluded.source_name,
          original_srt = excluded.original_srt,
          revision = excluded.revision,
          offset_ms = excluded.offset_ms,
          selection_mode = excluded.selection_mode,
          is_selected = excluded.is_selected
        ''',
        [
          _scope.ownerId,
          track.id,
          track.materialId,
          track.languageTag,
          track.sourceName,
          Uint8List.fromList(track.originalBytes),
          track.revision,
          track.offsetMs,
          manual ? 'manual' : 'automatic',
          selected ? 1 : 0,
        ],
      );
      await _database.customStatement(
        'DELETE FROM subtitle_cues WHERE owner_id = ? AND track_id = ?',
        [_scope.ownerId, track.id],
      );
      if (track.cues.isNotEmpty) {
        await _database.batch((batch) {
          for (var ordinal = 0; ordinal < track.cues.length; ordinal++) {
            final cue = track.cues[ordinal];
            batch.customStatement(
              '''
              INSERT INTO subtitle_cues
                (owner_id, track_id, cue_id, ordinal, sequence, start_ms,
                 end_ms, text)
              VALUES (?, ?, ?, ?, ?, ?, ?, ?)
              ''',
              [
                _scope.ownerId,
                track.id,
                cue.id,
                ordinal,
                cue.sequence,
                cue.startMs,
                cue.endMs,
                cue.text,
              ],
            );
          }
        });
      }
      return track.copyWith(
        selectionMode: manual
            ? SubtitleSelectionMode.manual
            : SubtitleSelectionMode.automatic,
        isSelected: selected,
      );
    });
  }

  @override
  Future<List<SubtitleTrack>> listSubtitleTracks(String materialId) async {
    final tracks = await _database
        .customSelect(
          '''
          SELECT id, owner_id, material_id, language_tag, source_name,
                 original_srt, revision, offset_ms, selection_mode, is_selected
          FROM subtitle_tracks
          WHERE owner_id = ? AND material_id = ?
          ORDER BY language_tag, is_selected DESC, revision DESC, id
          ''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(materialId),
          ],
        )
        .get();
    final result = <SubtitleTrack>[];
    for (final row in tracks) {
      final cueRows = await _database
          .customSelect(
            '''
            SELECT cue_id, sequence, start_ms, end_ms, text
            FROM subtitle_cues
            WHERE owner_id = ? AND track_id = ?
            ORDER BY ordinal
            ''',
            variables: [
              Variable.withString(_scope.ownerId),
              Variable.withString(row.read<String>('id')),
            ],
          )
          .get();
      result.add(
        SubtitleTrack(
          id: row.read<String>('id'),
          ownerId: row.read<String>('owner_id'),
          materialId: row.read<String>('material_id'),
          languageTag: row.read<String>('language_tag'),
          sourceName: row.read<String>('source_name'),
          originalBytes: row.read<Uint8List>('original_srt'),
          revision: row.read<int>('revision'),
          offsetMs: row.read<int>('offset_ms'),
          selectionMode: SubtitleSelectionMode.values.byName(
            row.read<String>('selection_mode'),
          ),
          isSelected: row.read<int>('is_selected') == 1,
          cues: [
            for (final cueRow in cueRows)
              SubtitleCue(
                id: cueRow.read<String>('cue_id'),
                sequence: cueRow.read<int>('sequence'),
                startMs: cueRow.read<int>('start_ms'),
                endMs: cueRow.read<int>('end_ms'),
                text: cueRow.read<String>('text'),
              ),
          ],
        ),
      );
    }
    return List.unmodifiable(result);
  }

  LearningMaterial _materialFromRow(QueryRow row) => LearningMaterial(
    id: row.read<String>('id'),
    ownerId: row.read<String>('owner_id'),
    title: row.read<String>('title'),
    audioAssetId: row.read<String>('audio_asset_id'),
    status: MaterialStatus.values.byName(row.read<String>('status')),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('created_at_ms'),
      isUtc: true,
    ),
  );

  String _languageKey(String languageTag) {
    final lower = languageTag.toLowerCase();
    if (lower == 'en' || lower.startsWith('en-')) return 'en';
    if (lower == 'zh' || lower.startsWith('zh-')) return 'zh';
    return lower;
  }
}
