import 'package:english_learning_player/core/audio/audio_engine_provider.dart';
import 'package:english_learning_player/core/audio/audio_engine.dart';
import 'package:english_learning_player/core/audio/audio_media_session_provider.dart';
import 'package:english_learning_player/core/sync/progress_policy.dart';
import 'package:english_learning_player/features/progress/domain/progress_models.dart';
import 'package:english_learning_player/features/library/material_repository.dart';
import 'package:english_learning_player/features/player/player_dependencies.dart';
import 'package:english_learning_player/features/player/player_page.dart';
import 'package:english_learning_player/features/player/services/material_playback_loader.dart';
import 'package:english_learning_player/features/bookmarks/bookmark_dependencies.dart';
import 'package:english_learning_player/features/subtitles/domain/subtitle_models.dart';
import 'package:english_learning_player/features/bookmarks/bookmarks_page.dart';
import 'package:english_learning_player/features/bookmarks/domain/bookmark.dart';
import 'package:english_learning_player/features/library/library_dependencies.dart';
import 'package:english_learning_player/features/progress/progress_dependencies.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_audio_engine.dart';
import '../../fakes/fake_audio_media_session.dart';
import '../../fakes/fake_bookmark_repository.dart';
import '../../fakes/fake_progress_repository.dart';

void main() {
  late LearningMaterial material;
  late Uri mediaUri;
  late List<SubtitleTrack> tracks;
  late FakeAudioEngine audio;
  late FakeBookmarkRepository bookmarks;
  late FakeProgressRepository progress;
  late FakeAudioMediaSession mediaSession;
  late Widget Function({TextScaler textScaler}) buildApp;

  setUp(() {
    material = LearningMaterial(
      id: 'material-1',
      ownerId: 'owner-1',
      title: 'A lesson',
      audioAssetId: 'asset-1',
      status: MaterialStatus.localReady,
      createdAt: DateTime.utc(2026),
      durationMs: 60_000,
    );
    mediaUri = Uri.parse('file:///tmp/lesson.m4a');
    tracks = [
      _track(
        id: 'en-track',
        language: 'en',
        selected: true,
        cues: const [
          SubtitleCue(
            id: 'en-1',
            sequence: 9,
            startMs: 1000,
            endMs: 2500,
            text: 'A sentence to learn.',
          ),
        ],
      ),
      _track(
        id: 'zh-track',
        language: 'zh-TW',
        selected: true,
        cues: const [
          SubtitleCue(
            id: 'zh-1',
            sequence: 1,
            startMs: 1000,
            endMs: 2500,
            text: '一句練習句。',
          ),
        ],
      ),
    ];
    audio = FakeAudioEngine({mediaUri: 60_000});
    bookmarks = FakeBookmarkRepository();
    progress = FakeProgressRepository();
    mediaSession = FakeAudioMediaSession();
    buildApp = ({TextScaler textScaler = TextScaler.noScaling}) =>
        ProviderScope(
          overrides: [
            audioEngineProvider.overrideWithValue(audio),
            bookmarkRepositoryProvider.overrideWith((ref) async => bookmarks),
            progressRepositoryProvider.overrideWith((ref) async => progress),
            audioMediaSessionProvider.overrideWith((ref) async => mediaSession),
            materialPlaybackLoaderProvider.overrideWith(
              (ref) async => _FixedLoader(
                MaterialPlaybackBundle(
                  material: material,
                  source: MediaSource(materialId: material.id, uri: mediaUri),
                  subtitleTracks: tracks,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(textScaler: textScaler),
              child: PlayerPage(material: material),
            ),
          ),
        );
  });

  tearDown(() async {
    await audio.dispose();
  });

  testWidgets('subtitle sheet exposes manual import and inactive tools', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('字幕設定'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('AI 語音辨識（尚未提供）'), findsOneWidget);
    expect(find.byTooltip('手動匯入 SRT'), findsOneWidget);
    expect(find.byTooltip('字幕樣式（尚未提供）'), findsOneWidget);
    expect(find.text('英文'), findsWidgets);
    expect(find.text('中文'), findsWidgets);
  });

  testWidgets(
    'shows the full bilingual transcript before the first cue plays',
    (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('逐句字幕'), findsOneWidget);
      expect(find.text('A sentence to learn.'), findsOneWidget);
      expect(find.text('一句練習句。'), findsOneWidget);
      expect(find.byKey(const ValueKey('activeSubtitleCard')), findsNothing);
    },
  );

  testWidgets('renders an already-imported bilingual cue from one SRT track', (
    tester,
  ) async {
    tracks = [
      _track(
        id: 'bilingual-track',
        language: 'en',
        selected: true,
        cues: const [
          SubtitleCue(
            id: 'bilingual-1',
            sequence: 1,
            startMs: 0,
            endMs: 2000,
            text: 'So, imagine this scenario.\n我想請你想像這個情境。',
          ),
        ],
      ),
    ];
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('So, imagine this scenario.'), findsOneWidget);
    expect(find.text('我想請你想像這個情境。'), findsOneWidget);
  });

  testWidgets('keeps the playing sentence inside the transcript viewport', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 700);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tracks = [
      _track(
        id: 'long-track',
        language: 'en',
        selected: true,
        cues: [
          for (var index = 0; index < 40; index++)
            SubtitleCue(
              id: 'long-$index',
              sequence: index + 1,
              startMs: (index + 1) * 1000,
              endMs: (index + 1) * 1000 + 900,
              text: 'Sentence number $index.',
            ),
        ],
      ),
    ];
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    audio.advanceTo(28000);
    await tester.pumpAndSettle();

    final activeRect = tester.getRect(
      find.byKey(const ValueKey('activeSubtitleCard')),
    );
    final viewportRect = tester.getRect(
      find.byKey(const ValueKey('subtitleTranscriptList')),
    );
    expect(viewportRect.contains(activeRect.topLeft), isTrue);
    expect(viewportRect.contains(activeRect.bottomRight), isTrue);
    expect(find.text('Sentence number 27.'), findsOneWidget);

    audio.advanceTo(39000);
    await tester.pumpAndSettle();
    final nextActiveRect = tester.getRect(
      find.byKey(const ValueKey('activeSubtitleCard')),
    );
    final nextViewportRect = tester.getRect(
      find.byKey(const ValueKey('subtitleTranscriptList')),
    );
    expect(nextViewportRect.contains(nextActiveRect.topLeft), isTrue);
    expect(nextViewportRect.contains(nextActiveRect.bottomRight), isTrue);
    expect(find.text('Sentence number 38.'), findsOneWidget);
  });

  for (final scenario in [
    (name: 'narrow phone', size: const Size(320, 700), scale: 1.0),
    (name: 'wide desktop', size: const Size(1280, 720), scale: 1.0),
    (name: 'large text', size: const Size(390, 844), scale: 1.8),
    (name: 'compact with large text', size: const Size(320, 600), scale: 1.8),
  ]) {
    testWidgets('renders ${scenario.name} without layout exceptions', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario.size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildApp(textScaler: TextScaler.linear(scenario.scale)),
      );
      await tester.pumpAndSettle();
      audio.advanceTo(1800);
      await tester.pumpAndSettle();

      expect(find.text('A lesson'), findsOneWidget);
      expect(find.text('0:01'), findsOneWidget);
      expect(find.text('1:00'), findsOneWidget);
      expect(find.byTooltip('字幕設定').hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('subtitleTranscriptList')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('previewing the timeline seeks only when released', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    final slider = find.byKey(const ValueKey('playbackPositionSlider'));
    final gesture = await tester.startGesture(tester.getCenter(slider));
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();

    expect(find.text('0:00'), findsNothing);
    expect(audio.seekCalls, 0);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(audio.seekCalls, 1);
    expect(audio.snapshot.positionMs, greaterThan(0));
  });

  testWidgets('tapping the current sentence seeks and plays it once', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    audio.advanceTo(1800);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('activeSubtitleCard')));
    await tester.pumpAndSettle();

    expect(audio.seekCalls, 1);
    expect(audio.playCalls, 1);
    expect(audio.snapshot.positionMs, 1000);
    expect(
      progress.checkpoints.any((checkpoint) => checkpoint.positionMs == 1000),
      isTrue,
    );
  });

  testWidgets('tapping a sentence card plays only that sentence', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    audio.advanceTo(1800);
    await tester.pumpAndSettle();
    expect(audio.snapshot.currentLoop, isNull);

    await tester.tap(find.byKey(const ValueKey('activeSubtitleCard')));
    await tester.pumpAndSettle();
    expect(audio.snapshot.currentLoop, isNull);
    expect(audio.snapshot.playing, isTrue);

    audio.advanceTo(2600);
    await tester.pumpAndSettle();
    expect(audio.snapshot.positionMs, 2600);
    expect(audio.snapshot.playing, isFalse);
  });

  testWidgets('resumes confirmed canonical progress only on normal open', (
    tester,
  ) async {
    progress.savedCanonical = CanonicalProgress(
      checkpoint: ProgressCheckpoint(
        stream: (
          ownerId: material.ownerId,
          materialId: material.id,
          deviceId: 'other-device',
          sessionId: 'previous-session',
        ),
        positionMs: 12000,
        state: CheckpointState.paused,
        sequence: 4,
        baseRevision: 7,
      ),
      revision: 7,
    );
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(mediaSession.id, material.id);
    expect(mediaSession.title, material.title);
    expect(audio.snapshot.positionMs, 12000);
    expect(audio.seekCalls, 1);
    await progress.mergeRemoteCanonical(
      checkpoint: ProgressCheckpoint(
        stream: (
          ownerId: material.ownerId,
          materialId: material.id,
          deviceId: 'remote-device',
          sessionId: 'remote-session',
        ),
        positionMs: 25000,
        state: CheckpointState.paused,
        sequence: 1,
        baseRevision: 8,
      ),
      revision: 8,
      nowMs: DateTime.utc(2026).millisecondsSinceEpoch,
    );
    await tester.pump();
    expect(audio.snapshot.positionMs, 12000);
    expect(audio.seekCalls, 1);
  });

  testWidgets('changing subtitle visibility preserves playback position', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    audio.advanceTo(1800);
    await tester.pump();

    await tester.tap(find.byTooltip('字幕設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('只顯示英文'));
    await tester.pumpAndSettle();

    expect(audio.snapshot.positionMs, 1800);
    expect(find.text('A sentence to learn.'), findsOneWidget);
    expect(find.text('一句練習句。'), findsNothing);
    expect(audio.seekCalls, 0);
  });

  testWidgets('hide and intensive reveal use the same subtitle visibility', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    audio.advanceTo(1800);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('字幕設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隱藏'));
    await tester.pumpAndSettle();
    expect(find.text('A sentence to learn.'), findsNothing);
    expect(find.text('一句練習句。'), findsNothing);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.text('雙語'));
    await tester.pumpAndSettle();
    expect(find.text('一句練習句。'), findsOneWidget);

    await tester.tap(find.widgetWithText(ActionChip, '精聽'));
    await tester.pumpAndSettle();
    expect(find.text('A sentence to learn.'), findsNothing);
    expect(find.text('一句練習句。'), findsNothing);
    await tester.tap(find.widgetWithText(ActionChip, '顯示英文'));
    await tester.pumpAndSettle();
    expect(find.text('A sentence to learn.'), findsOneWidget);
    expect(find.text('一句練習句。'), findsNothing);
    await tester.tap(find.widgetWithText(ActionChip, '顯示中文'));
    await tester.pumpAndSettle();
    expect(find.text('一句練習句。'), findsOneWidget);
    expect(audio.seekCalls, 0);
  });

  testWidgets('current cue can be bookmarked and removed', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    audio.advanceTo(1800);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('收藏本句'));
    await tester.pumpAndSettle();
    expect(await bookmarks.listBookmarks(), hasLength(1));
    expect(find.byTooltip('移除收藏'), findsOneWidget);

    await tester.tap(find.byTooltip('移除收藏'));
    await tester.pumpAndSettle();
    expect(await bookmarks.listBookmarks(), isEmpty);
  });

  testWidgets('favorites resolve updated subtitles and start that cue', (
    tester,
  ) async {
    const oldTrack = 'old-en-track';
    final saved = await bookmarks.addBookmark(
      Bookmark(
        id: 'saved-bookmark',
        ownerId: material.ownerId,
        materialId: material.id,
        anchor: const BookmarkCueAnchor(
          trackId: oldTrack,
          trackRevision: 1,
          languageTag: 'en',
          cueId: 'old-cue',
          cueText: 'A sentence to learn.',
          startMs: 1000,
          endMs: 2500,
        ),
        createdAt: DateTime.utc(2026),
      ),
    );
    expect(saved.id, 'saved-bookmark');
    final latestTrack = _track(
      id: 'current-en-track',
      language: 'en',
      selected: true,
      revision: 2,
      cues: const [
        SubtitleCue(
          id: 'current-cue',
          sequence: 7,
          startMs: 3000,
          endMs: 4500,
          text: 'A sentence to learn.',
        ),
      ],
    );
    final library = _FakeMaterialRepository(material, [latestTrack]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioEngineProvider.overrideWithValue(audio),
          bookmarkRepositoryProvider.overrideWith((ref) async => bookmarks),
          progressRepositoryProvider.overrideWith((ref) async => progress),
          audioMediaSessionProvider.overrideWith((ref) async => mediaSession),
          materialRepositoryProvider.overrideWith((ref) async => library),
          materialPlaybackLoaderProvider.overrideWith(
            (ref) async => _FixedLoader(
              MaterialPlaybackBundle(
                material: material,
                source: MediaSource(materialId: material.id, uri: mediaUri),
                subtitleTracks: [latestTrack],
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: BookmarksPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A sentence to learn.'), findsOneWidget);
    expect(find.text(material.title), findsOneWidget);

    await tester.tap(find.text('A sentence to learn.'));
    for (var frame = 0; frame < 10 && audio.seekCalls == 0; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('無法開啟教材'), findsNothing);
    expect(audio.seekCalls, 1);
    expect(audio.playCalls, 1);
    expect(audio.snapshot.positionMs, 3000);
  });
}

SubtitleTrack _track({
  required String id,
  required String language,
  required bool selected,
  int revision = 1,
  required List<SubtitleCue> cues,
}) => SubtitleTrack(
  id: id,
  ownerId: 'owner-1',
  materialId: 'material-1',
  languageTag: language,
  sourceName: '$language.srt',
  originalBytes: const [],
  revision: revision,
  offsetMs: 0,
  selectionMode: SubtitleSelectionMode.automatic,
  isSelected: selected,
  cues: cues,
);

final class _FixedLoader implements MaterialPlaybackLoader {
  const _FixedLoader(this.bundle);

  final MaterialPlaybackBundle bundle;

  @override
  Future<MaterialPlaybackBundle> load(LearningMaterial material) async =>
      bundle;
}

final class _FakeMaterialRepository implements MaterialRepository {
  const _FakeMaterialRepository(this.material, this.tracks);

  final LearningMaterial material;
  final List<SubtitleTrack> tracks;

  @override
  Future<StoredAudioAsset?> audioAssetForMaterial(String materialId) async =>
      null;

  @override
  Future<InsertMaterialResult> insertAudio({
    required StoredAudioAsset asset,
    required String sourceKey,
    required String title,
    required String materialId,
    required DateTime createdAt,
  }) => throw UnsupportedError('Not needed in bookmark playback test.');

  @override
  Future<List<LearningMaterial>> listMaterials() async => [material];

  @override
  Future<List<SubtitleTrack>> listSubtitleTracks(String materialId) async =>
      tracks;

  @override
  Future<SubtitleTrack> saveSubtitleTrack(
    SubtitleTrack track, {
    required bool manual,
  }) => throw UnsupportedError('Not needed in bookmark playback test.');
}
