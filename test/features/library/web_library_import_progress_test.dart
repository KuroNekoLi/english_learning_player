import 'dart:async';

import 'package:english_learning_player/app/web_library_page.dart';
import 'package:english_learning_player/features/library/library_folder_view_model.dart';
import 'package:english_learning_player/features/library/library_view_model.dart';
import 'package:english_learning_player/features/library/services/media_selection_import_service.dart';
import 'package:english_learning_player/features/library/material_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_library_folder_repository.dart';

void main() {
  testWidgets('Web library shows per-file progress while import is pending', (
    tester,
  ) async {
    final completion = Completer<MediaSelectionImportResult?>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryFolderRepositoryProvider.overrideWith(
            (ref) async => FakeLibraryFolderRepository(),
          ),
          libraryViewModelProvider.overrideWith((ref) async => []),
          libraryImportProvider.overrideWith((ref) {
            return ({onProgress}) {
              onProgress?.call([
                const MediaFileImportProgress(
                  sourceName: 'lesson.m4a',
                  bytesCopied: 500,
                  totalBytes: 1000,
                  status: MediaFileImportStatus.importing,
                ),
              ]);
              return completion.future;
            };
          }),
        ],
        child: const MaterialApp(home: WebLibraryPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新增'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('匯入媒體'));
    await tester.pumpAndSettle();

    expect(find.text('lesson'), findsOneWidget);
    expect(find.text('正在匯入音訊 · 50%'), findsOneWidget);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      0.5,
    );

    completion.complete(
      MediaSelectionImportResult(
        importedMaterials: const <LearningMaterial>[],
        subtitlesImported: 0,
        ambiguousSubtitles: 0,
        audioFailures: 0,
        subtitleFailures: 0,
        unmatchedSubtitles: 0,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('lesson'), findsNothing);
    expect(find.textContaining('音訊 0 個、字幕 0 條'), findsOneWidget);
  });

  testWidgets('library plus menu links subtitles and creates usable folders', (
    tester,
  ) async {
    final repository = FakeLibraryFolderRepository();
    final material = LearningMaterial(
      id: 'lesson',
      ownerId: 'local-default',
      title: 'Lesson',
      audioAssetId: 'asset',
      status: MaterialStatus.localReady,
      createdAt: DateTime.utc(2026),
    );
    LearningMaterial? subtitleTarget;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryViewModelProvider.overrideWith((ref) async => [material]),
          libraryFolderRepositoryProvider.overrideWith(
            (ref) async => repository,
          ),
          librarySubtitleImportProvider.overrideWith((ref) {
            return (target) async {
              subtitleTarget = target;
              return 2;
            };
          }),
        ],
        child: const MaterialApp(home: WebLibraryPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('新增'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('匯入字幕'));
    await tester.pumpAndSettle();
    expect(find.text('選擇要加入字幕的教材'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Lesson'),
      ),
    );
    await tester.pumpAndSettle();
    expect(subtitleTarget, material);
    expect(find.text('「Lesson」已匯入 2 條字幕軌。'), findsOneWidget);

    await tester.tap(find.byTooltip('新增'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新增資料夾'));
    await tester.pumpAndSettle();
    final create = find.widgetWithText(FilledButton, '建立');
    await tester.enterText(find.byType(TextField), '   ');
    expect(tester.widget<FilledButton>(create).onPressed, isNull);
    await tester.enterText(find.byType(TextField), ' 精聽 ');
    await tester.pumpAndSettle();
    await tester.tap(create);
    await tester.pumpAndSettle();
    await tester.tap(find.text('精聽'));
    await tester.pumpAndSettle();
    expect(find.text('此資料夾尚無教材'), findsOneWidget);

    await tester.tap(find.byTooltip('加入教材'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Lesson'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lesson'), findsOneWidget);
    expect(await repository.materialIds('folder-0'), {'lesson'});
  });
}
