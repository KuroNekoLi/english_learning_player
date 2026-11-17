import 'package:english_learning_player/core/sync/progress_policy.dart';
import 'package:english_learning_player/features/progress/domain/progress_models.dart';
import 'package:english_learning_player/features/progress/services/progress_sync_coordinator.dart';

/// Transaction-shaped fake for validating the ADR-012 adapter contract.
final class FakeProgressLedger implements ProgressSyncTransport {
  final Map<String, ProgressCommitResult> _receipts = {};
  final Map<String, String> _receiptHashes = {};
  final Map<String, CanonicalProgress> canonicals = {};
  final Map<String, int> highWater = {};
  final Map<String, ProgressCandidate> candidates = {};
  int writes = 0;

  @override
  Future<ProgressCommitResult> commit({
    required String uid,
    required String opId,
    required String payloadHash,
    required ProgressCheckpoint checkpoint,
    ProgressResolution? resolution,
  }) async {
    if (uid != checkpoint.stream.ownerId) {
      throw StateError('UID scope mismatch.');
    }
    final existing = _receipts[opId];
    if (existing != null) {
      if (_receiptHashes[opId] != payloadHash) {
        throw StateError('opId payload changed.');
      }
      return existing;
    }
    writes++;
    final key = progressStreamKey(checkpoint.stream);
    final canonicalKey = '$uid\u0000${checkpoint.stream.materialId}';
    final canonical = canonicals[canonicalKey];
    final revision = canonical?.revision ?? 0;
    if (resolution case final request?) {
      final matchingCandidate = candidates.values.any(
        (candidate) => candidate.id == request.candidateId,
      );
      if (revision != request.observedCanonicalRevision || !matchingCandidate) {
        final result = ProgressCommitResult(
          status: ProgressCommitStatus.conflict,
          canonicalRevision: revision,
          candidateId: request.candidateId,
          canonicalCheckpoint: canonical?.checkpoint,
        );
        _receipts[opId] = result;
        _receiptHashes[opId] = payloadHash;
        return result;
      }
      final nextRevision = revision + 1;
      canonicals[canonicalKey] = CanonicalProgress(
        checkpoint: checkpoint,
        revision: nextRevision,
      );
      candidates.removeWhere(
        (_, candidate) => candidate.id == request.candidateId,
      );
      highWater[key] = checkpoint.sequence;
      final result = ProgressCommitResult(
        status: ProgressCommitStatus.accepted,
        canonicalRevision: nextRevision,
        canonicalCheckpoint: checkpoint,
      );
      _receipts[opId] = result;
      _receiptHashes[opId] = payloadHash;
      return result;
    }
    final decision = decideProgress(
      checkpoint: checkpoint,
      canonicalRevision: revision,
      highestSeenSequence: highWater[key] ?? 0,
    );
    late final ProgressCommitResult result;
    switch (decision) {
      case ProgressDecision.ignoreStale:
        result = ProgressCommitResult(
          status: ProgressCommitStatus.ignoredStale,
          canonicalRevision: revision,
          canonicalCheckpoint: canonical?.checkpoint,
        );
      case ProgressDecision.accept:
        final nextRevision = revision + 1;
        canonicals[canonicalKey] = CanonicalProgress(
          checkpoint: checkpoint,
          revision: nextRevision,
        );
        result = ProgressCommitResult(
          status: ProgressCommitStatus.accepted,
          canonicalRevision: nextRevision,
          canonicalCheckpoint: checkpoint,
        );
      case ProgressDecision.keepConflict:
        final candidateId = 'candidate:$key';
        candidates[key] = ProgressCandidate(
          id: candidateId,
          checkpoint: checkpoint,
          createdAtMs: 0,
        );
        result = ProgressCommitResult(
          status: ProgressCommitStatus.conflict,
          canonicalRevision: revision,
          canonicalCheckpoint: canonical?.checkpoint,
          candidateId: candidateId,
        );
    }
    if (decision != ProgressDecision.ignoreStale) {
      highWater[key] = checkpoint.sequence;
    }
    _receipts[opId] = result;
    _receiptHashes[opId] = payloadHash;
    return result;
  }
}
