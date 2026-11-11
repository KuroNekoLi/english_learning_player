import 'package:drift/drift.dart';

import '../../../core/db/account_scope.dart';
import '../../../core/db/local_database.dart';
import '../material_repository.dart';
import '../../subtitles/domain/subtitle_models.dart';

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
