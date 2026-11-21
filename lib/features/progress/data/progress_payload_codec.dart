import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/sync/progress_policy.dart';

String encodeProgressCheckpoint(ProgressCheckpoint value) => jsonEncode({
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

ProgressCheckpoint decodeProgressCheckpoint(String payload) {
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

String hashProgressPayload(String payload) =>
    sha256.convert(utf8.encode(payload)).toString();
