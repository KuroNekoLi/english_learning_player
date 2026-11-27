import 'package:english_learning_player/core/sync/progress_policy.dart';
import 'package:english_learning_player/features/progress/data/progress_repository.dart';
import 'package:english_learning_player/features/progress/domain/progress_models.dart';

final class FakeProgressRepository implements ProgressRepository {
  String device = 'test-device';
  final List<ProgressCheckpoint> checkpoints = [];
  CanonicalProgress? savedCanonical;
  final Map<String, LocalPlaybackPosition> localPositions = {};

  @override
  Future<String> deviceId() async => device;

  @override
  Future<ProgressCheckpoint> recordCheckpoint({
    required ProgressStream stream,
    required int positionMs,
    required CheckpointState state,
    required int nowMs,
  }) async {
    final checkpoint = ProgressCheckpoint(
      stream: stream,
      positionMs: positionMs,
      state: state,
      sequence: checkpoints.length + 1,
      baseRevision: savedCanonical?.revision ?? 0,
    );
    checkpoints.add(checkpoint);
    localPositions[stream.materialId] = LocalPlaybackPosition(
      materialId: stream.materialId,
      positionMs: positionMs,
      lastPlayedAtMs: nowMs,
    );
    return checkpoint;
  }

  @override
  Future<CanonicalProgress?> canonical(String materialId) async =>
      savedCanonical;

  @override
  Future<int?> resumePosition(String materialId) async =>
      localPositions[materialId]?.positionMs ??
      (savedCanonical?.checkpoint.stream.materialId == materialId
          ? savedCanonical?.checkpoint.positionMs
          : null);

  @override
  Future<LocalPlaybackPosition?> mostRecentlyPlayed() async =>
      localPositions.values.isEmpty
      ? null
      : localPositions.values.reduce(
          (a, b) => a.lastPlayedAtMs >= b.lastPlayedAtMs ? a : b,
        );

  @override
  Future<void> mergeRemoteCanonical({
    required ProgressCheckpoint checkpoint,
    required int revision,
    required int nowMs,
  }) async {
    savedCanonical = CanonicalProgress(
      checkpoint: checkpoint,
      revision: revision,
    );
  }

  @override
  Future<List<ProgressCandidate>> unresolvedCandidates(
    String materialId,
  ) async => const [];

  @override
  Future<void> applyCommitResult({
    required String opId,
    required String payloadHash,
    required ProgressCommitResult result,
    required int nowMs,
  }) async {}

  @override
  Future<void> resolveCandidate({
    required String candidateId,
    required int observedCanonicalRevision,
    required bool useCandidatePosition,
    required ProgressStream resolutionStream,
    required int nowMs,
  }) async {}

  @override
  Future<PendingProgressOperation?> claimNext(DateTime now) async => null;

  @override
  Future<void> defer({
    required String opId,
    required String code,
    required bool retryable,
    required DateTime now,
    required DateTime retryAt,
  }) async {}

  @override
  Future<void> waitForAuthentication(String opId, DateTime now) async {}

  @override
  Future<void> resumeAuthenticated(DateTime now) async {}

  @override
  Future<void> retryNeedsAttention(String opId, DateTime now) async {}
}
