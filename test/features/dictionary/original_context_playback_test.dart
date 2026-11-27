import 'package:english_learning_player/core/audio/audio_engine.dart';
import 'package:english_learning_player/core/audio/speech_playback.dart';
import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/features/dictionary/data/original_context_playback.dart';
import 'package:english_learning_player/features/dictionary/domain/original_word_context.dart';
import 'package:english_learning_player/features/library/material_repository.dart';
import 'package:english_learning_player/features/player/services/material_playback_loader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_audio_engine.dart';

void main() {
  test(
    'plays only the saved half-open audio range, then restores player',
    () async {
      final audio = FakeAudioEngine({_uri: 60000});
      addTearDown(audio.dispose);
      final material = _material();
      final repository = _Materials(material, _asset());
      var suspended = 0;
      var resumed = 0;
      final playback = OriginalContextPlayback(
        audio,
        repository,
        _Loader(material),
        AccountScope('owner-1'),
        SpeechPlayback(audio, _Speech()),
        () async {
          suspended++;
          return null;
        },
        (_) async => resumed++,
      );
      addTearDown(playback.dispose);

      final completed = playback.play(_context);
      for (var i = 0; i < 20 && !audio.snapshot.playing; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(audio.snapshot.playing, isTrue);
      expect(audio.snapshot.positionMs, 45000);
      audio.advanceTo(48000);
      expect(await completed, isTrue);
      expect(audio.snapshot.playing, isFalse);
      expect(audio.snapshot.positionMs, 48000);
      expect(suspended, 1);
      expect(resumed, 1);
    },
  );

  test('reports a confirmed cloud-only item as not downloaded', () async {
    final audio = FakeAudioEngine({});
    addTearDown(audio.dispose);
    final material = _material(status: MaterialStatus.cloudReady);
    final playback = OriginalContextPlayback(
      audio,
      _Materials(material, null),
      _Loader(material),
      AccountScope('owner-1'),
      SpeechPlayback(audio, _Speech()),
      () async => null,
      (_) async {},
    );
    addTearDown(playback.dispose);

    final state = await playback.availability(_context);
    expect(state.canPlay, isFalse);
    expect(state.message, '此裝置尚未下載');
  });

  test('stopping a preview releases audio and restores the player', () async {
    final audio = FakeAudioEngine({_uri: 60000});
    addTearDown(audio.dispose);
    final material = _material();
    var resumed = 0;
    final playback = OriginalContextPlayback(
      audio,
      _Materials(material, _asset()),
      _Loader(material),
      AccountScope('owner-1'),
      SpeechPlayback(audio, _Speech()),
      () async => null,
      (_) async => resumed++,
    );
    addTearDown(playback.dispose);

    final completed = playback.play(_context);
    for (var i = 0; i < 20 && !audio.snapshot.playing; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await playback.stop();
    expect(await completed, isFalse);
    expect(audio.snapshot.playing, isFalse);
    expect(resumed, 1);
  });
}

final _uri = Uri.parse('file:///lesson.mp3');
const _context = OriginalWordContext(
  materialId: 'lesson-1',
  materialTitle: 'Lesson',
  startMs: 45000,
  endMs: 48000,
  english: 'It is very murky.',
  translations: ['非常模糊。'],
);

LearningMaterial _material({
  MaterialStatus status = MaterialStatus.localReady,
}) => LearningMaterial(
  id: 'lesson-1',
  ownerId: 'owner-1',
  title: 'Lesson',
  audioAssetId: 'asset-1',
  status: status,
  createdAt: DateTime.utc(2026),
  durationMs: 60000,
);

StoredAudioAsset _asset() => const StoredAudioAsset(
  id: 'asset-1',
  sha256: 'hash',
  byteLength: 100,
  mediaType: 'audio/mpeg',
  relativePath: 'lesson.mp3',
);

final class _Loader implements MaterialPlaybackLoader {
  _Loader(this.material);
  final LearningMaterial material;

  @override
  Future<MaterialPlaybackBundle> load(LearningMaterial requested) async =>
      MaterialPlaybackBundle(
        material: material,
        source: MediaSource(materialId: material.id, uri: _uri),
        subtitleTracks: const [],
      );
}

final class _Materials implements MaterialRepository {
  _Materials(this.material, this.asset);
  final LearningMaterial material;
  final StoredAudioAsset? asset;

  @override
  Future<List<LearningMaterial>> listMaterials() async => [material];

  @override
  Future<StoredAudioAsset?> audioAssetForMaterial(String materialId) async =>
      asset;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Speech implements SpeechPort {
  @override
  Future<void> speak(String text, String locale) async {}

  @override
  Future<void> stop() async {}
}
