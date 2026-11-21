import 'dart:async';

import '../../../core/audio/audio_engine.dart';
import '../../../core/sync/progress_policy.dart';
import '../../learning/domain/learning_session.dart';
import '../../progress/services/playback_progress_recorder.dart';

/// Owns the subscriptions and progress recorder for an open material.
final class PlayerSessionResources {
  LearningSession? learning;
  PlaybackProgressRecorder? progress;
  StreamSubscription<PlaybackSnapshot>? playbackSubscription;
  StreamSubscription<LearningSessionState>? learningSubscription;

  Future<void> close(CheckpointState finalState) async {
    final recorder = progress;
    final snapshots = playbackSubscription;
    progress = null;
    playbackSubscription = null;
    final releaseLearning = closeLearning();
    await snapshots?.cancel();
    await Future.wait([
      releaseLearning,
      if (recorder != null) recorder.dispose(finalState: finalState),
    ]);
  }

  Future<void> closeLearning() async {
    final subscription = learningSubscription;
    final session = learning;
    learningSubscription = null;
    learning = null;
    await subscription?.cancel();
    await session?.dispose();
  }
}
