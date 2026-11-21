import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../../core/audio/audio_engine.dart';
import '../../../core/sync/progress_policy.dart';
import '../../learning/domain/learning_session.dart';
import '../../library/material_repository.dart';
import '../../progress/data/progress_repository.dart';
import '../../progress/services/playback_progress_recorder.dart';

/// Owns the subscriptions and progress recorder for an open material.
final class PlayerSessionResources {
  LearningSession? learning;
  PlaybackProgressRecorder? _progress;
  StreamSubscription<PlaybackSnapshot>? _playbackSubscription;
  StreamSubscription<LearningSessionState>? _learningSubscription;

  void attachLearning(
    LearningSession session,
    void Function(LearningSessionState) onState,
  ) {
    learning = session;
    _learningSubscription = session.states.listen(onState);
  }

  Future<void> startProgress({
    required AudioEngine audio,
    required ProgressRepository repository,
    required LearningMaterial material,
    required bool Function() isCurrent,
    required void Function(PlaybackSnapshot) onPlayback,
  }) async {
    final deviceId = await repository.deviceId();
    if (!isCurrent()) return;
    final recorder = _progress = PlaybackProgressRecorder(
      repository: repository,
      stream: (
        ownerId: material.ownerId,
        materialId: material.id,
        deviceId: deviceId,
        sessionId: const Uuid().v4(),
      ),
      clock: DateTime.now,
    );
    _playbackSubscription = audio.snapshots.listen((snapshot) {
      if (!isCurrent()) return;
      unawaited(
        recorder
            .onPlaybackSnapshot(
              positionMs: snapshot.positionMs,
              playing: snapshot.playing,
            )
            .catchError((Object _) {}),
      );
      onPlayback(snapshot);
    });
  }

  Future<void> savePosition(PlaybackSnapshot snapshot) async {
    await _progress?.onSeekCompleted(
      snapshot.positionMs,
      playing: snapshot.playing,
    );
  }

  Future<void> onLifecycleExit(PlaybackSnapshot snapshot) async {
    await _progress?.onLifecycleExit(positionMs: snapshot.positionMs);
  }

  Future<void> close(CheckpointState finalState) async {
    final recorder = _progress;
    final snapshots = _playbackSubscription;
    _progress = null;
    _playbackSubscription = null;
    final releaseLearning = closeLearning();
    await snapshots?.cancel();
    await Future.wait([
      releaseLearning,
      if (recorder != null) recorder.dispose(finalState: finalState),
    ]);
  }

  Future<void> closeLearning() async {
    final subscription = _learningSubscription;
    final session = learning;
    _learningSubscription = null;
    learning = null;
    await subscription?.cancel();
    await session?.dispose();
  }
}
