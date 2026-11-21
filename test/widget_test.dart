import 'package:english_learning_player/features/library/library_dependencies.dart';
import 'package:english_learning_player/features/library/material_repository.dart';
import 'package:english_learning_player/features/subtitles/domain/subtitle_models.dart';
import 'package:english_learning_player/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final material = LearningMaterial(
    id: 'test-material',
    ownerId: 'local-default',
    title: '合成教材',
    audioAssetId: 'test-asset',
    status: MaterialStatus.localReady,
    createdAt: DateTime.utc(2026),
  );

  testWidgets('empty repository displays the library empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          materialRepositoryProvider.overrideWith(
            (ref) async => _FakeMaterialRepository([]),
          ),
        ],
        child: const EnglishLearningPlayer(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('目前沒有教材'), findsOneWidget);
  });

  testWidgets('local repository data reaches the library view', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          materialRepositoryProvider.overrideWith(
            (ref) async => _FakeMaterialRepository([material]),
          ),
        ],
        child: const EnglishLearningPlayer(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('合成教材'), findsOneWidget);
  });

  testWidgets('library exposes add actions and filters its local materials', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          materialRepositoryProvider.overrideWith(
            (ref) async => _FakeMaterialRepository([material]),
          ),
        ],
        child: const EnglishLearningPlayer(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新增'));
    await tester.pumpAndSettle();
    expect(find.text('匯入媒體'), findsOneWidget);
    expect(find.text('匯入資料夾'), findsOneWidget);
    expect(find.text('從相簿匯入（尚未提供）'), findsOneWidget);

    await tester.tap(find.text('從相簿匯入（尚未提供）'));
    await tester.pumpAndSettle();
    expect(find.text('合成教材'), findsOneWidget);
    await tester.tap(find.byTooltip('搜尋'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pumpAndSettle();
    expect(find.text('目前沒有教材'), findsOneWidget);
  });

  testWidgets('a read failure can be retried through the same repository', (
    tester,
  ) async {
    final repository = _FakeMaterialRepository([material])..fail = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          materialRepositoryProvider.overrideWith((ref) async => repository),
        ],
        child: const EnglishLearningPlayer(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('合成教材'), findsNothing);
    final retry = find.text('無法讀取教材，重試');
    expect(retry, findsOneWidget);

    repository.fail = false;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(retry, findsNothing);
    expect(find.text('合成教材'), findsOneWidget);
  });
}

final class _FakeMaterialRepository implements MaterialRepository {
  _FakeMaterialRepository(this.materials);

  final List<LearningMaterial> materials;
  bool fail = false;

  @override
  Future<List<LearningMaterial>> listMaterials() async {
    if (fail) throw StateError('Simulated local read failure');
    return materials;
  }

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
  }) =>
      throw UnsupportedError('Import is not exercised by these widget tests.');

  @override
  Future<SubtitleTrack> saveSubtitleTrack(
    SubtitleTrack track, {
    required bool manual,
  }) => throw UnsupportedError(
    'Subtitles are not exercised by these widget tests.',
  );

  @override
  Future<List<SubtitleTrack>> listSubtitleTracks(String materialId) async =>
      const [];
}
