import 'package:english_learning_player/core/audio/audio_engine_provider.dart';
import 'package:english_learning_player/core/audio/audio_engine.dart';
import 'package:english_learning_player/features/library/material_repository.dart';
import 'package:english_learning_player/features/player/player_dependencies.dart';
import 'package:english_learning_player/features/player/player_page.dart';
import 'package:english_learning_player/features/player/services/material_playback_loader.dart';
import 'package:english_learning_player/features/subtitles/domain/subtitle_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_audio_engine.dart';

void main() {
  late LearningMaterial material;
  late Uri mediaUri;
  late List<SubtitleTrack> tracks;
  late FakeAudioEngine audio;
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
    buildApp = ({TextScaler textScaler = TextScaler.noScaling}) =>
        ProviderScope(
          overrides: [
            audioEngineProvider.overrideWithValue(audio),
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

  for (final scenario in [
    (name: 'narrow phone', size: const Size(320, 700), scale: 1.0),
    (name: 'wide desktop', size: const Size(1280, 720), scale: 1.0),
    (name: 'large text', size: const Size(390, 844), scale: 1.8),
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

      expect(find.text('A lesson'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

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
  });

  testWidgets('changing subtitle visibility preserves playback position', (
    tester,
  ) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    audio.advanceTo(1800);
    await tester.pump();

    await tester.tap(find.byTooltip('字幕顯示方式'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('只顯示英文'));
    await tester.pumpAndSettle();

    expect(audio.snapshot.positionMs, 1800);
    expect(find.text('A sentence to learn.'), findsOneWidget);
    expect(find.text('一句練習句。'), findsNothing);
    expect(audio.seekCalls, 0);
  });
}

SubtitleTrack _track({
  required String id,
  required String language,
  required bool selected,
  required List<SubtitleCue> cues,
}) => SubtitleTrack(
  id: id,
  ownerId: 'owner-1',
  materialId: 'material-1',
  languageTag: language,
  sourceName: '$language.srt',
  originalBytes: const [],
  revision: 1,
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
