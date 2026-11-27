import 'dart:async';

import '../../../core/audio/audio_engine.dart';
import '../../../core/audio/speech_playback.dart';
import '../../../core/db/account_scope.dart';
import '../../library/material_repository.dart';
import '../../player/player_view_model.dart';
import '../../player/services/material_playback_loader.dart';
import '../domain/original_word_context.dart';

final class OriginalContextAvailability {
  const OriginalContextAvailability(this.canPlay, this.message);

  final bool canPlay;
  final String message;
}

/// Plays a saved subtitle range through the app's shared audio gateway.
final class OriginalContextPlayback {
  OriginalContextPlayback(
    this._audio,
    this._materials,
    this._loader,
    this._scope,
    this._speech,
    this._suspendPlayer,
    this._resumePlayer,
  );

  final AudioEngine _audio;
  final MaterialRepository _materials;
  final MaterialPlaybackLoader _loader;
  final AccountScope _scope;
  final SpeechPlayback _speech;
  final Future<PlayerPreviewResume?> Function() _suspendPlayer;
  final Future<void> Function(PlayerPreviewResume?) _resumePlayer;
  final Object _speechOwner = Object();
  int _generation = 0;
  StreamSubscription<PlaybackSnapshot>? _subscription;
  Completer<void>? _playing;
  Completer<void>? _activeDone;
  String? _activeMaterialId;
  bool _disposed = false;

  Future<OriginalContextAvailability> availability(
    OriginalWordContext context,
  ) async {
    if (!context.isPlayableRange) {
      return const OriginalContextAvailability(false, '目前無法播放原音');
    }
    try {
      final matches = await _materials.listMaterials();
      final material = _findMaterial(matches, context.materialId);
      if (material == null) {
        return const OriginalContextAvailability(false, '目前無法播放原音');
      }
      if (material.ownerId != _scope.ownerId) {
        return const OriginalContextAvailability(false, '目前無法播放原音');
      }
      if (await _materials.audioAssetForMaterial(material.id) == null) {
        if (material.status == MaterialStatus.cloudReady ||
            material.status == MaterialStatus.uploading) {
          return const OriginalContextAvailability(false, '此裝置尚未下載');
        }
        return const OriginalContextAvailability(false, '目前無法播放原音');
      }
      return const OriginalContextAvailability(true, '');
    } catch (_) {
      return const OriginalContextAvailability(false, '目前無法播放原音');
    }
  }

  Future<bool> play(
    OriginalWordContext context, {
    void Function()? onStarted,
  }) async {
    if (_disposed) return false;
    await stop();
    final generation = ++_generation;
    final available = await availability(context);
    if (!available.canPlay || !_current(generation)) return false;

    PlayerPreviewResume? resume;
    MaterialPlaybackBundle? bundle;
    var sourceLoaded = false;
    final done = Completer<void>();
    _activeDone = done;
    try {
      await _speech.stop(_speechOwner);
      resume = await _suspendPlayer();
      if (!_current(generation)) return false;
      final material = _findMaterial(
        await _materials.listMaterials(),
        context.materialId,
      );
      if (material == null || material.ownerId != _scope.ownerId) return false;
      bundle = await _loader.load(material);
      if (!_current(generation)) return false;
      await _audio.setSentenceLoop(null);
      await _audio.load(bundle.source);
      sourceLoaded = true;
      if (!_current(generation)) return false;
      final duration = _audio.snapshot.durationMs;
      final start = context.startMs.clamp(0, duration ?? context.endMs);
      final end = context.endMs.clamp(0, duration ?? context.endMs);
      if (end <= start) return false;
      await _audio.seekTo(Duration(milliseconds: start));
      _activeMaterialId = context.materialId;
      _playing = Completer<void>();
      final completion = _playing!;
      _subscription = _audio.snapshots.listen((snapshot) {
        if (!_current(generation)) return;
        if (snapshot.materialId != context.materialId) {
          if (!completion.isCompleted) completion.complete();
          return;
        }
        if (snapshot.positionMs >= end ||
            snapshot.processingState == AudioProcessingState.completed) {
          unawaited(_audio.pause().catchError((Object _) {}));
          if (!completion.isCompleted) completion.complete();
        }
      });
      await _audio.play();
      onStarted?.call();
      await completion.future;
      return _current(generation);
    } catch (_) {
      return false;
    } finally {
      try {
        await _subscription?.cancel();
        _subscription = null;
        _playing = null;
        _activeMaterialId = null;
        if (bundle != null && !sourceLoaded) {
          await bundle.source.release?.call();
        }
        final sourceStillOwned =
            !sourceLoaded || _audio.snapshot.materialId == context.materialId;
        if (!_disposed &&
            sourceStillOwned &&
            (sourceLoaded || resume != null)) {
          await _resumePlayer(resume);
        }
      } finally {
        if (!done.isCompleted) done.complete();
        if (identical(_activeDone, done)) _activeDone = null;
      }
    }
  }

  Future<void> stop() async {
    _generation++;
    final materialId = _activeMaterialId;
    if (materialId != null && _audio.snapshot.materialId == materialId) {
      await _audio.pause().catchError((Object _) {});
    }
    final completion = _playing;
    if (completion != null && !completion.isCompleted) completion.complete();
    await _subscription?.cancel();
    _subscription = null;
    final activeDone = _activeDone;
    if (activeDone != null) await activeDone.future;
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
    await _speech.stop(_speechOwner);
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  LearningMaterial? _findMaterial(List<LearningMaterial> materials, String id) {
    for (final material in materials) {
      if (material.id == id) return material;
    }
    return null;
  }
}
