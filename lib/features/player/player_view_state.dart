import '../../core/audio/audio_engine.dart';
import '../learning/domain/learning_session.dart';
import '../library/material_repository.dart';
import '../subtitles/domain/subtitle_models.dart';
import '../subtitles/domain/subtitle_timeline.dart';

enum PlayerLoadStatus { idle, loading, ready, error }

final class PlayerViewState {
  const PlayerViewState({
    this.status = PlayerLoadStatus.idle,
    this.material,
    this.playback,
    this.learning,
    this.timeline,
    this.normalVisibility = SubtitleVisibility.bilingual,
    this.englishTrack,
    this.subtitleTracks = const [],
    this.errorMessage,
    this.isCurrentCueBookmarked = false,
  });

  final PlayerLoadStatus status;
  final LearningMaterial? material;
  final PlaybackSnapshot? playback;
  final LearningSessionState? learning;
  final SubtitleTimeline? timeline;
  final SubtitleVisibility normalVisibility;
  final SubtitleTrack? englishTrack;
  final List<SubtitleTrack> subtitleTracks;
  final String? errorMessage;
  final bool isCurrentCueBookmarked;

  bool get isLoading => status == PlayerLoadStatus.loading;
  bool get isReady => status == PlayerLoadStatus.ready;

  PlayerViewState copyWith({
    PlayerLoadStatus? status,
    LearningMaterial? material,
    PlaybackSnapshot? playback,
    LearningSessionState? learning,
    SubtitleTimeline? timeline,
    SubtitleVisibility? normalVisibility,
    SubtitleTrack? englishTrack,
    List<SubtitleTrack>? subtitleTracks,
    String? errorMessage,
    bool clearLearning = false,
    bool clearEnglishTrack = false,
    bool clearError = false,
    bool? isCurrentCueBookmarked,
  }) => PlayerViewState(
    status: status ?? this.status,
    material: material ?? this.material,
    playback: playback ?? this.playback,
    learning: clearLearning ? null : learning ?? this.learning,
    timeline: clearEnglishTrack ? null : timeline ?? this.timeline,
    normalVisibility: normalVisibility ?? this.normalVisibility,
    englishTrack: clearEnglishTrack ? null : englishTrack ?? this.englishTrack,
    subtitleTracks: subtitleTracks ?? this.subtitleTracks,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    isCurrentCueBookmarked:
        isCurrentCueBookmarked ?? this.isCurrentCueBookmarked,
  );
}
