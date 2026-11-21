import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/audio_engine.dart';
import '../../core/audio/audio_engine_provider.dart';
import '../../core/audio/audio_media_session_provider.dart';
import '../../core/sync/progress_policy.dart';
import '../../features/learning/domain/learning_session.dart';
import '../../features/learning/learning_session_provider.dart';
import '../../features/bookmarks/bookmark_dependencies.dart';
import '../../features/bookmarks/bookmark_list_view_model.dart';
import '../library/domain/audio_import_source.dart';
import '../library/material_repository.dart';
import '../progress/progress_dependencies.dart';
import '../subtitles/domain/subtitle_models.dart';
import '../subtitles/services/subtitle_import_service.dart';
import 'player_dependencies.dart';
import 'services/material_playback_loader.dart';
import 'services/player_bookmarks.dart';
import 'services/player_playback_startup.dart';
import 'services/player_session_resources.dart';

import 'player_view_state.dart';

export 'player_view_state.dart';

final class PlayerViewModel extends Notifier<PlayerViewState> {
  late AudioEngine _audioEngine;
  late LearningSessionFactory _sessionFactory;
  final _resources = PlayerSessionResources();
  LearningSession? get _session => _resources.learning;
  MaterialPlaybackBundle? _bundle;
  int _openGeneration = 0;
  bool _disposed = false;
  bool _closingAccount = false;

  PlayerBookmarkIndex _bookmarks = const {};
  bool _togglingBookmark = false;

  @override
  PlayerViewState build() {
    _audioEngine = ref.watch(audioEngineProvider);
    _sessionFactory = ref.watch(learningSessionFactoryProvider);
    ref.onDispose(() => unawaited(_disposeResources()));
    return const PlayerViewState();
  }

  Future<void> open(LearningMaterial material, {String? initialCueId}) async {
    _ensureUsable();
    if (_closingAccount) return;
    final generation = ++_openGeneration;
    state = PlayerViewState(
      status: PlayerLoadStatus.loading,
      material: material,
    );
    await _releaseSession(finalProgressState: CheckpointState.stopped);
    try {
      if (!_isCurrent(generation)) return;
      final loader = await ref.read(materialPlaybackLoaderProvider.future);
      final bundle = await loader.load(material);
      if (!_isCurrent(generation)) return;
      _bundle = bundle;
      final progressRepository = await PlayerPlaybackStartup(_audioEngine)
          .prepare(
            bundle,
            mediaSession: () => ref.read(audioMediaSessionProvider.future),
            progressRepository: () =>
                ref.read(progressRepositoryProvider.future),
            restorePosition: initialCueId == null,
            isCurrent: () => _isCurrent(generation),
          );
      if (progressRepository == null || !_isCurrent(generation)) return;
      await _loadBookmarkAnchors(
        material.id,
        bundle.subtitleTracks,
        generation,
      );
      if (!_isCurrent(generation)) return;
      await _createSession(generation);
      if (!_isCurrent(generation)) return;
      await _resources.startProgress(
        audio: _audioEngine,
        repository: progressRepository,
        material: material,
        isCurrent: () => _isCurrent(generation),
        onPlayback: (snapshot) =>
            state = state.copyWith(playback: snapshot, clearError: true),
      );
      if (!_isCurrent(generation)) return;
      state = PlayerViewState(
        status: PlayerLoadStatus.ready,
        material: material,
        playback: _audioEngine.snapshot,
        learning: _session?.state,
        englishTrack: bundle.englishTrack,
        timeline: bundle.timeline,
        subtitleTracks: bundle.subtitleTracks,
        isCurrentCueBookmarked:
            initialCueId != null ||
            _isBookmarked(_session?.state.currentCue, bundle.englishTrack),
      );
      if (initialCueId != null) {
        await _session?.playCue(initialCueId);
        if (!_isCurrent(generation)) return;
        state = state.copyWith(
          playback: _audioEngine.snapshot,
          learning: _session?.state,
          isCurrentCueBookmarked: _isBookmarked(
            _session?.state.currentCue,
            bundle.englishTrack,
          ),
        );
      }
    } catch (error) {
      if (!_isCurrent(generation)) return;
      final message = error is MaterialPlaybackException
          ? error.message
          : '無法載入教材，請檢查本機音訊檔案。';
      state = PlayerViewState(
        status: PlayerLoadStatus.error,
        material: material,
        errorMessage: message,
      );
    }
  }

  Future<void> togglePlayback() async {
    final playback = state.playback;
    if (!state.isReady || playback == null) return;
    if (playback.playing) {
      await _runAudioCommand(_audioEngine.pause, persistProgress: true);
    } else {
      await _runAudioCommand(_audioEngine.play);
    }
  }

  Future<void> seekTo(int positionMs) async {
    _session?.cancelOneShotPlayback();
    await _runAudioCommand(
      () => _audioEngine.seekTo(Duration(milliseconds: positionMs)),
      persistProgress: true,
    );
  }

