import '../../../core/sync/progress_policy.dart';

final class CanonicalProgress {
  const CanonicalProgress({required this.checkpoint, required this.revision});

  final ProgressCheckpoint checkpoint;
  final int revision;
}

final class ProgressCandidate {
  const ProgressCandidate({
    required this.id,
    required this.checkpoint,
    required this.createdAtMs,
  });

  final String id;
  final ProgressCheckpoint checkpoint;
  final int createdAtMs;
}

final class ProgressResolution {
  const ProgressResolution({
    required this.candidateId,
    required this.observedCanonicalRevision,
    required this.useCandidatePosition,
  });

  final String candidateId;
  final int observedCanonicalRevision;
  final bool useCandidatePosition;
}

enum ProgressCommitStatus { accepted, ignoredStale, conflict }

final class ProgressCommitResult {
  const ProgressCommitResult({
    required this.status,
    required this.canonicalRevision,
    this.candidateId,
    this.canonicalCheckpoint,
  });

  final ProgressCommitStatus status;
  final int canonicalRevision;
  final String? candidateId;
  final ProgressCheckpoint? canonicalCheckpoint;
}

String progressStreamKey(ProgressStream stream) =>
    '${stream.ownerId}\u0000${stream.materialId}\u0000${stream.deviceId}\u0000${stream.sessionId}';
