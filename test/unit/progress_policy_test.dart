import 'package:english_learning_player/core/sync/progress_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ProgressCheckpoint checkpoint({
    int sequence = 1,
    int baseRevision = 0,
    int positionMs = 300000,
    String deviceId = 'mac',
  }) => ProgressCheckpoint(
    stream: (
      ownerId: 'user',
      materialId: 'material',
      deviceId: deviceId,
      sessionId: 'session',
    ),
    positionMs: positionMs,
    state: CheckpointState.paused,
    sequence: sequence,
    baseRevision: baseRevision,
  );

  test('accepts the first checkpoint and a later intentional rewind', () {
    expect(
      decideProgress(
        checkpoint: checkpoint(),
        canonicalRevision: 0,
        highestSeenSequence: 0,
      ),
      ProgressDecision.accept,
    );
    expect(
      decideProgress(
        checkpoint: checkpoint(sequence: 2, baseRevision: 1, positionMs: 1000),
        canonicalRevision: 1,
        highestSeenSequence: 1,
      ),
      ProgressDecision.accept,
    );
  });

  test(
    'rejects repeated and out-of-order sequences before checking revision',
    () {
      for (final sequence in [1, 2]) {
        expect(
          decideProgress(
            checkpoint: checkpoint(sequence: sequence),
            canonicalRevision: 3,
            highestSeenSequence: 2,
          ),
          ProgressDecision.ignoreStale,
        );
      }
    },
  );

  test('preserves an offline checkpoint after another device advances', () {
    final offlineMac = checkpoint(baseRevision: 1);
    final onlinePhone = checkpoint(
      baseRevision: 1,
      deviceId: 'iphone',
      positionMs: 720000,
    );
    expect(
      decideProgress(
        checkpoint: onlinePhone,
        canonicalRevision: 1,
        highestSeenSequence: 0,
      ),
      ProgressDecision.accept,
    );
    expect(
      decideProgress(
        checkpoint: offlineMac,
        canonicalRevision: 2,
        highestSeenSequence: 0,
      ),
      ProgressDecision.keepConflict,
    );
  });

  test('rejects invalid checkpoint boundaries', () {
    expect(() => checkpoint(sequence: 0), throwsArgumentError);
    expect(() => checkpoint(baseRevision: -1), throwsArgumentError);
    expect(() => checkpoint(positionMs: -1), throwsArgumentError);
  });
}
