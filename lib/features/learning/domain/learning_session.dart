import 'dart:async';

import '../../../core/audio/audio_engine.dart';
import '../../subtitles/domain/subtitle_aligner.dart';
import '../../subtitles/domain/subtitle_models.dart';
import '../../subtitles/domain/subtitle_synchronizer.dart';

enum LearningMode { normal, intensive }

enum IntensivePhase { blindListening, englishShown, bilingualShown }

enum SubtitleVisibility { bilingual, englishOnly, chineseOnly, hidden }

final class LearningSessionState {
  LearningSessionState({
    required this.mode,
    required this.phase,
    required this.subtitleVisibility,
    required this.currentCue,
    required List<SubtitleCue> translationCues,
  }) : translationCues = List.unmodifiable(translationCues);

  final LearningMode mode;
  final IntensivePhase phase;
  final SubtitleVisibility subtitleVisibility;
  final SubtitleCue? currentCue;
  final List<SubtitleCue> translationCues;

  bool get hasTranslation => translationCues.isNotEmpty;

  /// Presentation layer can render this when bilingual reveal has no match.
  String? get translationPlaceholder =>
      currentCue == null || hasTranslation ? null : '未提供翻譯';
}

/// Coordinates cue-aware study actions while keeping playback behind AudioEngine.
final class LearningSession {
  LearningSession({
    required AudioEngine audioEngine,
    required SubtitleTrack englishTrack,
    SubtitleTrack? chineseTrack,
    this.normalVisibility = SubtitleVisibility.bilingual,
  }) : _audioEngine = audioEngine,
       _englishTrack = englishTrack,
       _chineseTrack = chineseTrack,
       _englishSynchronizer = SubtitleSynchronizer(
         cues: englishTrack.cues,
         offsetMs: englishTrack.offsetMs,
       ) {
    if (chineseTrack != null &&
        (chineseTrack.materialId != englishTrack.materialId ||
            chineseTrack.ownerId != englishTrack.ownerId)) {
      throw ArgumentError('Subtitle tracks must belong to the same material.');
    }
    if (!englishTrack.languageTag.toLowerCase().startsWith('en') ||
        chineseTrack != null &&
            !chineseTrack.languageTag.toLowerCase().startsWith('zh')) {
      throw ArgumentError(
        'Expected an English track and an optional Chinese track.',
      );
    }
    _cuesById = {for (final cue in englishTrack.cues) cue.id: cue};
    _sortedCues = englishTrack.cues.toList()
      ..sort((a, b) {
        final byTime = _audioStart(a).compareTo(_audioStart(b));
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    _translationsByEnglishCue = _buildTranslations();
    _state = _createState(_audioEngine.snapshot);
    _audioSubscription = _audioEngine.snapshots.listen(_onPlaybackSnapshot);
  }

  final AudioEngine _audioEngine;
  final SubtitleTrack _englishTrack;
  final SubtitleTrack? _chineseTrack;
  final SubtitleSynchronizer _englishSynchronizer;
  final StreamController<LearningSessionState> _events =
      StreamController<LearningSessionState>.broadcast(sync: true);

  late final Map<String, SubtitleCue> _cuesById;
  late final List<SubtitleCue> _sortedCues;
  late final Map<String, List<SubtitleCue>> _translationsByEnglishCue;
  late final StreamSubscription<PlaybackSnapshot> _audioSubscription;
  late LearningSessionState _state;
  LearningMode _mode = LearningMode.normal;
  IntensivePhase _phase = IntensivePhase.blindListening;
  SubtitleCue? _currentCue;
  bool _sessionLoopEnabled = false;
  bool _disposed = false;

  SubtitleVisibility normalVisibility;

  LearningSessionState get state => _state;

  Stream<LearningSessionState> get states => Stream.multi((controller) {
    controller.add(_state);
    final subscription = _events.stream.listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    controller.onCancel = subscription.cancel;
  });

  void enterIntensive() {
    _ensureUsable();
    _mode = LearningMode.intensive;
    _phase = IntensivePhase.blindListening;
    _publish();
  }

  void setNormalVisibility(SubtitleVisibility visibility) {
    _ensureUsable();
    normalVisibility = visibility;
    if (_mode == LearningMode.normal) _publish();
  }

  Future<void> exitIntensive() async {
    _ensureUsable();
    if (_sessionLoopEnabled) {
      await _audioEngine.setSentenceLoop(null);
      _sessionLoopEnabled = false;
    }
    _mode = LearningMode.normal;
    _publish();
  }

  void revealEnglish() {
    _ensureUsable();
    if (_mode != LearningMode.intensive ||
        _phase != IntensivePhase.blindListening) {
      return;
    }
    _phase = IntensivePhase.englishShown;
    _publish();
  }

  void revealChinese() {
    _ensureUsable();
    if (_mode != LearningMode.intensive ||
        _phase != IntensivePhase.englishShown) {
      return;
    }
    // Reveal remains available without a translation so the view can show its
    // explicit "未提供翻譯" state instead of trapping the learner.
    _phase = IntensivePhase.bilingualShown;
    _publish();
  }

  void resetCue() {
    _ensureUsable();
    if (_mode != LearningMode.intensive) return;
    _phase = IntensivePhase.blindListening;
    _publish();
  }

  /// Replays the active cue from its offset-adjusted start without changing
  /// the current reveal phase.
  Future<bool> replay() async {
    _ensureUsable();
    if (!_isActiveMaterial) return false;
    final cue = _currentCue;
    if (cue == null) return false;
    final range = _audioRangeFor(cue);
    if (range == null) return false;
    if (_audioEngine.snapshot.currentLoop != null &&
        _audioEngine.snapshot.currentLoop != range) {
      await _audioEngine.setSentenceLoop(null);
      _sessionLoopEnabled = false;
    }
    await _audioEngine.seekTo(Duration(milliseconds: range.startMs));
    await _audioEngine.play();
    _refreshFromPlayback();
    return true;
  }

  /// Enables or clears the active cue loop. Enabling starts replay at cue start.
  Future<bool> setCueLoopEnabled(bool enabled) async {
    _ensureUsable();
    if (!_isActiveMaterial) return false;
    final cue = _currentCue;
    if (cue == null) return false;
    if (!enabled) {
      await _audioEngine.setSentenceLoop(null);
      _sessionLoopEnabled = false;
      _refreshFromPlayback();
      return true;
    }

    final range = _audioRangeFor(cue);
    if (range == null) return false;
    await _audioEngine.setSentenceLoop(range);
    _sessionLoopEnabled = true;
    await _audioEngine.seekTo(Duration(milliseconds: range.startMs));
    await _audioEngine.play();
    _refreshFromPlayback();
    return true;
  }

  /// Advances in audio-time order, clears the old loop and masks the new cue.
  Future<bool> nextCue() async {
    _ensureUsable();
    if (!_isActiveMaterial) return false;
    if (_sortedCues.isEmpty) return false;

    final positionMs = _audioEngine.snapshot.positionMs;
    final current = _currentCue;
    final currentIndex = current == null
        ? -1
        : _sortedCues.indexWhere((cue) => cue.id == current.id);
    final next = currentIndex >= 0
        ? (currentIndex + 1 < _sortedCues.length
              ? _sortedCues[currentIndex + 1]
              : null)
        : _sortedCues.cast<SubtitleCue?>().firstWhere(
            (cue) => _audioStart(cue!) >= positionMs,
            orElse: () => null,
          );
    if (next == null) return false;

    return playCue(next.id);
  }

  /// Plays a selected English cue. Selecting another cue returns intensive
  /// mode to blind listening; selecting the active cue preserves its reveal.
  Future<bool> playCue(String cueId) async {
    _ensureUsable();
    if (!_isActiveMaterial) return false;
    final cue = _cuesById[cueId];
    if (cue == null) return false;
    final range = _audioRangeFor(cue);
    if (range == null) return false;

    final isSameCue = _currentCue?.id == cue.id;
    if (_audioEngine.snapshot.currentLoop != null &&
        _audioEngine.snapshot.currentLoop != range) {
      await _audioEngine.setSentenceLoop(null);
    }
    _sessionLoopEnabled =
        _audioEngine.snapshot.currentLoop?.startMs == range.startMs &&
        _audioEngine.snapshot.currentLoop?.endMs == range.endMs;
    await _audioEngine.seekTo(Duration(milliseconds: range.startMs));
    await _audioEngine.play();
    if (_mode == LearningMode.intensive && !isSameCue) {
      _phase = IntensivePhase.blindListening;
    }
    _refreshFromPlayback();
    return true;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _audioSubscription.cancel();
    await _events.close();
  }

  Map<String, List<SubtitleCue>> _buildTranslations() {
    final chineseTrack = _chineseTrack;
    if (chineseTrack == null) return const {};
    final matches = const SubtitleAligner().align(
      sourceCues: _englishTrack.cues,
      targetCues: chineseTrack.cues,
      sourceOffsetMs: _englishTrack.offsetMs,
      targetOffsetMs: chineseTrack.offsetMs,
    );
    final chineseById = {for (final cue in chineseTrack.cues) cue.id: cue};
    return {
      for (final match in matches)
        match.sourceCueId: List.unmodifiable(
          match.targetCueIds
              .map((id) => chineseById[id])
              .whereType<SubtitleCue>(),
        ),
    };
  }

  LearningSessionState _createState(PlaybackSnapshot snapshot) {
    _currentCue = snapshot.materialId != _englishTrack.materialId
        ? null
        : _englishSynchronizer.at(
            snapshot.positionMs,
            previousCueId: _currentCue?.id,
          );
    return LearningSessionState(
      mode: _mode,
      phase: _phase,
      subtitleVisibility: _effectiveVisibility(),
      currentCue: _currentCue,
      translationCues: _currentCue == null
          ? const []
          : _translationsByEnglishCue[_currentCue!.id] ?? const [],
    );
  }

  SubtitleVisibility _effectiveVisibility() {
    if (_mode == LearningMode.normal) return normalVisibility;
    return switch (_phase) {
      IntensivePhase.blindListening => SubtitleVisibility.hidden,
      IntensivePhase.englishShown => SubtitleVisibility.englishOnly,
      IntensivePhase.bilingualShown => SubtitleVisibility.bilingual,
    };
  }

  int _audioStart(SubtitleCue cue) => cue.startMs + _englishTrack.offsetMs;

  bool get _isActiveMaterial =>
      _audioEngine.snapshot.materialId == _englishTrack.materialId;

  TimeRange? _audioRangeFor(SubtitleCue cue) {
    final startMs = _audioStart(cue);
    final endMs = cue.endMs + _englishTrack.offsetMs;
    final durationMs = _audioEngine.snapshot.durationMs;
    final boundedStart = startMs < 0 ? 0 : startMs;
    final boundedEnd = durationMs != null && endMs > durationMs
        ? durationMs
        : endMs;
    if (boundedEnd <= boundedStart) return null;
    return TimeRange(boundedStart, boundedEnd);
  }

  void _onPlaybackSnapshot(PlaybackSnapshot snapshot) {
    if (_disposed) return;
    if (snapshot.materialId != _englishTrack.materialId) {
      _sessionLoopEnabled = false;
    }
    _state = _createState(snapshot);
    _events.add(_state);
  }

  void _refreshFromPlayback() {
    _state = _createState(_audioEngine.snapshot);
    _events.add(_state);
  }

  void _publish() {
    if (_disposed) return;
    _state = _createState(_audioEngine.snapshot);
    _events.add(_state);
  }

  void _ensureUsable() {
    if (_disposed) throw StateError('LearningSession has been disposed.');
  }
}
