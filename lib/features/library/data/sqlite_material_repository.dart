import 'package:drift/drift.dart';

import '../../../core/db/account_scope.dart';
import '../../../core/db/local_database.dart';
import '../material_repository.dart';

final class SqliteMaterialRepository implements MaterialRepository {
  const SqliteMaterialRepository({
    required AccountScope scope,
    required LocalDatabase database,
  }) : _scope = scope,
       _database = database;

  final AccountScope _scope;
  final LocalDatabase _database;

  Future<void> close() => _database.close();

  @override
  Future<List<LearningMaterial>> listMaterials() async {
    final rows = await _database
        .customSelect(
          '''
      SELECT m.id, m.owner_id, m.title, m.audio_asset_id, m.status,
             m.created_at_ms, a.byte_length
      FROM materials AS m
      JOIN media_assets AS a
        ON a.owner_id = m.owner_id AND a.id = m.audio_asset_id
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

    final assets = await _database
        .customSelect(
          'SELECT id FROM media_assets WHERE owner_id = ? AND sha256 = ?',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(asset.sha256),
          ],
        )
        .get();
    final assetId = assets.isEmpty
        ? asset.id
        : assets.single.read<String>('id');
    if (assets.isEmpty) {
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
          storedCreatedAt.millisecondsSinceEpoch,
        ],
      );
    }
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
