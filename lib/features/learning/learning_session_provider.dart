import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_engine.dart';
import '../../core/audio/audio_engine_provider.dart';
import '../subtitles/domain/subtitle_models.dart';
import '../subtitles/domain/subtitle_timeline.dart';
import 'domain/learning_session.dart';

final learningSessionFactoryProvider = Provider<LearningSessionFactory>(
  (ref) => LearningSessionFactory(ref.watch(audioEngineProvider)),
);

/// Creates one disposable learning session for a selected subtitle pair.
/// The caller owns each returned session and must call [LearningSession.dispose].
final class LearningSessionFactory {
  const LearningSessionFactory(this._audioEngine);

  final AudioEngine _audioEngine;

  LearningSession create({
    required SubtitleTrack englishTrack,
    SubtitleTrack? chineseTrack,
    SubtitleTimeline? timeline,
    SubtitleVisibility normalVisibility = SubtitleVisibility.bilingual,
  }) => LearningSession(
    audioEngine: _audioEngine,
    englishTrack: englishTrack,
    chineseTrack: chineseTrack,
    timeline: timeline,
    normalVisibility: normalVisibility,
  );
}
