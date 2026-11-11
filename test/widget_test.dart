import 'package:english_learning_player/features/library/library_view_model.dart';
import 'package:english_learning_player/features/library/material_repository.dart';
import 'package:english_learning_player/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final material = LearningMaterial(
    id: 'test-material',
    ownerId: 'test-profile',
    title: '合成教材',
    audioAssetId: 'test-asset',
    status: MaterialStatus.localReady,
    createdAt: DateTime.utc(2026),
  );

  testWidgets('FR-01: empty bootstrap launches without a cloud account', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: EnglishLearningPlayer()),
    );
    await tester.pumpAndSettle();
    expect(find.text('目前沒有教材'), findsOneWidget);
  });

  testWidgets('local repository data reaches the library view', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          materialRepositoryProvider.overrideWithValue(
            _FakeMaterialRepository([material]),
          ),
        ],
        child: const EnglishLearningPlayer(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('合成教材'), findsOneWidget);
  });

  testWidgets('a read failure can be retried through the same repository', (
    tester,
  ) async {
    final repository = _FakeMaterialRepository([material])..fail = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [materialRepositoryProvider.overrideWithValue(repository)],
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
}
