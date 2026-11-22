import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/account_scope.dart';
import '../db/local_database.dart';
import 'sync_contracts.dart';

final class SqliteSyncOutbox implements SyncOutbox {
  SqliteSyncOutbox({required AccountScope scope, required LocalDatabase db})
    : _scope = scope,
      _db = db;

  final AccountScope _scope;
  final LocalDatabase _db;

  static const _uuid = Uuid();

  /// Must be called inside the material repository's transaction.
  static Future<String> enqueueMaterialInTransaction({
    required LocalDatabase db,
    required String ownerId,
    required String materialId,
    required String payloadJson,
    required int nowMs,
  }) async {
    final opId = _uuid.v4();
    final payloadHash = _hashPayload(payloadJson);
    await db.customStatement(
      '''
      INSERT INTO sync_outbox
        (owner_id, op_id, entity_type, entity_id, operation, payload_version,
         payload_json, payload_hash, attempts, next_retry_at_ms, state,
         created_at_ms, updated_at_ms)
      VALUES (?, ?, 'material', ?, 'uploadMaterial', 1, ?, ?, 0, ?, 'queued', ?, ?)
      ''',
      [
        ownerId,
        opId,
        materialId,
        payloadJson,
        payloadHash,
        nowMs,
        nowMs,
        nowMs,
      ],
    );
    await db.customStatement(
      '''
      INSERT INTO material_sync_state
        (owner_id, material_id, state, last_error, last_synced_at_ms)
      VALUES (?, ?, 'localReady', NULL, NULL)
      ''',
      [ownerId, materialId],
    );
    return opId;
  }

  static String payloadHash(String payloadJson) => _hashPayload(payloadJson);

  static String canonicalMaterialPayload({
    required String materialId,
    required String title,
    required String assetId,
    required String sha256,
    required int byteLength,
    required String mediaType,
  }) => jsonEncode({
    'schemaVersion': 1,
    'materialId': materialId,
    'title': title,
    'assetId': assetId,
    'sha256': sha256,
    'byteLength': byteLength,
    'mediaType': mediaType,
  });

  static const _eligibleMedia = '''
        WHERE job.owner_id = ?1 AND job.next_retry_at_ms <= ?2
          AND NOT EXISTS (
            SELECT 1 FROM library_changes AS change
            WHERE change.owner_id = job.owner_id AND change.entity_id = job.entity_id
              AND change.field = 'materialDeleted'
          )
          AND (job.state IN ('queued', 'waitingForAuth') OR (job.state = 'leased' AND job.lease_until_ms <= ?3))
          AND (
            job.entity_type = 'material'
            OR (job.entity_type = 'subtitle'
              AND EXISTS (
                SELECT 1 FROM sync_outbox AS parent
                WHERE parent.owner_id = job.owner_id AND parent.entity_id = job.entity_id
                  AND parent.entity_type = 'material' AND parent.state = 'completed'
              ) AND NOT EXISTS (
                SELECT 1 FROM sync_outbox AS peer
                WHERE peer.owner_id = job.owner_id AND peer.entity_id = job.entity_id
                  AND peer.entity_type = 'subtitle' AND peer.state = 'leased'
                  AND peer.lease_until_ms > ?3
                  AND peer.op_id != job.op_id
              )
            )
          )
  ''';

  List<Variable<Object>> _dueVariables(String ownerId, int nowMs) => [
    Variable.withString(ownerId),
    Variable.withInt(nowMs),
    Variable.withInt(nowMs),
  ];

  Future<bool> hasDueMedia(DateTime now) async {
    final rows = await _db
        .customSelect(
          'SELECT 1 FROM sync_outbox AS job $_eligibleMedia LIMIT 1',
          variables: _dueVariables(_scope.ownerId, now.millisecondsSinceEpoch),
        )
        .get();
    return rows.isNotEmpty;
  }

  @override
  Future<SyncOperation?> claimNext(String ownerId, DateTime now) async {
    _checkOwner(ownerId);
    final nowMs = now.millisecondsSinceEpoch;
    return _db.transaction(() async {
      final rows = await _db
          .customSelect(
            '''
        SELECT job.op_id, job.entity_id, job.entity_type, job.payload_json,
               job.payload_hash, job.attempts
        FROM sync_outbox AS job
        $_eligibleMedia AND job.state != 'waitingForAuth'
        ORDER BY job.created_at_ms, job.op_id LIMIT 1
        ''',
            variables: [
              Variable.withString(ownerId),
              Variable.withInt(nowMs),
              Variable.withInt(nowMs),
            ],
          )
          .get();
      if (rows.isEmpty) return null;
      final row = rows.single;
      final operation = _operationFromRow(ownerId, row);
      await _db.customStatement(
        '''
        UPDATE sync_outbox SET state = 'leased', lease_until_ms = ?, updated_at_ms = ?
        WHERE owner_id = ? AND op_id = ?
        ''',
        [
          nowMs + const Duration(minutes: 2).inMilliseconds,
          nowMs,
          ownerId,
          operation.opId,
        ],
      );
      if (operation.kind == SyncOperationKind.material) {
        await _db.customStatement(
          '''
        UPDATE material_sync_state SET state = 'uploading', last_error = NULL
        WHERE owner_id = ? AND material_id = ?
        ''',
          [ownerId, operation.entityId],
        );
      }
      return operation;
    });
  }

