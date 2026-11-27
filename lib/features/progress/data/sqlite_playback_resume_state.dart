import 'package:drift/drift.dart';

import '../../../core/db/account_scope.dart';
import '../../../core/db/local_database.dart';
import '../../../core/sync/progress_policy.dart';
import '../domain/progress_models.dart';

/// Stores local resume checkpoints separately from server-canonical progress.
/// This lets an offline device resume its own playback without silently
/// overwriting a remote revision or resolving a conflict.
final class SqlitePlaybackResumeState {
  const SqlitePlaybackResumeState(this._scope, this._db);

  final AccountScope _scope;
  final LocalDatabase _db;

  Future<int?> position(String materialId) async {
    final rows = await _db
        .customSelect(
          '''SELECT position_ms FROM playback_resume_state
             WHERE owner_id = ? AND material_id = ?''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(materialId),
          ],
        )
        .get();
    return rows.isEmpty ? null : rows.single.read<int>('position_ms');
  }

  Future<LocalPlaybackPosition?> mostRecentlyPlayed() async {
    final row = await _db
        .customSelect(
          '''SELECT material_id, position_ms, last_played_at_ms
             FROM playback_resume_state
             WHERE owner_id = ? AND last_played_at_ms > 0
             ORDER BY last_played_at_ms DESC, updated_at_ms DESC
             LIMIT 1''',
          variables: [Variable.withString(_scope.ownerId)],
        )
        .getSingleOrNull();
    if (row == null) return null;
    return LocalPlaybackPosition(
      materialId: row.read<String>('material_id'),
      positionMs: row.read<int>('position_ms'),
      lastPlayedAtMs: row.read<int>('last_played_at_ms'),
    );
  }

  Future<void> recordLocal(ProgressCheckpoint checkpoint, int nowMs) async {
    final previous = await _db
        .customSelect(
          '''SELECT updated_at_ms, last_played_at_ms
             FROM playback_resume_state
             WHERE owner_id = ? AND material_id = ?''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(checkpoint.stream.materialId),
          ],
        )
        .getSingleOrNull();
    final previousUpdated = previous?.read<int>('updated_at_ms') ?? 0;
    final updatedAt = nowMs > previousUpdated ? nowMs : previousUpdated + 1;
    final previousPlayedAt = previous?.read<int>('last_played_at_ms') ?? 0;
    final lastPlayedAt =
        checkpoint.state == CheckpointState.playing || checkpoint.positionMs > 0
        ? updatedAt
        : previousPlayedAt;
    await _db.customStatement(
      '''INSERT INTO playback_resume_state
        (owner_id, material_id, position_ms, state, device_id, session_id,
         sequence, base_revision, sync_state, last_played_at_ms, updated_at_ms)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?)
        ON CONFLICT(owner_id, material_id) DO UPDATE SET
          position_ms = excluded.position_ms,
          state = excluded.state,
          device_id = excluded.device_id,
          session_id = excluded.session_id,
          sequence = excluded.sequence,
          base_revision = excluded.base_revision,
          sync_state = 'pending',
          last_played_at_ms = MAX(playback_resume_state.last_played_at_ms,
                                  excluded.last_played_at_ms),
          updated_at_ms = excluded.updated_at_ms
        WHERE excluded.updated_at_ms > playback_resume_state.updated_at_ms''',
      [
        _scope.ownerId,
        checkpoint.stream.materialId,
        checkpoint.positionMs,
        checkpoint.state.name,
        checkpoint.stream.deviceId,
        checkpoint.stream.sessionId,
        checkpoint.sequence,
        checkpoint.baseRevision,
        lastPlayedAt,
        updatedAt,
      ],
    );
  }

  Future<void> applyRemoteCanonical(
    ProgressCheckpoint checkpoint,
    int revision,
    int nowMs,
  ) async {
    final row = await _db
        .customSelect(
          '''SELECT sync_state, last_played_at_ms, updated_at_ms
             FROM playback_resume_state
             WHERE owner_id = ? AND material_id = ?''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(checkpoint.stream.materialId),
          ],
        )
        .getSingleOrNull();
    if (row != null && row.read<String>('sync_state') != 'synced') return;
    final previousPlayedAt = row?.read<int>('last_played_at_ms') ?? 0;
    final lastPlayedAt =
        checkpoint.state == CheckpointState.playing || checkpoint.positionMs > 0
        ? (nowMs > previousPlayedAt ? nowMs : previousPlayedAt + 1)
        : previousPlayedAt;
    final previousUpdated = row?.read<int>('updated_at_ms') ?? 0;
    final updatedAt = nowMs > previousUpdated ? nowMs : previousUpdated + 1;
    await _db.customStatement(
      '''INSERT INTO playback_resume_state
        (owner_id, material_id, position_ms, state, device_id, session_id,
         sequence, base_revision, sync_state, last_played_at_ms, updated_at_ms)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'synced', ?, ?)
        ON CONFLICT(owner_id, material_id) DO UPDATE SET
          position_ms = excluded.position_ms,
          state = excluded.state,
          device_id = excluded.device_id,
          session_id = excluded.session_id,
          sequence = excluded.sequence,
          base_revision = excluded.base_revision,
          sync_state = 'synced',
          last_played_at_ms = excluded.last_played_at_ms,
          updated_at_ms = excluded.updated_at_ms
        WHERE playback_resume_state.sync_state = 'synced'
          AND excluded.base_revision > playback_resume_state.base_revision''',
      [
        _scope.ownerId,
        checkpoint.stream.materialId,
        checkpoint.positionMs,
        checkpoint.state.name,
        checkpoint.stream.deviceId,
        checkpoint.stream.sessionId,
        checkpoint.sequence,
        revision,
        lastPlayedAt,
        updatedAt,
      ],
    );
  }

  Future<void> applyCommit(ProgressCheckpoint checkpoint, int revision) async {
    await _db.customStatement(
      '''UPDATE playback_resume_state
         SET sync_state = 'synced', base_revision = ?
         WHERE owner_id = ? AND material_id = ? AND device_id = ?
           AND session_id = ? AND sequence = ? AND sync_state = 'pending' ''',
      [
        revision,
        _scope.ownerId,
        checkpoint.stream.materialId,
        checkpoint.stream.deviceId,
        checkpoint.stream.sessionId,
        checkpoint.sequence,
      ],
    );
  }

  Future<void> applyResolution(
    ProgressCheckpoint checkpoint,
    int revision,
    int nowMs,
  ) async {
    final row = await _db
        .customSelect(
          '''SELECT last_played_at_ms, updated_at_ms
             FROM playback_resume_state
             WHERE owner_id = ? AND material_id = ?''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(checkpoint.stream.materialId),
          ],
        )
        .getSingleOrNull();
    final previousPlayedAt = row?.read<int>('last_played_at_ms') ?? 0;
    final lastPlayedAt =
        checkpoint.state == CheckpointState.playing || checkpoint.positionMs > 0
        ? (nowMs > previousPlayedAt ? nowMs : previousPlayedAt + 1)
        : previousPlayedAt;
    final previousUpdated = row?.read<int>('updated_at_ms') ?? 0;
    final updatedAt = nowMs > previousUpdated ? nowMs : previousUpdated + 1;
    await _db.customStatement(
      '''INSERT INTO playback_resume_state
        (owner_id, material_id, position_ms, state, device_id, session_id,
         sequence, base_revision, sync_state, last_played_at_ms, updated_at_ms)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'synced', ?, ?)
        ON CONFLICT(owner_id, material_id) DO UPDATE SET
          position_ms = excluded.position_ms,
          state = excluded.state,
          device_id = excluded.device_id,
          session_id = excluded.session_id,
          sequence = excluded.sequence,
          base_revision = excluded.base_revision,
          sync_state = 'synced',
          last_played_at_ms = excluded.last_played_at_ms,
          updated_at_ms = excluded.updated_at_ms''',
      [
        _scope.ownerId,
        checkpoint.stream.materialId,
        checkpoint.positionMs,
        checkpoint.state.name,
        checkpoint.stream.deviceId,
        checkpoint.stream.sessionId,
        checkpoint.sequence,
        revision,
        lastPlayedAt,
        updatedAt,
      ],
    );
  }

  Future<void> markConflict(ProgressCheckpoint checkpoint) async {
    await _db.customStatement(
      '''UPDATE playback_resume_state SET sync_state = 'conflict'
         WHERE owner_id = ? AND material_id = ? AND device_id = ?
           AND session_id = ? AND sync_state = 'pending' ''',
      [
        _scope.ownerId,
        checkpoint.stream.materialId,
        checkpoint.stream.deviceId,
        checkpoint.stream.sessionId,
      ],
    );
  }
}
