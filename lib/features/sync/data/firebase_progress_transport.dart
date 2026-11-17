import 'dart:io';

import '../../../core/sync/progress_policy.dart';
import '../../../core/sync/sync_contracts.dart';
import '../../progress/domain/progress_models.dart';
import '../../progress/services/progress_sync_coordinator.dart';
import 'firebase_account_session.dart';
import 'firebase_endpoint.dart';
import 'firebase_material_transport.dart';

final class FirebaseProgressTransport implements ProgressSyncTransport {
  const FirebaseProgressTransport(
    this.endpoint,
    this.session,
    this.http,
    this.materials,
  );

  final FirebaseEndpoint endpoint;
  final FirebaseAccountSession session;
  final FirebaseHttp http;
  final FirebaseMaterialTransport materials;

  @override
  Future<ProgressCommitResult> commit({
    required String uid,
    required String opId,
    required String payloadHash,
    required ProgressCheckpoint checkpoint,
    ProgressResolution? resolution,
  }) async {
    final response = await http.send(
      'POST',
      endpoint.progressFunction,
      authorization: 'Bearer ${await session.tokenFor(uid)}',
      contentType: ContentType.json,
      bytes: FirebaseHttp.encode({
        'data': {
          'opId': opId,
          'payloadHash': payloadHash,
          'payload': {
            'schemaVersion': 1,
            'ownerId': checkpoint.stream.ownerId,
            'materialId': checkpoint.stream.materialId,
            'deviceId': checkpoint.stream.deviceId,
            'sessionId': checkpoint.stream.sessionId,
            'positionMs': checkpoint.positionMs,
            'state': checkpoint.state.name,
            'sequence': checkpoint.sequence,
            'baseRevision': checkpoint.baseRevision,
            if (resolution != null) ...{
              'resolveCandidateId': resolution.candidateId,
              'observedCanonicalRevision': resolution.observedCanonicalRevision,
              'useCandidatePosition': resolution.useCandidatePosition,
            },
          },
        },
      }),
    );
    await http.requireSuccess(response);
    final json = await http.json(response);
    final result = json['result'];
    if (result is! Map<String, dynamic>) _invalid();
    final revision = result['canonicalRevision'];
    final status = result['status'];
    final candidate = result['candidateId'];
    if (revision is! int ||
        status is! String ||
        (candidate != null && candidate is! String)) {
      _invalid();
    }
    try {
      final canonical = result['canonicalCheckpoint'];
      return ProgressCommitResult(
        status: ProgressCommitStatus.values.byName(status),
        canonicalRevision: revision,
        candidateId: candidate as String?,
        canonicalCheckpoint: canonical == null ? null : _checkpoint(canonical),
      );
    } on ArgumentError {
      _invalid();
    }
  }

  Future<CanonicalProgress?> canonical(String uid, String materialId) async {
    final record = await materials.readDocument(uid, [
      'users',
      uid,
      'progress',
      materialId,
    ]);
    if (record == null) return null;
    final revision = record['revision'];
    if (revision is! int || revision < 1) _invalid();
    final checkpoint = _checkpoint(record['checkpoint']);
    if (checkpoint.stream.ownerId != uid ||
        checkpoint.stream.materialId != materialId) {
      _invalid();
    }
    return CanonicalProgress(checkpoint: checkpoint, revision: revision);
  }

  static ProgressCheckpoint _checkpoint(Object? data) {
    if (data is! Map<String, dynamic>) _invalid();
    try {
      return ProgressCheckpoint(
        stream: (
          ownerId: data['ownerId'] as String,
          materialId: data['materialId'] as String,
          deviceId: data['deviceId'] as String,
          sessionId: data['sessionId'] as String,
        ),
        positionMs: data['positionMs'] as int,
        state: CheckpointState.values.byName(data['state'] as String),
        sequence: data['sequence'] as int,
        baseRevision: data['baseRevision'] as int,
      );
    } on TypeError {
      _invalid();
    } on ArgumentError {
      _invalid();
    }
  }

  static Never _invalid() => throw const SyncFailure(
    SyncFailureKind.invalidData,
    'invalid_progress_response',
  );
}
