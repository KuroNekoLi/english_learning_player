import 'package:drift/drift.dart';

import '../../../core/db/account_scope.dart';
import '../../../core/db/local_database.dart';
import '../../subtitles/domain/subtitle_models.dart';

final class SqliteSubtitleTrackStore {
  const SqliteSubtitleTrackStore(this._scope, this._database);

  final AccountScope _scope;
  final LocalDatabase _database;

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

  String _languageKey(String languageTag) {
    final lower = languageTag.toLowerCase();
    if (lower == 'en' || lower.startsWith('en-')) return 'en';
    if (lower == 'zh' || lower.startsWith('zh-')) return 'zh';
    return lower;
  }
}
