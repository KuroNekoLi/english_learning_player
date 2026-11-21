import 'package:english_learning_player/features/library/services/media_selection_import_service.dart';
import 'package:english_learning_player/features/library/widgets/importing_audio_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the selected audio preview with its circular progress', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ImportingAudioTile(
            progress: MediaFileImportProgress(
              sourceName: 'lesson.m4a',
              bytesCopied: 250,
              totalBytes: 1000,
              status: MediaFileImportStatus.importing,
            ),
          ),
        ),
      ),
    );

    expect(find.text('lesson'), findsOneWidget);
    expect(find.text('正在匯入音訊 · 25%'), findsOneWidget);
    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, 0.25);
    expect(find.byIcon(Icons.audiotrack_rounded), findsOneWidget);
  });
}