  Future<void> onLifecycleExit() =>
      _resources.onLifecycleExit(_audioEngine.snapshot);

  Future<void> setSpeed(double speed) =>
      _runAudioCommand(() => _audioEngine.setSpeed(speed));

  Future<void> replay() async {
    final session = _session;
    if (session != null) {
      await _runAudioCommand(session.replay, persistProgress: true);
    }
  }

  Future<void> playCue(String cueId) async {
    final session = _session;
    if (session != null) {
      await _runAudioCommand(
        () => session.playCue(cueId),
        persistProgress: true,
      );
    }
  }

  Future<void> nextCue() async {
    final session = _session;
    if (session != null) {
      await _runAudioCommand(session.nextCue, persistProgress: true);
    }
  }

  Future<void> previousCue() async {
    final session = _session;
    if (session != null) {
      await _runAudioCommand(session.previousCue, persistProgress: true);
    }
  }

  Future<void> toggleCueLoop() async {
    final session = _session;
    final loopIsActive = state.playback?.currentLoop != null;
    if (session != null) {
      await _runAudioCommand(() => session.setCueLoopEnabled(!loopIsActive));
    }
  }

  void toggleIntensiveMode() {
    final session = _session;
    if (session == null) return;
    if (session.state.mode == LearningMode.intensive) {
      unawaited(_runAudioCommand(session.exitIntensive));
    } else {
      session.enterIntensive();
      _syncLearningState(session.state);
    }
  }

  void revealNext() {
    final session = _session;
    if (session == null) return;
    switch (session.state.phase) {
      case IntensivePhase.blindListening:
        session.revealEnglish();
      case IntensivePhase.englishShown:
        session.revealChinese();
      case IntensivePhase.bilingualShown:
        session.resetCue();
    }
    _syncLearningState(session.state);
  }

  void setNormalVisibility(SubtitleVisibility visibility) {
    state = state.copyWith(normalVisibility: visibility);
    _session?.setNormalVisibility(visibility);
    if (_session != null) _syncLearningState(_session!.state);
  }

  Future<void> selectSubtitleTrack(SubtitleTrack track) async {
    final material = state.material;
    if (material == null || track.materialId != material.id) return;
    await _saveSubtitleTrack(track, manual: true);
  }

  Future<AudioImportSource?> pickSubtitle() async {
    try {
      return await ref.read(subtitleFilePickerProvider).pickSubtitle();
    } catch (_) {
      if (ref.mounted) state = state.copyWith(errorMessage: '無法開啟字幕檔案。');
      return null;
    }
  }

  Future<bool> importSubtitle({required AudioImportSource source}) async {
    final material = state.material;
    final generation = _openGeneration;
    if (material == null || !state.isReady) return false;
    try {
      final service = await ref.read(playerSubtitlesProvider.future);
      if (!_isCurrent(generation)) return false;
      final tracks = await service.import(material, source);
      return await _applySubtitleTracks(material, tracks, generation);
    } on SubtitleLanguageDetectionException {
      if (_isCurrent(generation)) {
        state = state.copyWith(errorMessage: '無法判斷字幕語言或雙語格式，請檢查 SRT 內容與檔名。');
      }
      return false;
    } catch (_) {
      if (_isCurrent(generation)) {
        state = state.copyWith(errorMessage: '字幕匯入失敗，請確認 SRT 格式。');
      }
      return false;
    }
  }

  Future<void> setSubtitleOffset(SubtitleTrack track, int offsetMs) async {
    if (offsetMs == track.offsetMs) return;
    await _saveSubtitleTrack(
      track.copyWith(offsetMs: offsetMs),
      manual: track.selectionMode == SubtitleSelectionMode.manual,
    );
  }

  Future<void> toggleBookmark() async {
    final material = state.material;
    final track = state.englishTrack;
    final cue = state.learning?.currentCue;
    if (_closingAccount ||
        _togglingBookmark ||
        material == null ||
        track == null ||
        cue == null) {
      return;
    }
    final generation = _openGeneration;
    final key = PlayerBookmarks.key(track, cue);
    _togglingBookmark = true;
    try {
      final service = PlayerBookmarks(
        await ref.read(bookmarkRepositoryProvider.future),
      );
      if (!_isCurrent(generation)) return;
      final saved = await service.toggle(material, track, cue, _bookmarks[key]);
      if (!_isCurrent(generation)) return;
      _bookmarks = Map.unmodifiable({
        for (final entry in _bookmarks.entries)
          if (entry.key != key) entry.key: entry.value,
        if (saved != null) key: saved,
      });
      ref.invalidate(bookmarkListViewModelProvider);
      state = state.copyWith(
        isCurrentCueBookmarked: _isBookmarked(
          state.learning?.currentCue,
          state.englishTrack,
        ),
        clearError: true,
      );
    } catch (_) {
      if (_isCurrent(generation)) {
        state = state.copyWith(errorMessage: '收藏儲存失敗，請重試。');
      }
    } finally {
      _togglingBookmark = false;
    }
  }

