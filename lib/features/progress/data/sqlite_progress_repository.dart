import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/account_scope.dart';
import '../../../core/db/local_database.dart';
import '../../../core/sync/progress_policy.dart';
import '../../../core/sync/sync_contracts.dart';
import '../domain/progress_models.dart';
import 'progress_repository.dart';
import 'progress_payload_codec.dart';
import 'sqlite_progress_positions.dart';
import 'sqlite_progress_queue.dart';

final class SqliteProgressRepository implements ProgressRepository {
  SqliteProgressRepository({
    required AccountScope scope,
    required LocalDatabase db,
  }) : _scope = scope,
       _db = db;

  final AccountScope _scope;
  final LocalDatabase _db;
  static const _uuid = Uuid();
  late final _positions = SqliteProgressPositions(_scope, _db);

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
      final payload = encodeProgressCheckpoint(checkpoint);
      await _insertOutbox(stream, payload, nowMs, operation: 'writeProgress');
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
  Future<CanonicalProgress?> canonical(String materialId) =>
      _positions.canonical(materialId);

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
      await _positions.upsertCanonical(checkpoint, revision, nowMs);
    });
  }

  @override
  Future<List<ProgressCandidate>> unresolvedCandidates(String materialId) =>
      _positions.unresolvedCandidates(materialId);

  SqliteProgressQueue get _queue => SqliteProgressQueue(_scope, _db);

  @override
  Future<PendingProgressOperation?> claimNext(DateTime now) =>
      _queue.claimNext(now);

  @override
  Future<void> defer({
    required String opId,
    required String code,
    required bool retryable,
    required DateTime now,
    required DateTime retryAt,
  }) => _queue.defer(
    opId: opId,
    code: code,
    retryable: retryable,
    now: now,
    retryAt: retryAt,
  );

  @override
  Future<void> waitForAuthentication(String opId, DateTime now) =>
      _queue.waitForAuthentication(opId, now);

  @override
  Future<void> resumeAuthenticated(DateTime now) =>
      _queue.resumeAuthenticated(now);

  @override
  Future<void> retryNeedsAttention(String opId, DateTime now) =>
      _queue.retryNeedsAttention(opId, now);

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
      if (hashProgressPayload(payload) != payloadHash) {
        throw StateError('Progress operation payload hash mismatch.');
      }
      final checkpoint = decodeProgressCheckpoint(payload);
      final snapshot = result.canonicalCheckpoint;
      if (checkpoint.stream.ownerId != _scope.ownerId ||
          checkpoint.stream.materialId != row.read<String>('entity_id') ||
          result.canonicalRevision < 0 ||
          (result.status == ProgressCommitStatus.accepted &&
              result.canonicalRevision == 0) ||
          (snapshot != null &&
              (snapshot.stream.ownerId != _scope.ownerId ||
                  snapshot.stream.materialId !=
                      checkpoint.stream.materialId))) {
        throw const SyncFailure(
          SyncFailureKind.invalidData,
          'invalid_progress_receipt',
        );
      }
      switch (result.status) {
        case ProgressCommitStatus.accepted:
          await _positions.upsertCanonical(
            checkpoint,
            result.canonicalRevision,
            nowMs,
          );
          final resolutionPayload = jsonDecode(payload) as Map<String, dynamic>;
          final resolvedCandidateId = resolutionPayload['resolveCandidateId'];
          if (resolvedCandidateId is String) {
            await _positions.markResolved(resolvedCandidateId, nowMs);
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
            await _positions.upsertCanonical(
              canonical,
              result.canonicalRevision,
              nowMs,
            );
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
            await _positions.upsertCanonical(
              canonical,
              result.canonicalRevision,
              nowMs,
            );
          }
          if (!isResolution) {
            await _positions.saveConflict(candidateId!, checkpoint, nowMs);
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
      final canonical = await _positions.canonical(resolutionStream.materialId);
      final currentRevision = canonical?.revision ?? 0;
      if (currentRevision != observedCanonicalRevision) {
        throw StateError(
          'Canonical progress changed; refresh before resolving.',
        );
      }
      final candidate = await _positions.unresolvedCandidate(
        candidateId,
        resolutionStream,
      );
      if (candidate == null) {
        throw StateError('Progress candidate is no longer available.');
      }
      final chosen = useCandidatePosition ? candidate : canonical?.checkpoint;
      if (chosen == null) {
        throw StateError('No canonical position exists to retain.');
      }
      final payload = encodeProgressCheckpoint(
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
        hashProgressPayload(payload),
        nowMs,
        nowMs,
        nowMs,
      ],
    );
  }

  void _checkOwner(String ownerId) {
    if (ownerId != _scope.ownerId) {
      throw ArgumentError('Progress owner does not match database scope.');
    }
  }
}
