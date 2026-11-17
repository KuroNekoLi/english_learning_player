import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/account_scope.dart';
import '../../../core/db/local_database.dart';
import '../../../core/sync/progress_policy.dart';
import '../domain/progress_models.dart';
import 'progress_repository.dart';

final class SqliteProgressRepository implements ProgressRepository {
  SqliteProgressRepository({
    required AccountScope scope,
    required LocalDatabase db,
  }) : _scope = scope,
       _db = db;

  final AccountScope _scope;
  final LocalDatabase _db;
  static const _uuid = Uuid();

  @override
  Future<String> deviceId() async {
    await _db.customStatement(
      'INSERT OR IGNORE INTO progress_device_identity (owner_id, device_id) VALUES (?, ?)',
      [_scope.ownerId, _uuid.v4()],
    );
    final rows = await _db
        .customSelect(
          'SELECT device_id FROM progress_device_identity WHERE owner_id = ?',
          variables: [Variable.withString(_scope.ownerId)],
        )
        .get();
    return rows.single.read<String>('device_id');
  }

  @override
  Future<ProgressCheckpoint> recordCheckpoint({
    required ProgressStream stream,
    required int positionMs,
    required CheckpointState state,
    required int nowMs,
  }) async {
    _checkOwner(stream.ownerId);
    final provisional = ProgressCheckpoint(
      stream: stream,
      positionMs: positionMs,
      state: state,
      sequence: 1,
      baseRevision: 0,
    );
    return _db.transaction(() async {
      final canonicalRows = await _db
          .customSelect(
            'SELECT revision FROM playback_progress WHERE owner_id = ? AND material_id = ?',
            variables: [
              Variable.withString(stream.ownerId),
              Variable.withString(stream.materialId),
            ],
          )
          .get();
      final canonicalRevision = canonicalRows.isEmpty
          ? 0
          : canonicalRows.single.read<int>('revision');
      await _db.customStatement(
        '''
        INSERT OR IGNORE INTO progress_stream_state
          (owner_id, material_id, device_id, session_id, next_sequence, confirmed_revision)
        VALUES (?, ?, ?, ?, 1, ?)
      ''',
        [
          stream.ownerId,
          stream.materialId,
          stream.deviceId,
          stream.sessionId,
          canonicalRevision,
        ],
      );
      final streamRows = await _db
          .customSelect(
            '''
        SELECT next_sequence, confirmed_revision FROM progress_stream_state
        WHERE owner_id = ? AND material_id = ? AND device_id = ? AND session_id = ?
      ''',
            variables: [
              Variable.withString(stream.ownerId),
              Variable.withString(stream.materialId),
              Variable.withString(stream.deviceId),
              Variable.withString(stream.sessionId),
            ],
          )
          .get();
      final sequence = streamRows.single.read<int>('next_sequence');
      final baseRevision = streamRows.single.read<int>('confirmed_revision');
      final checkpoint = ProgressCheckpoint(
        stream: provisional.stream,
        positionMs: provisional.positionMs,
        state: provisional.state,
        sequence: sequence,
        baseRevision: baseRevision,
      );
      final payload = _encodeCheckpoint(checkpoint);
      final opId = _uuid.v4();
      await _db.customStatement(
        '''
        INSERT INTO sync_outbox
          (owner_id, op_id, entity_type, entity_id, operation, payload_version,
           payload_json, payload_hash, attempts, next_retry_at_ms, state,
           created_at_ms, updated_at_ms)
        VALUES (?, ?, 'progress', ?, 'writeProgress', 1, ?, ?, 0, ?, 'queued', ?, ?)
      ''',
        [
          stream.ownerId,
          opId,
          stream.materialId,
          payload,
          _hash(payload),
          nowMs,
          nowMs,
          nowMs,
        ],
      );
      await _db.customStatement(
        '''
        UPDATE progress_stream_state SET next_sequence = ?
        WHERE owner_id = ? AND material_id = ? AND device_id = ? AND session_id = ?
      ''',
        [
          sequence + 1,
          stream.ownerId,
          stream.materialId,
          stream.deviceId,
          stream.sessionId,
        ],
      );
      return checkpoint;
    });
  }