  @override
  Future<void> complete(String ownerId, String opId, DateTime now) async {
    _checkOwner(ownerId);
    final nowMs = now.millisecondsSinceEpoch;
    await _db.transaction(() async {
      final operation = await _findLeased(ownerId, opId);
      await _db.customStatement(
        '''
        UPDATE sync_outbox SET state = 'completed', lease_until_ms = NULL,
          last_error = NULL, updated_at_ms = ? WHERE owner_id = ? AND op_id = ?
        ''',
        [nowMs, ownerId, opId],
      );
      if (operation.kind != SyncOperationKind.material) return;
      await _db.customStatement(
        '''
        UPDATE material_sync_state SET state = 'cloudReady', last_error = NULL,
          last_synced_at_ms = ? WHERE owner_id = ? AND material_id = ?
        ''',
        [nowMs, ownerId, operation.entityId],
      );
    });
  }

  @override
  Future<void> release(String ownerId, String opId, DateTime now) async {
    _checkOwner(ownerId);
    final nowMs = now.millisecondsSinceEpoch;
    await _db.transaction(() async {
      final operation = await _findLeased(ownerId, opId);
      if (await _deleteSupersededSubtitle(operation)) return;
      await _db.customStatement(
        '''UPDATE sync_outbox SET state = 'queued', next_retry_at_ms = ?,
         lease_until_ms = NULL, updated_at_ms = ?
         WHERE owner_id = ? AND op_id = ?''',
        [nowMs, nowMs, ownerId, opId],
      );
      if (operation.kind != SyncOperationKind.material) return;
      await _db.customStatement(
        '''UPDATE material_sync_state SET state = 'localReady'
           WHERE owner_id = ? AND material_id = ?''',
        [ownerId, operation.entityId],
      );
    });
  }

  @override
  Future<void> deferForAuthentication(
    String ownerId,
    String opId,
    DateTime now,
  ) async {
    _checkOwner(ownerId);
    final nowMs = now.millisecondsSinceEpoch;
    await _db.transaction(() async {
      final operation = await _findLeased(ownerId, opId);
      if (await _deleteSupersededSubtitle(operation)) return;
      await _db.customStatement(
        '''UPDATE sync_outbox SET state = 'waitingForAuth', lease_until_ms = NULL,
          last_error = 'unauthenticated', updated_at_ms = ?
          WHERE owner_id = ? AND op_id = ?''',
        [nowMs, ownerId, opId],
      );
      if (operation.kind != SyncOperationKind.material) return;
      await _db.customStatement(
        '''UPDATE material_sync_state SET state = 'localReady', last_error = 'unauthenticated'
          WHERE owner_id = ? AND material_id = ?''',
        [ownerId, operation.entityId],
      );
    });
  }

  @override
  Future<void> fail({
    required String ownerId,
    required String opId,
    required String code,
    required bool retryable,
    required DateTime now,
    required DateTime? retryAt,
  }) async {
    _checkOwner(ownerId);
    final nowMs = now.millisecondsSinceEpoch;
    await _db.transaction(() async {
      final operation = await _findLeased(ownerId, opId);
      if (await _deleteSupersededSubtitle(operation)) return;
      final nextAttempts = operation.attempts + (retryable ? 1 : 0);
      final needsAttention = !retryable || nextAttempts >= 8;
      await _db.customStatement(
        '''UPDATE sync_outbox SET state = ?, attempts = ?, next_retry_at_ms = ?,
          lease_until_ms = NULL, last_error = ?, updated_at_ms = ?
          WHERE owner_id = ? AND op_id = ?''',
        [
          needsAttention ? 'needsAttention' : 'queued',
          nextAttempts,
          (retryAt ?? now).millisecondsSinceEpoch,
          code,
          nowMs,
          ownerId,
          opId,
        ],
      );
      if (operation.kind != SyncOperationKind.material) return;
      await _db.customStatement(
        '''UPDATE material_sync_state SET state = ?, last_error = ?
          WHERE owner_id = ? AND material_id = ?''',
        [
          needsAttention ? 'error' : 'localReady',
          code,
          ownerId,
          operation.entityId,
        ],
      );
    });
  }

