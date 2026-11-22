import 'package:drift/drift.dart';

import '../../../core/db/account_scope.dart';
import '../../../core/db/local_database.dart';
import '../../../core/sync/sqlite_sync_outbox.dart';
import '../material_repository.dart';
import 'sqlite_folder_source_store.dart';
import 'sqlite_subtitle_track_store.dart';
import '../../subtitles/domain/subtitle_models.dart';

final class SqliteMaterialRepository
    implements
        MaterialRepository,
        FolderReconciliationRepository,
        CloudMaterialCacheRepository,
        CloudSubtitleCacheRepository,
        SubtitleTrackBatchWriter {
  const SqliteMaterialRepository({
    required AccountScope scope,
    required LocalDatabase database,
  }) : _scope = scope,
       _database = database;

  final AccountScope _scope;
  final LocalDatabase _database;

  Future<void> close() => _database.close();

  SqliteFolderSourceStore get _folders =>
      SqliteFolderSourceStore(_scope, _database);
  SqliteSubtitleTrackStore get _subtitles =>
      SqliteSubtitleTrackStore(_scope, _database);

  @override
  Future<List<FolderSourceRecord>> listFolderSources(String bindingId) =>
      _folders.listFolderSources(bindingId);

  @override
  Future<void> finishFolderScan({
    required String bindingId,
    required Set<String> inventoryPaths,
  }) => _folders.finishFolderScan(
    bindingId: bindingId,
    inventoryPaths: inventoryPaths,
  );

  @override
  Future<void> saveFolderSource({
    required String bindingId,
    required String relativePath,
    required String materialId,
    required String contentSha256,
  }) => _folders.saveFolderSource(
    bindingId: bindingId,
    relativePath: relativePath,
    materialId: materialId,
    contentSha256: contentSha256,
  );

  @override
  Future<void> addToFolderPlaylist({
    required String bindingId,
    required String materialId,
    required String title,
  }) => _folders.addToFolderPlaylist(
    bindingId: bindingId,
    materialId: materialId,
    title: title,
  );

  Future<Set<String>> uploadedMaterialIds() async {
    final rows = await _database
        .customSelect(
          """
      SELECT entity_id FROM sync_outbox
      WHERE owner_id = ? AND entity_type = 'material' AND state = 'completed'
      """,
          variables: [Variable.withString(_scope.ownerId)],
        )
        .get();
    return rows.map((row) => row.read<String>('entity_id')).toSet();
  }

  @override
  Future<List<LearningMaterial>> listMaterials() async {
    final rows = await _database
        .customSelect(
          '''
      SELECT m.id, m.owner_id, COALESCE(n.value, m.title) AS title, m.audio_asset_id,
             COALESCE(ms.state, m.status) AS status,
             m.created_at_ms, a.byte_length
      FROM materials AS m
      JOIN media_assets AS a
        ON a.owner_id = m.owner_id AND a.id = m.audio_asset_id
      LEFT JOIN material_sync_state AS ms
        ON ms.owner_id = m.owner_id AND ms.material_id = m.id
      LEFT JOIN library_changes n
        ON n.owner_id = m.owner_id AND n.entity_id = m.id AND n.field = 'materialTitle'
      LEFT JOIN library_changes d
        ON d.owner_id = m.owner_id AND d.entity_id = m.id AND d.field = 'materialDeleted'
      WHERE m.owner_id = ? AND d.entity_id IS NULL
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
  }) => _subtitles.saveSubtitleTrack(
    track,
    manual: manual,
    queueForPublication: true,
  );

  @override
  Future<List<SubtitleTrack>> saveSubtitleTracks(
    List<SubtitleTrack> tracks, {
    required bool manual,
  }) => _database.transaction(
    () async => [
      for (final track in tracks)
        await saveSubtitleTrack(track, manual: manual),
    ],
  );

  @override
  Future<SubtitleTrack> saveDownloadedSubtitleTrack(SubtitleTrack track) =>
      _subtitles.saveSubtitleTrack(
        track,
        manual: false,
        queueForPublication: false,
      );

  @override
  Future<List<SubtitleTrack>> listSubtitleTracks(String materialId) =>
      _subtitles.listSubtitleTracks(materialId);

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
}
