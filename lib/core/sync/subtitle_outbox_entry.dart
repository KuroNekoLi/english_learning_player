import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

/// Records that the selected tracks of an authored material need publishing.
/// The worker reads the current tracks when it takes the lease.
abstract final class SubtitleOutboxEntry {
  static String payload(String materialId) =>
      jsonEncode({'schemaVersion': 1, 'materialId': materialId});

  /// Must run in the transaction that saves the subtitle or upgrades its DB.
  static Future<void> enqueue(
    DatabaseConnectionUser database, {
    required String ownerId,
    required String materialId,
    required int nowMs,
  }) async {
    final args = [ownerId, materialId];
    // Only local origins have an audio publication operation. Downloaded
    // tracks stay in the local cache, including after a manual override.
    final authored = await database.customSelect(
      '''SELECT 1 FROM sync_outbox WHERE owner_id = ? AND entity_type = 'material'
         AND entity_id = ? AND operation = 'uploadMaterial' LIMIT 1''',
      variables: args.map(Variable.withString).toList(),
    ).get();
    if (authored.isEmpty) return;

    final pending = await database.customUpdate(
      '''UPDATE sync_outbox SET state = 'queued', attempts = 0, next_retry_at_ms = ?,
           last_error = NULL, updated_at_ms = ?
         WHERE owner_id = ? AND entity_type = 'subtitle' AND entity_id = ?
           AND state IN ('queued', 'waitingForAuth', 'needsAttention')''',
      variables: [
        Variable.withInt(nowMs),
        Variable.withInt(nowMs),
        Variable.withString(ownerId),
        Variable.withString(materialId),
      ],
    );
    if (pending != 0) return;

    final json = payload(materialId);
    await database.customStatement(
      '''INSERT INTO sync_outbox
         (owner_id, op_id, entity_type, entity_id, operation, payload_version,
          payload_json, payload_hash, attempts, next_retry_at_ms, state,
          created_at_ms, updated_at_ms)
         VALUES (?, ?, 'subtitle', ?, 'publishSubtitles', 1, ?, ?, 0, ?, 'queued', ?, ?)''',
      [
        ownerId,
        const Uuid().v4(),
        materialId,
        json,
        sha256.convert(utf8.encode(json)).toString(),
        nowMs,
        nowMs,
        nowMs,
      ],
    );
  }
}
