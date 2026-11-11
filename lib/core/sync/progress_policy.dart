typedef ProgressStream = ({
  String ownerId,
  String materialId,
  String deviceId,
  String sessionId,
});

enum CheckpointState { playing, paused, stopped, completed }

final class ProgressCheckpoint {
  ProgressCheckpoint({
    required this.stream,
    required this.positionMs,
    required this.state,
    required this.sequence,
    required this.baseRevision,
  }) {
    if (positionMs < 0 || sequence < 1 || baseRevision < 0) {
      throw ArgumentError('Invalid position, sequence, or base revision.');
    }
  }

  final ProgressStream stream;
  final int positionMs;
  final CheckpointState state;
  final int sequence;
  final int baseRevision;
}

enum ProgressDecision { accept, ignoreStale, keepConflict }

/// Evaluate inside the commit transaction, after checking the opId receipt.
/// highestSeenSequence is scoped to the checkpoint stream, including conflicts.
ProgressDecision decideProgress({
  required ProgressCheckpoint checkpoint,
  required int canonicalRevision,
  required int highestSeenSequence,
}) {
  if (checkpoint.sequence <= highestSeenSequence) {
    return ProgressDecision.ignoreStale;
  }
  if (checkpoint.baseRevision != canonicalRevision) {
    return ProgressDecision.keepConflict;
  }
  return ProgressDecision.accept;
}