  @override
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
    final revision = row.read<int>('revision');
    return CanonicalProgress(
      checkpoint: ProgressCheckpoint(
        stream: (
          ownerId: _scope.ownerId,
          materialId: materialId,
          deviceId: row.read<String>('device_id'),
          sessionId: row.read<String>('session_id'),
        ),
        positionMs: row.read<int>('position_ms'),
        state: CheckpointState.values.byName(row.read<String>('state')),
        sequence: row.read<int>('sequence'),
        baseRevision: revision,
      ),
      revision: revision,
    );
  }

  @override
  Future<void> mergeRemoteCanonical({
    required ProgressCheckpoint checkpoint,
    required int revision,
    required int nowMs,
  }) async {
    _checkOwner(checkpoint.stream.ownerId);
    if (revision < 1) throw ArgumentError.value(revision, 'revision');
    await _db.transaction(() async {
      final current = await canonical(checkpoint.stream.materialId);
      if (current != null && current.revision >= revision) return;
      await _upsertCanonical(checkpoint, revision, nowMs);
    });
  }

  @override
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

  @override
  Future<PendingProgressOperation?> claimNext(DateTime now) async {
    final nowMs = now.millisecondsSinceEpoch;
    return _db.transaction(() async {
      final rows = await _db
          .customSelect(
            '''
        SELECT op_id, operation, payload_json, payload_hash, attempts FROM sync_outbox
        WHERE owner_id = ? AND entity_type = 'progress' AND next_retry_at_ms <= ?
          AND (state = 'queued' OR (state = 'leased' AND lease_until_ms <= ?))
        ORDER BY created_at_ms, op_id LIMIT 1
      ''',
            variables: [
              Variable.withString(_scope.ownerId),
              Variable.withInt(nowMs),
              Variable.withInt(nowMs),
            ],
          )
          .get();
      if (rows.isEmpty) return null;
      final row = rows.single;
      await _db.customStatement(
        '''UPDATE sync_outbox SET state = 'leased', lease_until_ms = ?, updated_at_ms = ?
        WHERE owner_id = ? AND op_id = ?''',
        [
          nowMs + const Duration(minutes: 2).inMilliseconds,
          nowMs,
          _scope.ownerId,
          row.read<String>('op_id'),
        ],
      );
      final payload =
          jsonDecode(row.read<String>('payload_json')) as Map<String, dynamic>;
      final resolution = row.read<String>('operation') == 'resolveProgress'
          ? ProgressResolution(
              candidateId: payload['resolveCandidateId'] as String,
              observedCanonicalRevision:
                  payload['observedCanonicalRevision'] as int,
              useCandidatePosition: payload['useCandidatePosition'] as bool,
            )
          : null;
      return PendingProgressOperation(
        opId: row.read<String>('op_id'),
        checkpoint: _decodeCheckpoint(jsonEncode(payload)),
        payloadHash: row.read<String>('payload_hash'),
        attempts: row.read<int>('attempts'),
        resolution: resolution,
      );
    });
  }

  @override
  Future<void> defer({
    required String opId,
    required String code,
    required bool retryable,
    required DateTime now,
    required DateTime retryAt,
  }) async {
    final rows = await _db
        .customSelect(
          '''SELECT attempts FROM sync_outbox
      WHERE owner_id = ? AND op_id = ? AND entity_type = 'progress' AND state = 'leased' ''',
          variables: [
            Variable.withString(_scope.ownerId),
            Variable.withString(opId),
          ],
        )
        .get();
    if (rows.isEmpty) throw StateError('Progress operation is not leased.');
    final attempts = rows.single.read<int>('attempts') + (retryable ? 1 : 0);
    final state = retryable && attempts < 8 ? 'queued' : 'needsAttention';
    await _db.customStatement(
      '''UPDATE sync_outbox SET state = ?, attempts = ?, next_retry_at_ms = ?,
      lease_until_ms = NULL, last_error = ?, updated_at_ms = ? WHERE owner_id = ? AND op_id = ?''',
      [
        state,
        attempts,
        retryAt.millisecondsSinceEpoch,
        code,
        now.millisecondsSinceEpoch,
        _scope.ownerId,
        opId,
      ],
    );
  }

  @override
  Future<void> waitForAuthentication(String opId, DateTime now) async {
    await _db.customStatement(
      '''UPDATE sync_outbox SET state = 'waitingForAuth', lease_until_ms = NULL,
      last_error = 'unauthenticated', updated_at_ms = ?
      WHERE owner_id = ? AND op_id = ? AND entity_type = 'progress' ''',
      [now.millisecondsSinceEpoch, _scope.ownerId, opId],
    );
  }

  @override
  Future<void> resumeAuthenticated(DateTime now) async {
    await _db.customStatement(
      '''UPDATE sync_outbox SET state = 'queued', next_retry_at_ms = ?,
      last_error = NULL, updated_at_ms = ? WHERE owner_id = ? AND entity_type = 'progress'
      AND state = 'waitingForAuth' ''',
      [now.millisecondsSinceEpoch, now.millisecondsSinceEpoch, _scope.ownerId],
    );
  }

  @override
  Future<void> retryNeedsAttention(String opId, DateTime now) async {
    final nowMs = now.millisecondsSinceEpoch;
    final changed = await _db.customUpdate(
      '''UPDATE sync_outbox SET state = 'queued', attempts = 0, next_retry_at_ms = ?,
        lease_until_ms = NULL, last_error = NULL, updated_at_ms = ?
        WHERE owner_id = ? AND op_id = ? AND entity_type = 'progress' AND state = 'needsAttention' ''',
      variables: [
        Variable.withInt(nowMs),
        Variable.withInt(nowMs),
        Variable.withString(_scope.ownerId),
        Variable.withString(opId),
      ],
      updates: const {},
    );
    if (changed == 0) {
      throw StateError('Progress operation is not awaiting attention.');
    }
  }

  @override
  Future<void> applyCommitResult({
    required String opId,
    required String payloadHash,
    required ProgressCommitResult result,
    required int nowMs,
  }) async {
    await _db.transaction(() async {
      final rows = await _db
          .customSelect(
            '''
        SELECT payload_json, entity_id FROM sync_outbox
        WHERE owner_id = ? AND op_id = ? AND entity_type = 'progress'
      ''',
            variables: [
              Variable.withString(_scope.ownerId),
              Variable.withString(opId),
            ],
          )
          .get();
      if (rows.isEmpty) throw StateError('Progress operation does not exist.');
      final row = rows.single;
      final payload = row.read<String>('payload_json');
      if (_hash(payload) != payloadHash) {
        throw StateError('Progress operation payload hash mismatch.');
      }
      final checkpoint = _decodeCheckpoint(payload);
      switch (result.status) {
        case ProgressCommitStatus.accepted:
          await _upsertCanonical(checkpoint, result.canonicalRevision, nowMs);
          final resolutionPayload = jsonDecode(payload) as Map<String, dynamic>;
          final resolvedCandidateId = resolutionPayload['resolveCandidateId'];
          if (resolvedCandidateId is String) {
            await _db.customStatement(
              '''UPDATE progress_conflicts SET resolved_at_ms = ?
                WHERE owner_id = ? AND candidate_id = ? AND resolved_at_ms IS NULL''',
              [nowMs, _scope.ownerId, resolvedCandidateId],
            );
          }
          await _db.customStatement(
            '''
            UPDATE progress_stream_state SET confirmed_revision = MAX(confirmed_revision, ?)
            WHERE owner_id = ? AND material_id = ? AND device_id = ? AND session_id = ?
          ''',
            [
              result.canonicalRevision,
              _scope.ownerId,
              checkpoint.stream.materialId,
              checkpoint.stream.deviceId,
              checkpoint.stream.sessionId,
            ],
          );
        case ProgressCommitStatus.ignoredStale:
          final canonical = result.canonicalCheckpoint;
          if (canonical != null) {
            await _upsertCanonical(canonical, result.canonicalRevision, nowMs);
          }
          break;
        case ProgressCommitStatus.conflict:
          final candidateId = result.candidateId;
          final isResolution =
              (jsonDecode(payload)
                      as Map<String, dynamic>)['resolveCandidateId']
                  is String;
          if (candidateId == null && !isResolution) {
            throw StateError('Conflict result needs candidate ID.');
          }
          final canonical = result.canonicalCheckpoint;
          if (canonical != null) {
            await _upsertCanonical(canonical, result.canonicalRevision, nowMs);
          }
          if (!isResolution) {
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
          ''',
              [
                _scope.ownerId,
                candidateId!,
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
      }
      await _db.customStatement(
        '''
        UPDATE sync_outbox SET state = 'completed', lease_until_ms = NULL,
          last_error = NULL, updated_at_ms = ? WHERE owner_id = ? AND op_id = ?
      ''',
        [nowMs, _scope.ownerId, opId],
      );
    });
  }

  @override
  Future<void> resolveCandidate({
    required String candidateId,
    required int observedCanonicalRevision,
    required bool useCandidatePosition,
    required ProgressStream resolutionStream,
    required int nowMs,
  }) async {
    _checkOwner(resolutionStream.ownerId);
    await _db.transaction(() async {
      final canonicalRows = await _db
          .customSelect(
            '''
        SELECT * FROM playback_progress WHERE owner_id = ? AND material_id = ?
      ''',
            variables: [
              Variable.withString(_scope.ownerId),
              Variable.withString(resolutionStream.materialId),
            ],
          )
          .get();
      final currentRevision = canonicalRows.isEmpty
          ? 0
          : canonicalRows.single.read<int>('revision');
      if (currentRevision != observedCanonicalRevision) {
        throw StateError(
          'Canonical progress changed; refresh before resolving.',
        );
      }
      final candidateRows = await _db
          .customSelect(
            '''
        SELECT * FROM progress_conflicts WHERE owner_id = ? AND candidate_id = ?
          AND material_id = ? AND resolved_at_ms IS NULL
      ''',
            variables: [
              Variable.withString(_scope.ownerId),
              Variable.withString(candidateId),
              Variable.withString(resolutionStream.materialId),
            ],
          )
          .get();
      if (candidateRows.isEmpty) {
        throw StateError('Progress candidate is no longer available.');
      }
      final candidate = candidateRows.single;
      final existing = canonicalRows.isEmpty
          ? null
          : _checkpointFromCanonical(
              canonicalRows.single,
              resolutionStream.materialId,
            );
      final chosen = useCandidatePosition
          ? _checkpointFromConflict(candidate, resolutionStream)
          : existing;
      if (chosen == null) {
        throw StateError('No canonical position exists to retain.');
      }
      final payload = _encodeCheckpoint(
        ProgressCheckpoint(
          stream: resolutionStream,
          positionMs: chosen.positionMs,
          state: chosen.state,
          sequence: (await _nextSequence(resolutionStream)),
          baseRevision: currentRevision,
        ),
      );
      final resolutionPayload = jsonEncode({
        ...jsonDecode(payload) as Map<String, dynamic>,
        'resolveCandidateId': candidateId,
        'observedCanonicalRevision': observedCanonicalRevision,
        'useCandidatePosition': useCandidatePosition,
      });
      await _insertOutbox(
        resolutionStream,
        resolutionPayload,
        nowMs,
        operation: 'resolveProgress',
      );
    });
  }

  Future<int> _nextSequence(ProgressStream stream) async {
    await _db.customStatement(
      '''
      INSERT OR IGNORE INTO progress_stream_state
        (owner_id, material_id, device_id, session_id, next_sequence, confirmed_revision)
      VALUES (?, ?, ?, ?, 1, 0)
    ''',
      [stream.ownerId, stream.materialId, stream.deviceId, stream.sessionId],
    );
    final rows = await _db
        .customSelect(
          '''SELECT next_sequence FROM progress_stream_state
      WHERE owner_id = ? AND material_id = ? AND device_id = ? AND session_id = ?''',
          variables: [
            Variable.withString(stream.ownerId),
            Variable.withString(stream.materialId),
            Variable.withString(stream.deviceId),
            Variable.withString(stream.sessionId),
          ],
        )
        .get();
    final sequence = rows.single.read<int>('next_sequence');
    await _db.customStatement(
      '''UPDATE progress_stream_state SET next_sequence = ?
      WHERE owner_id = ? AND material_id = ? AND device_id = ? AND session_id = ?''',
      [
        sequence + 1,
        stream.ownerId,
        stream.materialId,
        stream.deviceId,
        stream.sessionId,
      ],
    );
    return sequence;
  }

  Future<void> _insertOutbox(
    ProgressStream stream,
    String payload,
    int nowMs, {
    required String operation,
  }) async {
    await _db.customStatement(
      '''INSERT INTO sync_outbox
      (owner_id, op_id, entity_type, entity_id, operation, payload_version,
       payload_json, payload_hash, attempts, next_retry_at_ms, state, created_at_ms, updated_at_ms)
      VALUES (?, ?, 'progress', ?, ?, 1, ?, ?, 0, ?, 'queued', ?, ?)''',
      [
        stream.ownerId,
        _uuid.v4(),
        stream.materialId,
        operation,
        payload,
        _hash(payload),
        nowMs,
        nowMs,
        nowMs,
      ],
    );
  }

  Future<void> _upsertCanonical(
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

  String _encodeCheckpoint(ProgressCheckpoint value) => jsonEncode({
    'schemaVersion': 1,
    'ownerId': value.stream.ownerId,
    'materialId': value.stream.materialId,
    'deviceId': value.stream.deviceId,
    'sessionId': value.stream.sessionId,
    'positionMs': value.positionMs,
    'state': value.state.name,
    'sequence': value.sequence,
    'baseRevision': value.baseRevision,
  });

  ProgressCheckpoint _decodeCheckpoint(String payload) {
    final value = jsonDecode(payload) as Map<String, dynamic>;
    return ProgressCheckpoint(
      stream: (
        ownerId: value['ownerId'] as String,
        materialId: value['materialId'] as String,
        deviceId: value['deviceId'] as String,
        sessionId: value['sessionId'] as String,
      ),
      positionMs: value['positionMs'] as int,
      state: CheckpointState.values.byName(value['state'] as String),
      sequence: value['sequence'] as int,
      baseRevision: value['baseRevision'] as int,
    );
  }

  String _hash(String payload) =>
      sha256.convert(utf8.encode(payload)).toString();

  void _checkOwner(String ownerId) {
    if (ownerId != _scope.ownerId) {
      throw ArgumentError('Progress owner does not match database scope.');
    }
  }
}
