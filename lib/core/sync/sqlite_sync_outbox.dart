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

  @override
  Future<SyncOperation?> claimNext(String ownerId, DateTime now) async {
    _checkOwner(ownerId);
    final nowMs = now.millisecondsSinceEpoch;
    return _db.transaction(() async {
      final rows = await _db
          .customSelect(
            '''
        SELECT op_id, entity_id, payload_json, payload_hash, attempts
        FROM sync_outbox
        WHERE owner_id = ?
          AND next_retry_at_ms <= ?
          AND (state = 'queued' OR (state = 'leased' AND lease_until_ms <= ?))
        ORDER BY created_at_ms, op_id LIMIT 1
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
      final opId = row.read<String>('op_id');
      await _db.customStatement(
        '''
        UPDATE sync_outbox SET state = 'leased', lease_until_ms = ?, updated_at_ms = ?
        WHERE owner_id = ? AND op_id = ?
        ''',
        [
          nowMs + const Duration(minutes: 2).inMilliseconds,
          nowMs,
          ownerId,
          opId,
        ],
      );
      await _db.customStatement(
        '''
        UPDATE material_sync_state SET state = 'uploading', last_error = NULL
        WHERE owner_id = ? AND material_id = ?
        ''',
        [ownerId, row.read<String>('entity_id')],
      );
      return SyncOperation(
        ownerId: ownerId,
        opId: opId,
        entityId: row.read<String>('entity_id'),
        payloadJson: row.read<String>('payload_json'),
        payloadHash: row.read<String>('payload_hash'),
        attempts: row.read<int>('attempts'),
      );
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
  Future<void> deferForAuthentication(
    String ownerId,
    String opId,
    DateTime now,
  ) async {
    _checkOwner(ownerId);
    final operation = await _findLeased(ownerId, opId);
    final nowMs = now.millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _db.customStatement(
        '''UPDATE sync_outbox SET state = 'waitingForAuth', lease_until_ms = NULL,
          last_error = 'unauthenticated', updated_at_ms = ?
          WHERE owner_id = ? AND op_id = ?''',
        [nowMs, ownerId, opId],
      );
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
    final operation = await _findLeased(ownerId, opId);
    final nextAttempts = operation.attempts + (retryable ? 1 : 0);
    final needsAttention = !retryable || nextAttempts >= 8;
    final state = needsAttention ? 'needsAttention' : 'queued';
    final nowMs = now.millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _db.customStatement(
        '''UPDATE sync_outbox SET state = ?, attempts = ?, next_retry_at_ms = ?,
          lease_until_ms = NULL, last_error = ?, updated_at_ms = ?
          WHERE owner_id = ? AND op_id = ?''',
        [
          state,
          nextAttempts,
          (retryAt ?? now).millisecondsSinceEpoch,
          code,
          nowMs,
          ownerId,
          opId,
        ],
      );
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
        WHERE owner_id = ? AND state = 'waitingForAuth' ''',
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
    final rows = await _db
        .customSelect(
          '''SELECT entity_id FROM sync_outbox
         WHERE owner_id = ? AND op_id = ? AND state = 'needsAttention' ''',
          variables: [Variable.withString(ownerId), Variable.withString(opId)],
        )
        .get();
    if (rows.isEmpty) {
      throw StateError('Outbox operation is not awaiting attention.');
    }
    final materialId = rows.single.read<String>('entity_id');
    final nowMs = now.millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _db.customStatement(
        '''UPDATE sync_outbox SET state = 'queued', attempts = 0,
          next_retry_at_ms = ?, lease_until_ms = NULL, last_error = NULL,
          updated_at_ms = ? WHERE owner_id = ? AND op_id = ?''',
        [nowMs, nowMs, ownerId, opId],
      );
      await _db.customStatement(
        '''UPDATE material_sync_state SET state = 'localReady', last_error = NULL
          WHERE owner_id = ? AND material_id = ?''',
        [ownerId, materialId],
      );
    });
  }

  Future<SyncOperation> _findLeased(String ownerId, String opId) async {
    final rows = await _db
        .customSelect(
          '''SELECT entity_id, payload_json, payload_hash, attempts FROM sync_outbox
        WHERE owner_id = ? AND op_id = ? AND state = 'leased' ''',
          variables: [Variable.withString(ownerId), Variable.withString(opId)],
        )
        .get();
    if (rows.isEmpty) throw StateError('Outbox operation is not leased.');
    final row = rows.single;
    return SyncOperation(
      ownerId: ownerId,
      opId: opId,
      entityId: row.read<String>('entity_id'),
      payloadJson: row.read<String>('payload_json'),
      payloadHash: row.read<String>('payload_hash'),
      attempts: row.read<int>('attempts'),
    );
  }

  void _checkOwner(String ownerId) {
    if (ownerId != _scope.ownerId) {
      throw ArgumentError.value(ownerId, 'ownerId', 'Outbox owner mismatch.');
    }
  }
}

String _hashPayload(String payloadJson) =>
    sha256.convert(utf8.encode(payloadJson)).toString();
