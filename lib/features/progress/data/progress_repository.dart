import '../../../core/sync/progress_policy.dart';
import '../domain/progress_models.dart';

final class PendingProgressOperation {
  const PendingProgressOperation({
    required this.opId,
    required this.checkpoint,
    required this.payloadHash,
    required this.attempts,
    this.resolution,
  });

  final String opId;
  final ProgressCheckpoint checkpoint;
  final String payloadHash;
  final int attempts;
  final ProgressResolution? resolution;
}

abstract interface class ProgressRepository {
  Future<String> deviceId();

  Future<ProgressCheckpoint> recordCheckpoint({
    required ProgressStream stream,
    required int positionMs,
    required CheckpointState state,
    required int nowMs,
  });

  Future<CanonicalProgress?> canonical(String materialId);
  Future<int?> resumePosition(String materialId);
  Future<LocalPlaybackPosition?> mostRecentlyPlayed();
  Future<void> mergeRemoteCanonical({
    required ProgressCheckpoint checkpoint,
    required int revision,
    required int nowMs,
  });
  Future<List<ProgressCandidate>> unresolvedCandidates(String materialId);
  Future<void> applyCommitResult({
    required String opId,
    required String payloadHash,
    required ProgressCommitResult result,
    required int nowMs,
  });

  Future<void> resolveCandidate({
    required String candidateId,
    required int observedCanonicalRevision,
    required bool useCandidatePosition,
    required ProgressStream resolutionStream,
    required int nowMs,
  });

  Future<PendingProgressOperation?> claimNext(DateTime now);
  Future<void> defer({
    required String opId,
    required String code,
    required bool retryable,
    required DateTime now,
    required DateTime retryAt,
  });

  Future<void> waitForAuthentication(String opId, DateTime now);
  Future<void> resumeAuthenticated(DateTime now);
  Future<void> retryNeedsAttention(String opId, DateTime now);
}
