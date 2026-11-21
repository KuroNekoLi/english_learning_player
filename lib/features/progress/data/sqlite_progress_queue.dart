import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/account_scope.dart';
import '../../../core/db/local_database.dart';
import '../domain/progress_models.dart';
import 'progress_payload_codec.dart';
import 'progress_repository.dart';

/// Owns lease, retry and auth transitions for progress outbox operations.
final class SqliteProgressQueue {
  const SqliteProgressQueue(this._scope, this._db);

  final AccountScope _scope;
  final LocalDatabase _db;

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
        checkpoint: decodeProgressCheckpoint(row.read<String>('payload_json')),
        payloadHash: row.read<String>('payload_hash'),
        attempts: row.read<int>('attempts'),
        resolution: resolution,
      );
    });
  }

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

  Future<void> waitForAuthentication(String opId, DateTime now) async {
    await _db.customStatement(
      '''UPDATE sync_outbox SET state = 'waitingForAuth', lease_until_ms = NULL,
      last_error = 'unauthenticated', updated_at_ms = ?
      WHERE owner_id = ? AND op_id = ? AND entity_type = 'progress' ''',
      [now.millisecondsSinceEpoch, _scope.ownerId, opId],
    );
  }

  Future<void> resumeAuthenticated(DateTime now) async {
    await _db.customStatement(
      '''UPDATE sync_outbox SET state = 'queued', next_retry_at_ms = ?,
      last_error = NULL, updated_at_ms = ? WHERE owner_id = ? AND entity_type = 'progress'
      AND state = 'waitingForAuth' ''',
      [now.millisecondsSinceEpoch, now.millisecondsSinceEpoch, _scope.ownerId],
    );
  }

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
}
