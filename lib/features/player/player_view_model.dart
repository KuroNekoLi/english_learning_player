import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/audio/audio_engine.dart';
import '../../core/audio/audio_engine_provider.dart';
import '../../core/audio/audio_media_session_provider.dart';
import '../../core/sync/progress_policy.dart';
import '../../features/learning/domain/learning_session.dart';
import '../../features/learning/learning_session_provider.dart';
import '../../features/bookmarks/bookmark_dependencies.dart';
import '../../features/bookmarks/bookmark_list_view_model.dart';
import '../../features/bookmarks/domain/bookmark.dart';
import '../../features/bookmarks/domain/bookmark_resolver.dart';
import '../library/library_view_model.dart';
import '../library/material_repository.dart';
import '../progress/progress_dependencies.dart';
import '../progress/services/playback_progress_recorder.dart';
import '../subtitles/domain/subtitle_models.dart';
import '../subtitles/services/subtitle_import_service.dart';
import 'player_dependencies.dart';
import 'services/material_playback_loader.dart';

enum PlayerLoadStatus { idle, loading, ready, error }

final class PlayerViewState {
  const PlayerViewState({
    this.status = PlayerLoadStatus.idle,
    this.material,
    this.playback,
    this.learning,
    this.englishTrack,
    this.subtitleTracks = const [],
    this.errorMessage,
    this.isCurrentCueBookmarked = false,
  });

  final PlayerLoadStatus status;
  final LearningMaterial? material;
  final PlaybackSnapshot? playback;
  final LearningSessionState? learning;
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
    englishTrack: clearEnglishTrack ? null : englishTrack ?? this.englishTrack,
    subtitleTracks: subtitleTracks ?? this.subtitleTracks,
    errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    isCurrentCueBookmarked:
        isCurrentCueBookmarked ?? this.isCurrentCueBookmarked,
  );
}

final class PlayerViewModel extends Notifier<PlayerViewState> {
  late AudioEngine _audioEngine;
  late LearningSessionFactory _sessionFactory;
  LearningSession? _session;
  MaterialPlaybackBundle? _bundle;
  StreamSubscription<PlaybackSnapshot>? _playbackSubscription;
  StreamSubscription<LearningSessionState>? _learningSubscription;
  PlaybackProgressRecorder? _progressRecorder;
  SubtitleVisibility _normalVisibility = SubtitleVisibility.bilingual;
  int _openGeneration = 0;
  bool _disposed = false;

  SubtitleVisibility get normalVisibility => _normalVisibility;
  final Map<String, Bookmark> _bookmarksByCueKey = {};
  final BookmarkResolver _bookmarkResolver = const BookmarkResolver();

  @override
  PlayerViewState build() {
    _audioEngine = ref.watch(audioEngineProvider);
    _sessionFactory = ref.watch(learningSessionFactoryProvider);
    ref.onDispose(() => unawaited(_disposeResources()));
    return const PlayerViewState();
  }