  @override
  Future<void> resumeAuthenticated(String ownerId, DateTime now) async {
    _checkOwner(ownerId);
    final nowMs = now.millisecondsSinceEpoch;
    await _db.customStatement(
      '''UPDATE sync_outbox SET state = 'queued', next_retry_at_ms = ?,
        last_error = NULL, updated_at_ms = ?
        WHERE owner_id = ? AND entity_type IN ('material', 'subtitle')
          AND state = 'waitingForAuth' ''',
      [nowMs, nowMs, ownerId],
    );
    await _db.customStatement(
      '''UPDATE material_sync_state SET state = 'localReady', last_error = NULL
        WHERE owner_id = ? AND state = 'localReady' AND last_error = 'unauthenticated' ''',
      [ownerId],
    );
  }

  @override
  Future<void> retryNeedsAttention(
    String ownerId,
    String opId,
    DateTime now,
  ) async {
    _checkOwner(ownerId);
    final nowMs = now.millisecondsSinceEpoch;
    await _db.transaction(() async {
      final row = await _db
          .customSelect(
            '''SELECT entity_type, entity_id FROM sync_outbox WHERE owner_id = ? AND op_id = ?
           AND entity_type IN ('material', 'subtitle') AND state = 'needsAttention' ''',
            variables: [
              Variable.withString(ownerId),
              Variable.withString(opId),
            ],
          )
          .getSingleOrNull();
      if (row == null) {
        throw StateError('Outbox operation is not awaiting attention.');
      }
      await _db.customStatement(
        '''UPDATE sync_outbox SET state = 'queued', attempts = 0,
          next_retry_at_ms = ?, lease_until_ms = NULL, last_error = NULL,
          updated_at_ms = ? WHERE owner_id = ? AND op_id = ?''',
        [nowMs, nowMs, ownerId, opId],
      );
      if (row.read<String>('entity_type') != 'material') return;
      await _db.customStatement(
        '''UPDATE material_sync_state SET state = 'localReady', last_error = NULL
          WHERE owner_id = ? AND material_id = ?''',
        [ownerId, row.read<String>('entity_id')],
      );
    });
  }

  Future<SyncOperation> _findLeased(String ownerId, String opId) async {
    final rows = await _db
        .customSelect(
          '''SELECT op_id, entity_id, entity_type, payload_json, payload_hash, attempts
        FROM sync_outbox WHERE owner_id = ? AND op_id = ? AND state = 'leased'
          AND entity_type IN ('material', 'subtitle') ''',
          variables: [Variable.withString(ownerId), Variable.withString(opId)],
        )
        .get();
    if (rows.isEmpty) throw StateError('Outbox operation is not leased.');
    return _operationFromRow(ownerId, rows.single);
  }

  /// An edit made during a lease already queued the latest selection. Keep
  /// that job when the old attempt cannot complete.
  Future<bool> _deleteSupersededSubtitle(SyncOperation operation) async {
    if (operation.kind != SyncOperationKind.subtitle) return false;
    final removed = await _db.customUpdate(
      '''DELETE FROM sync_outbox WHERE owner_id = ? AND op_id = ? AND EXISTS (
         SELECT 1 FROM sync_outbox AS newer WHERE newer.owner_id = ?
           AND newer.entity_type = 'subtitle' AND newer.entity_id = ?
           AND newer.state = 'queued'
       )''',
      variables: [
        Variable.withString(operation.ownerId),
        Variable.withString(operation.opId),
        Variable.withString(operation.ownerId),
        Variable.withString(operation.entityId),
      ],
    );
    return removed != 0;
  }

  SyncOperation _operationFromRow(String ownerId, QueryRow row) =>
      SyncOperation(
        ownerId: ownerId,
        opId: row.read<String>('op_id'),
        entityId: row.read<String>('entity_id'),
        payloadJson: row.read<String>('payload_json'),
        payloadHash: row.read<String>('payload_hash'),
        attempts: row.read<int>('attempts'),
        kind: SyncOperationKind.values.byName(row.read<String>('entity_type')),
      );

  void _checkOwner(String ownerId) {
    if (ownerId != _scope.ownerId) {
      throw ArgumentError.value(ownerId, 'ownerId', 'Outbox owner mismatch.');
    }
  }
}

String _hashPayload(String payloadJson) =>
    sha256.convert(utf8.encode(payloadJson)).toString();
