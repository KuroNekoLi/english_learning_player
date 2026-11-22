import 'package:english_learning_player/features/library/library_folder_repository.dart';
import 'package:english_learning_player/features/library/material_repository.dart';
import 'package:english_learning_player/features/library/widgets/library_item_menu.dart';
import 'package:english_learning_player/features/library/widgets/library_material_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final material = LearningMaterial(
    id: 'lesson-1',
    ownerId: 'local-default',
    title: 'Lesson',
    audioAssetId: 'asset-1',
    status: MaterialStatus.localReady,
    createdAt: DateTime.utc(2026),
  );

  testWidgets('row menu offers subtitle import and keeps AI disabled', (
    tester,
  ) async {
    LibraryItemAction? selected;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: LibraryMaterialList(
              library: const AsyncData([]),
              materials: [material],
              gridMode: false,
              onRetry: () {},
              onOpen: (_) {},
              onMaterialAction: (_, action) => selected = action,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('更多選項'));
    await tester.pumpAndSettle();
    expect(find.text('匯入字幕'), findsOneWidget);
    expect(find.text('產生字幕'), findsOneWidget);

    final generate = tester.widget<PopupMenuItem<LibraryItemAction>>(
      find.ancestor(
        of: find.text('產生字幕'),
        matching: find.byType(PopupMenuItem<LibraryItemAction>),
      ),
    );
    expect(generate.enabled, isFalse);

    await tester.tap(find.text('匯入字幕'));
    await tester.pumpAndSettle();
    expect(selected, LibraryItemAction.importSubtitles);
  });

  testWidgets('multi-select switches rows to selectable checkboxes', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryMaterialList(
            library: const AsyncData([]),
            materials: [material],
            gridMode: false,
            onRetry: () {},
            onOpen: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('更多選項'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('多選'));
    await tester.pumpAndSettle();

    expect(find.text('已選取 1 個教材'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
  });

  testWidgets('folder row exposes its contextual information menu', (
    tester,
  ) async {
    LibraryItemAction? selected;
    const folder = LibraryFolder(
      id: 'folder-1',
      title: 'Listening',
      materialCount: 2,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryMaterialList(
            library: const AsyncData([]),
            materials: const [],
            folders: const [folder],
            gridMode: false,
            onRetry: () {},
            onOpen: (_) {},
            onFolderAction: (_, action) => selected = action,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('更多選項'));
    await tester.pumpAndSettle();
    expect(find.text('資訊'), findsOneWidget);
    await tester.tap(find.text('資訊'));
    await tester.pumpAndSettle();
    expect(selected, LibraryItemAction.information);
  });
}
