import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;

import 'audio_engine.dart';
import 'audio_player_port.dart';

final class JustAudioPlayerPort implements AudioPlayerPort {
  JustAudioPlayerPort({ja.AudioPlayer? player})
    : _player = player ?? ja.AudioPlayer(handleInterruptions: false) {
    _errorSubscription = _player.errorStream.listen(
      _errors.add,
      onError: _errors.add,
    );
    _sessionBinding = _bindAudioSession();
  }

  final ja.AudioPlayer _player;
  final StreamController<Object> _errors = StreamController<Object>.broadcast();
  final StreamController<AudioPortInterruption> _interruptionEvents =
      StreamController<AudioPortInterruption>.broadcast();
  late final StreamSubscription<ja.PlayerException> _errorSubscription;
  late final Future<void> _sessionBinding;
  final List<StreamSubscription<dynamic>> _sessionSubscriptions = [];
  bool _disposed = false;

  @override
  Stream<Duration> get positionStream => _player.positionStream;
  @override
  Stream<Duration?> get durationStream => _player.durationStream;
  @override
  Stream<Duration> get bufferedPositionStream => _player.bufferedPositionStream;
  @override
  Stream<bool> get playingStream => _player.playingStream;
  @override
  Stream<double> get speedStream => _player.speedStream;
  @override
  Stream<AudioPortProcessingState> get processingStateStream =>
      _player.processingStateStream.map(_mapProcessingState);
  @override
  Stream<Object> get errors => _errors.stream;
  @override
  Stream<AudioPortInterruption> get interruptions => _interruptionEvents.stream;

  @override
  Duration get position => _player.position;
  @override
  Duration? get duration => _player.duration;
  @override
  Duration get bufferedPosition => _player.bufferedPosition;
  @override
  bool get playing => _player.playing;
  @override
  double get speed => _player.speed;
  @override
  AudioPortProcessingState get processingState =>
      _mapProcessingState(_player.processingState);

  @override
  Future<Duration?> load(Uri uri) {
    if (uri.scheme == 'file') return _player.setFilePath(uri.toFilePath());
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      return _player.setUrl(uri.toString());
    }
    if (uri.scheme == 'blob') return _player.setUrl(uri.toString());
    throw const AudioEngineException(AudioFailure.unsupportedFormat);
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    await _sessionBinding;
    unawaited(
      _player.play().catchError((Object error) {
        if (!_errors.isClosed) _errors.add(error);
      }),
    );
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> clearSource() => _player.clearAudioSources();

  @override
  Future<void> seekTo(int positionMs) =>
      _player.seek(Duration(milliseconds: positionMs));

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> setClip(TimeRange? range) async {
    // Clearing a clip before the first load is already satisfied.
    if (range == null && _player.audioSource == null) return;
    await _player.setClip(
      start: range == null ? null : Duration(milliseconds: range.startMs),
      end: range == null ? null : Duration(milliseconds: range.endMs),
    );
  }

  @override
  Future<void> setLoopEnabled(bool enabled) =>
      _player.setLoopMode(enabled ? ja.LoopMode.one : ja.LoopMode.off);

  Future<void> _bindAudioSession() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      final session = await AudioSession.instance;
      await session.configure(AudioSessionConfiguration.speech());
      _sessionSubscriptions.add(
        session.interruptionEventStream.listen((event) {
          if (event.begin) {
            _interruptionEvents.add(AudioPortInterruption.began);
          } else if (!event.begin) {
            _interruptionEvents.add(AudioPortInterruption.ended);
          }
        }),
      );
      _sessionSubscriptions.add(
        session.becomingNoisyEventStream.listen(
          (_) =>
              _interruptionEvents.add(AudioPortInterruption.outputBecameNoisy),
        ),
      );
    } catch (error) {
      if (!_errors.isClosed) _errors.add(error);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _sessionBinding;
    await Future.wait([
      _errorSubscription.cancel(),
      for (final subscription in _sessionSubscriptions) subscription.cancel(),
    ]);
    await _player.dispose();
    await _errors.close();
    await _interruptionEvents.close();
  }

  AudioPortProcessingState _mapProcessingState(ja.ProcessingState state) =>
      switch (state) {
        ja.ProcessingState.idle => AudioPortProcessingState.idle,
        ja.ProcessingState.loading => AudioPortProcessingState.loading,
        ja.ProcessingState.buffering => AudioPortProcessingState.buffering,
        ja.ProcessingState.ready => AudioPortProcessingState.ready,
        ja.ProcessingState.completed => AudioPortProcessingState.completed,
      };
}
