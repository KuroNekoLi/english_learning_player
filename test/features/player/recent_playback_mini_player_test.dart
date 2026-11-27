import 'package:english_learning_player/core/audio/audio_engine.dart';
import 'package:english_learning_player/core/audio/audio_engine_provider.dart';
import 'package:english_learning_player/core/audio/audio_media_session_provider.dart';
import 'package:english_learning_player/features/bookmarks/bookmark_dependencies.dart';
import 'package:english_learning_player/features/library/library_view_model.dart';
import 'package:english_learning_player/features/library/material_repository.dart';
import 'package:english_learning_player/features/player/player_dependencies.dart';
import 'package:english_learning_player/features/player/services/material_playback_loader.dart';
import 'package:english_learning_player/features/player/widgets/recent_playback_mini_player.dart';
import 'package:english_learning_player/features/progress/domain/progress_models.dart';
import 'package:english_learning_player/features/progress/progress_dependencies.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_audio_engine.dart';
import '../../fakes/fake_audio_media_session.dart';
import '../../fakes/fake_bookmark_repository.dart';
import '../../fakes/fake_progress_repository.dart';

void main() {
  testWidgets('home mini player shows recent position and resumes on play', (
    tester,
  ) async {
    final material = LearningMaterial(
      id: 'resume-1',
      ownerId: 'owner-1',
      title: 'Resume lesson',
      audioAssetId: 'asset-1',
      status: MaterialStatus.localReady,
      createdAt: DateTime.utc(2026),
      durationMs: 90000,
    );
    final uri = Uri.parse('file:///tmp/resume.m4a');
    final audio = FakeAudioEngine({uri: 90000});
    final progress = FakeProgressRepository()
      ..localPositions[material.id] = LocalPlaybackPosition(
        materialId: material.id,
        positionMs: 42000,
        lastPlayedAtMs: 1,
      );
    final bookmarks = FakeBookmarkRepository();
    final mediaSession = FakeAudioMediaSession();
    addTearDown(audio.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioEngineProvider.overrideWithValue(audio),
          progressRepositoryProvider.overrideWith((ref) async => progress),
          libraryViewModelProvider.overrideWith((ref) async => [material]),
          bookmarkRepositoryProvider.overrideWith((ref) async => bookmarks),
          audioMediaSessionProvider.overrideWith((ref) async => mediaSession),
          materialPlaybackLoaderProvider.overrideWith(
            (ref) async => _Loader(
              MaterialPlaybackBundle(
                material: material,
                source: MediaSource(materialId: material.id, uri: uri),
                subtitleTracks: const [],
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(bottomNavigationBar: RecentPlaybackMiniPlayer()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Resume lesson'), findsOneWidget);
    expect(find.text('繼續播放 · 00:42'), findsOneWidget);
    await tester.tap(find.byTooltip('播放'));
    await tester.pumpAndSettle();

    expect(audio.snapshot.positionMs, 42000);
    expect(audio.playCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

final class _Loader implements MaterialPlaybackLoader {
  const _Loader(this.bundle);

  final MaterialPlaybackBundle bundle;

  @override
  Future<MaterialPlaybackBundle> load(LearningMaterial material) async =>
      bundle;
}
