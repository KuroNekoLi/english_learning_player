import 'dart:async';

import 'package:english_learning_player/app/web_library_page.dart';
import 'package:english_learning_player/features/library/library_view_model.dart';
import 'package:english_learning_player/features/library/services/media_selection_import_service.dart';
import 'package:english_learning_player/features/library/material_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Web library shows per-file progress while import is pending', (
    tester,
  ) async {
    final completion = Completer<MediaSelectionImportResult?>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
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

    await tester.tap(find.byTooltip('匯入音訊與 SRT'));
    await tester.pump();

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
}
