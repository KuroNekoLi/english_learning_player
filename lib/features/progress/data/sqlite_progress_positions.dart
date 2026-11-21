import 'package:drift/drift.dart';

import '../../../core/db/account_scope.dart';
import '../../../core/db/local_database.dart';
import '../../../core/sync/progress_policy.dart';
import '../domain/progress_models.dart';

/// Maps confirmed progress and conflict candidates. The repository owns
/// transactions that also touch streams or the outbox.
final class SqliteProgressPositions {
  const SqliteProgressPositions(this._scope, this._db);
  final AccountScope _scope;
  final LocalDatabase _db;

  Future<CanonicalProgress?> canonical(String materialId) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT position_ms, state, device_id, session_id, sequence, revision
      FROM playback_progress WHERE owner_id = ? AND material_id = ?
    ''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(materialId),
          ],
        )
        .get();
    if (rows.isEmpty) return null;
    final row = rows.single;
    return CanonicalProgress(
      checkpoint: _checkpointFromCanonical(row, materialId),
      revision: row.read<int>('revision'),
    );
  }

  Future<List<ProgressCandidate>> unresolvedCandidates(
    String materialId,
  ) async {
    final rows = await _db
        .customSelect(
          '''
      SELECT candidate_id, device_id, session_id, sequence, base_revision,
             position_ms, state, created_at_ms
      FROM progress_conflicts WHERE owner_id = ? AND material_id = ? AND resolved_at_ms IS NULL
      ORDER BY created_at_ms, candidate_id
    ''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(materialId),
          ],
        )
        .get();
    return rows
        .map((row) {
          final checkpoint = ProgressCheckpoint(
            stream: (
              ownerId: _scope.ownerId,
              materialId: materialId,
              deviceId: row.read<String>('device_id'),
              sessionId: row.read<String>('session_id'),
            ),
            positionMs: row.read<int>('position_ms'),
            state: CheckpointState.values.byName(row.read<String>('state')),
            sequence: row.read<int>('sequence'),
            baseRevision: row.read<int>('base_revision'),
          );
          return ProgressCandidate(
            id: row.read<String>('candidate_id'),
            checkpoint: checkpoint,
            createdAtMs: row.read<int>('created_at_ms'),
          );
        })
        .toList(growable: false);
  }

  Future<ProgressCheckpoint?> unresolvedCandidate(
    String candidateId,
    ProgressStream stream,
  ) async {
    final row = await _db
        .customSelect(
          '''
      SELECT * FROM progress_conflicts WHERE owner_id = ? AND candidate_id = ?
        AND material_id = ? AND resolved_at_ms IS NULL
      ''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(candidateId),
            Variable.withString(stream.materialId),
          ],
        )
        .getSingleOrNull();
    return row == null ? null : _checkpointFromConflict(row, stream);
  }

  Future<void> markResolved(String candidateId, int nowMs) async {
    await _db.customStatement(
      '''UPDATE progress_conflicts SET resolved_at_ms = ?
                WHERE owner_id = ? AND candidate_id = ? AND resolved_at_ms IS NULL''',
      [nowMs, _scope.ownerId, candidateId],
    );
  }

  Future<void> saveConflict(
    String candidateId,
    ProgressCheckpoint checkpoint,
    int nowMs,
  ) async {
    await _db.customStatement(
      '''
            INSERT INTO progress_conflicts
              (owner_id, candidate_id, material_id, device_id, session_id, sequence,
               base_revision, position_ms, state, created_at_ms)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(owner_id, candidate_id) DO UPDATE SET
              sequence = excluded.sequence, base_revision = excluded.base_revision,
              position_ms = excluded.position_ms, state = excluded.state,
              created_at_ms = excluded.created_at_ms, resolved_at_ms = NULL
            WHERE progress_conflicts.material_id = excluded.material_id
              AND progress_conflicts.device_id = excluded.device_id
              AND progress_conflicts.session_id = excluded.session_id
              AND excluded.sequence > progress_conflicts.sequence
          ''',
      [
        _scope.ownerId,
        candidateId,
        checkpoint.stream.materialId,
        checkpoint.stream.deviceId,
        checkpoint.stream.sessionId,
        checkpoint.sequence,
        checkpoint.baseRevision,
        checkpoint.positionMs,
        checkpoint.state.name,
        nowMs,
      ],
    );
  }

  Future<void> upsertCanonical(
    ProgressCheckpoint checkpoint,
    int revision,
    int nowMs,
  ) async {
    await _db.customStatement(
      '''
      INSERT INTO playback_progress
        (owner_id, material_id, position_ms, state, device_id, session_id, sequence, revision, updated_at_ms)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(owner_id, material_id) DO UPDATE SET
        position_ms=excluded.position_ms, state=excluded.state, device_id=excluded.device_id,
        session_id=excluded.session_id, sequence=excluded.sequence, revision=excluded.revision,
        updated_at_ms=excluded.updated_at_ms
      WHERE excluded.revision > playback_progress.revision
    ''',
      [
        checkpoint.stream.ownerId,
        checkpoint.stream.materialId,
        checkpoint.positionMs,
        checkpoint.state.name,
        checkpoint.stream.deviceId,
        checkpoint.stream.sessionId,
        checkpoint.sequence,
        revision,
        nowMs,
      ],
    );
  }

  ProgressCheckpoint _checkpointFromCanonical(
    QueryRow row,
    String materialId,
  ) => ProgressCheckpoint(
    stream: (
      ownerId: _scope.ownerId,
      materialId: materialId,
      deviceId: row.read<String>('device_id'),
      sessionId: row.read<String>('session_id'),
    ),
    positionMs: row.read<int>('position_ms'),
    state: CheckpointState.values.byName(row.read<String>('state')),
    sequence: row.read<int>('sequence'),
    baseRevision: row.read<int>('revision'),
  );

  ProgressCheckpoint _checkpointFromConflict(
    QueryRow row,
    ProgressStream stream,
  ) => ProgressCheckpoint(
    stream: stream,
    positionMs: row.read<int>('position_ms'),
    state: CheckpointState.values.byName(row.read<String>('state')),
    sequence: row.read<int>('sequence'),
    baseRevision: row.read<int>('base_revision'),
  );
}