  Future<void> open(LearningMaterial material, {String? initialCueId}) async {
    _ensureUsable();
    final generation = ++_openGeneration;
    state = PlayerViewState(
      status: PlayerLoadStatus.loading,
      material: material,
    );
    await _releaseSession(finalProgressState: CheckpointState.stopped);
    try {
      final loader = await ref.read(materialPlaybackLoaderProvider.future);
      final bundle = await loader.load(material);
      if (generation != _openGeneration) return;
      _bundle = bundle;
      await _audioEngine.load(bundle.source);
      if (generation != _openGeneration) return;
      await _publishMediaItem(material);
      if (generation != _openGeneration) return;
      final progressRepository = await ref.read(
        progressRepositoryProvider.future,
      );
      if (initialCueId == null) {
        final savedProgress = await progressRepository.canonical(material.id);
        final positionMs = savedProgress?.checkpoint.positionMs ?? 0;
        if (positionMs > 0) {
          await _audioEngine.seekTo(Duration(milliseconds: positionMs));
        }
      }
      await _loadBookmarkAnchors(material.id, bundle.subtitleTracks);
      if (generation != _openGeneration) return;
      await _createSession();
      if (generation != _openGeneration) return;
      _progressRecorder = PlaybackProgressRecorder(
        repository: progressRepository,
        stream: (
          ownerId: material.ownerId,
          materialId: material.id,
          deviceId: await progressRepository.deviceId(),
          sessionId: const Uuid().v4(),
        ),
        clock: DateTime.now,
      );
      _playbackSubscription = _audioEngine.snapshots.listen(
        (snapshot) => _updatePlayback(snapshot, generation),
      );
      state = PlayerViewState(
        status: PlayerLoadStatus.ready,
        material: material,
        playback: _audioEngine.snapshot,
        learning: _session?.state,
        englishTrack: bundle.englishTrack,
        subtitleTracks: bundle.subtitleTracks,
        isCurrentCueBookmarked:
            initialCueId != null ||
            _isBookmarked(_session?.state.currentCue, bundle.englishTrack),
      );
      if (initialCueId != null) {
        await _session?.playCue(initialCueId);
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
      if (generation != _openGeneration) return;
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
    await _runAudioCommand(
      () => _audioEngine.seekTo(Duration(milliseconds: positionMs)),
      persistProgress: true,
    );
  }

  Future<void> onLifecycleExit() async {
    await _progressRecorder?.onLifecycleExit(
      positionMs: _audioEngine.snapshot.positionMs,
    );
  }

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
    _normalVisibility = visibility;
    _session?.setNormalVisibility(visibility);
    if (_session != null) _syncLearningState(_session!.state);
  }

  Future<void> selectSubtitleTrack(SubtitleTrack track) async {
    final material = state.material;
    if (material == null || track.materialId != material.id) return;
    await _saveSubtitleTrack(track, manual: true);
  }

  Future<void> importSubtitle({
    required String languageTag,
    required String sourceName,
    required List<int> bytes,
  }) async {
    final material = state.material;
    if (material == null || !state.isReady) return;
    try {
      final repository = await ref.read(materialRepositoryProvider.future);
      final imported = await SubtitleImportService(repository: repository)
          .importBytes(
            ownerId: material.ownerId,
            materialId: material.id,
            languageTag: languageTag,
            sourceName: sourceName,
            bytes: bytes,
            manual: true,
          );
      await _saveSubtitleTrack(imported.track, manual: true);
    } catch (_) {
      state = state.copyWith(errorMessage: '字幕匯入失敗，請確認 SRT 格式。');
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
    if (material == null || track == null || cue == null) return;
    final key = _cueKey(track, cue);
    try {
      final repository = await ref.read(bookmarkRepositoryProvider.future);
      final existing =
          _bookmarksByCueKey[key] ??
          await repository.findForAnchor(
            materialId: material.id,
            anchor: _anchorFor(track, cue),
          );
      if (existing != null) {
        await repository.removeBookmark(existing.id);
        _bookmarksByCueKey.remove(key);
      } else {
        final bookmark = await repository.addBookmark(
          Bookmark(
            id: const Uuid().v4(),
            ownerId: material.ownerId,
            materialId: material.id,
            anchor: _anchorFor(track, cue),
            createdAt: DateTime.now().toUtc(),
          ),
        );
        _bookmarksByCueKey[key] = bookmark;
      }
      ref.invalidate(bookmarkListViewModelProvider);
      state = state.copyWith(
        isCurrentCueBookmarked: _bookmarksByCueKey.containsKey(key),
        clearError: true,
      );
    } catch (_) {
      state = state.copyWith(errorMessage: '收藏儲存失敗，請重試。');
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
      final repository = await ref.read(materialRepositoryProvider.future);
      await repository.saveSubtitleTrack(track, manual: manual);
      final tracks = await repository.listSubtitleTracks(material.id);
      if (generation != _openGeneration || _bundle == null) return;
      final wasIntensive = _session?.state.mode == LearningMode.intensive;
      _bundle = MaterialPlaybackBundle(
        material: material,
        source: _bundle!.source,
        subtitleTracks: tracks,
      );
      await _loadBookmarkAnchors(material.id, tracks);
      await _createSession(wasIntensive: wasIntensive);
      state = state.copyWith(
        learning: _session?.state,
        englishTrack: _bundle!.englishTrack,
        subtitleTracks: tracks,
        clearLearning: _session == null,
        clearEnglishTrack: _bundle!.englishTrack == null,
        isCurrentCueBookmarked: _isBookmarked(
          _session?.state.currentCue,
          _bundle!.englishTrack,
        ),
      );
    } catch (_) {
      state = state.copyWith(errorMessage: '字幕設定儲存失敗');
    }
  }

  Future<void> _createSession({bool wasIntensive = false}) async {
    await _releaseLearningSession();
    final bundle = _bundle;
    final english = bundle?.englishTrack;
    if (bundle == null || english == null) return;
    final session = _sessionFactory.create(
      englishTrack: english,
      chineseTrack: bundle.chineseTrack,
      normalVisibility: _normalVisibility,
    );
    _session = session;
    if (wasIntensive) session.enterIntensive();
    _learningSubscription = session.states.listen(_syncLearningState);
  }

  void _updatePlayback(PlaybackSnapshot snapshot, int generation) {
    if (_disposed || generation != _openGeneration) return;
    final recorder = _progressRecorder;
    if (recorder != null) {
      unawaited(
        recorder
            .onPlaybackSnapshot(
              positionMs: snapshot.positionMs,
              playing: snapshot.playing,
            )
            .catchError((Object _) {}),
      );
    }
    state = state.copyWith(playback: snapshot, clearError: true);
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
  ) async {
    _bookmarksByCueKey.clear();
    final repository = await ref.read(bookmarkRepositoryProvider.future);
    final bookmarks = await repository.listBookmarks();
    for (final bookmark in bookmarks.where(
      (item) => item.materialId == materialId,
    )) {
      final resolution = _bookmarkResolver.resolve(bookmark, tracks);
      if (resolution.status == BookmarkResolutionStatus.resolved) {
        _bookmarksByCueKey[_cueKey(resolution.track!, resolution.cue!)] =
            bookmark;
      }
    }
  }

  Future<void> _publishMediaItem(LearningMaterial material) async {
    try {
      final mediaSession = await ref.read(audioMediaSessionProvider.future);
      await mediaSession.publishMediaItem(
        id: material.id,
        title: material.title,
        durationMs: _audioEngine.snapshot.durationMs,
      );
    } catch (_) {
      // Keep foreground playback available if a platform media session fails.
    }
  }

  bool _isBookmarked(SubtitleCue? cue, SubtitleTrack? track) =>
      cue != null &&
      track != null &&
      _bookmarksByCueKey.containsKey(_cueKey(track, cue));

  String _cueKey(SubtitleTrack track, SubtitleCue cue) =>
      '${track.id}:${track.revision}:${cue.id}';

  BookmarkCueAnchor _anchorFor(SubtitleTrack track, SubtitleCue cue) {
    final startMs = cue.startMs + track.offsetMs;
    final endMs = cue.endMs + track.offsetMs;
    return BookmarkCueAnchor(
      trackId: track.id,
      trackRevision: track.revision,
      languageTag: track.languageTag,
      cueId: cue.id,
      cueText: cue.text,
      startMs: startMs < 0 ? 0 : startMs,
      endMs: endMs,
    );
  }

  Future<void> _runAudioCommand(
    Future<void> Function() command, {
    bool persistProgress = false,
  }) async {
    if (!state.isReady) return;
    try {
      await command();
      state = state.copyWith(playback: _audioEngine.snapshot, clearError: true);
      if (persistProgress) {
        final snapshot = _audioEngine.snapshot;
        await _progressRecorder?.onSeekCompleted(
          snapshot.positionMs,
          playing: snapshot.playing,
        );
      }
    } catch (_) {
      state = state.copyWith(errorMessage: '播放操作失敗，請重試。');
    }
  }

  Future<void> _releaseSession({
    CheckpointState finalProgressState = CheckpointState.paused,
  }) async {
    final recorder = _progressRecorder;
    _progressRecorder = null;
    await _playbackSubscription?.cancel();
    _playbackSubscription = null;
    await recorder?.dispose(finalState: finalProgressState);
    await _releaseLearningSession();
    _bundle = null;
  }

  Future<void> _releaseLearningSession() async {
    await _learningSubscription?.cancel();
    _learningSubscription = null;
    final session = _session;
    _session = null;
    await session?.dispose();
  }

  Future<void> _disposeResources() async {
    _disposed = true;
    _openGeneration++;
    await _releaseSession(finalProgressState: CheckpointState.paused);
  }

  void _ensureUsable() {
    if (_disposed) throw StateError('PlayerViewModel has been disposed.');
  }
}

final playerViewModelProvider =
    NotifierProvider.autoDispose<PlayerViewModel, PlayerViewState>(
      PlayerViewModel.new,
    );