  Future<void> _saveSubtitleTrack(
    SubtitleTrack track, {
    required bool manual,
  }) async {
    final generation = _openGeneration;
    final material = state.material;
    if (material == null || !state.isReady) return;
    try {
      final service = await ref.read(playerSubtitlesProvider.future);
      if (!_isCurrent(generation)) return;
      final tracks = await service.save(track, manual: manual);
      await _applySubtitleTracks(material, tracks, generation);
    } catch (_) {
      if (_isCurrent(generation)) {
        state = state.copyWith(errorMessage: '字幕設定儲存失敗');
      }
    }
  }

  Future<bool> _applySubtitleTracks(
    LearningMaterial material,
    List<SubtitleTrack> tracks,
    int generation,
  ) async {
    final current = _bundle;
    if (!_isCurrent(generation) || current == null) return false;
    final wasIntensive = _session?.state.mode == LearningMode.intensive;
    final bundle = MaterialPlaybackBundle(
      material: material,
      source: current.source,
      subtitleTracks: tracks,
    );
    await _loadBookmarkAnchors(material.id, tracks, generation);
    if (!_isCurrent(generation)) return false;
    _bundle = bundle;
    await _createSession(generation, wasIntensive: wasIntensive);
    if (!_isCurrent(generation) || !identical(_bundle, bundle)) return false;
    state = state.copyWith(
      learning: _session?.state,
      englishTrack: bundle.englishTrack,
      subtitleTracks: tracks,
      timeline: bundle.timeline,
      clearLearning: _session == null,
      clearEnglishTrack: bundle.englishTrack == null,
      isCurrentCueBookmarked: _isBookmarked(
        _session?.state.currentCue,
        bundle.englishTrack,
      ),
    );
    return true;
  }

  Future<void> _createSession(
    int generation, {
    bool wasIntensive = false,
  }) async {
    await _resources.closeLearning();
    if (!_isCurrent(generation)) return;
    final bundle = _bundle;
    final english = bundle?.englishTrack;
    if (bundle == null || english == null) return;
    final session = _sessionFactory.create(
      englishTrack: english,
      chineseTrack: bundle.chineseTrack,
      timeline: bundle.timeline,
      normalVisibility: state.normalVisibility,
    );
    if (wasIntensive) session.enterIntensive();
    _resources.attachLearning(session, _syncLearningState);
  }

  void _syncLearningState(LearningSessionState learning) {
    if (_disposed || !state.isReady) return;
    state = state.copyWith(
      learning: learning,
      clearLearning: false,
      isCurrentCueBookmarked: _isBookmarked(
        learning.currentCue,
        state.englishTrack,
      ),
    );
  }

  Future<void> _loadBookmarkAnchors(
    String materialId,
    List<SubtitleTrack> tracks,
    int generation,
  ) async {
    final service = PlayerBookmarks(
      await ref.read(bookmarkRepositoryProvider.future),
    );
    if (!_isCurrent(generation)) return;
    final bookmarks = await service.load(materialId, tracks);
    if (_isCurrent(generation)) _bookmarks = bookmarks;
  }

  bool _isBookmarked(SubtitleCue? cue, SubtitleTrack? track) =>
      cue != null &&
      track != null &&
      _bookmarks.containsKey(PlayerBookmarks.key(track, cue));

  Future<void> _runAudioCommand(
    Future<void> Function() command, {
    bool persistProgress = false,
  }) async {
    final generation = _openGeneration;
    if (_closingAccount || !state.isReady) return;
    try {
      await command();
      if (!_isCurrent(generation)) return;
      state = state.copyWith(playback: _audioEngine.snapshot, clearError: true);
      if (persistProgress) {
        await _resources.savePosition(_audioEngine.snapshot);
      }
    } catch (_) {
      if (_isCurrent(generation)) {
        state = state.copyWith(errorMessage: '播放操作失敗，請重試。');
      }
    }
  }

  /// Finish pending progress on the current account, then unload its media.
  Future<void> closeForAccountChange() async {
    _closingAccount = true;
    _openGeneration++;
    try {
      await Future.wait([_releaseSession(), _audioEngine.unload()]);
    } finally {
      if (!_disposed && ref.mounted) state = const PlayerViewState();
      _closingAccount = false;
    }
  }

  Future<void> _releaseSession({
    CheckpointState finalProgressState = CheckpointState.paused,
  }) async {
    _bundle = null;
    _bookmarks = const {};
    await _resources.close(finalProgressState);
  }

  Future<void> _disposeResources() async {
    _disposed = true;
    _openGeneration++;
    await _releaseSession(finalProgressState: CheckpointState.paused);
  }

  bool _isCurrent(int generation) =>
      !_disposed && !_closingAccount && generation == _openGeneration;

  void _ensureUsable() {
    if (_disposed) throw StateError('PlayerViewModel has been disposed.');
  }
}

final playerViewModelProvider =
    NotifierProvider.autoDispose<PlayerViewModel, PlayerViewState>(
      PlayerViewModel.new,
    );
