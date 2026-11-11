import 'package:english_learning_player/core/audio/audio_engine.dart';
import 'package:english_learning_player/core/platform/folder_access_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_audio_engine.dart';
import '../fakes/fake_folder_access_gateway.dart';

void main() {
  test('audio contract exposes one source and clamps seeks', () async {
    final uri = Uri.file('/synthetic/test.m4a');
    final AudioEngine audio = FakeAudioEngine({uri: 1000});
    addTearDown(audio.dispose);

    final ready = audio.snapshots.first;
    await audio.load(MediaSource(materialId: 'test', uri: uri));
    expect((await ready).processingState, AudioProcessingState.ready);

    await audio.play();
    await audio.seekTo(const Duration(seconds: 2));
    expect(audio.snapshot.positionMs, 1000);
    expect(audio.snapshot.playing, isTrue);

    await expectLater(
      audio.load(MediaSource(materialId: 'missing', uri: Uri.file('/missing'))),
      throwsA(isA<AudioEngineException>()),
    );
    expect(() => TimeRange(200, 200), throwsArgumentError);
  });

  test(
    'folder inventory separates pending downloads from lost grants',
    () async {
      final fake = FakeFolderAccessGateway([
        (
          relativePath: 'test.m4a',
          status: FolderEntryStatus.pendingDownload,
          byteLength: null,
          modifiedAt: null,
        ),
      ]);
      addTearDown(fake.dispose);
      final FolderAccessGateway folders = fake;
      fake.cancelPick = true;
      expect(await folders.pickFolder('binding'), isNull);

      fake.cancelPick = false;
      expect((await folders.pickFolder('binding'))?.bindingId, 'binding');
      expect(
        (await folders.scan('binding')).single.status,
        FolderEntryStatus.pendingDownload,
      );
      await expectLater(
        folders.stageFile('binding', 'test.m4a'),
        throwsA(
          isA<FolderAccessException>().having(
            (error) => error.failure,
            'failure',
            FolderFailure.fileNotDownloaded,
          ),
        ),
      );

      fake.denyGrant = true;
      expect(await folders.restoreGrant('binding'), GrantStatus.denied);
      await expectLater(
        folders.scan('binding'),
        throwsA(
          isA<FolderAccessException>().having(
            (error) => error.failure,
            'failure',
            FolderFailure.permissionDenied,
          ),
        ),
      );

      await folders.disconnect('binding');
      expect(await folders.restoreGrant('binding'), GrantStatus.missing);
    },
  );
}
