import 'package:english_learning_player/core/platform/folder_access_gateway.dart';
import 'package:english_learning_player/core/platform/folder_access_gateway_provider.dart';
import 'package:english_learning_player/features/library/folder_source_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_folder_access_gateway.dart';

void main() {
  testWidgets(
    'T-FOLDER-10 macOS panel reports pending iCloud entries',
    (tester) async {
      final gateway = FakeFolderAccessGateway([
        (
          relativePath: 'lesson.m4a',
          status: FolderEntryStatus.available,
          byteLength: 10,
          modifiedAt: null,
        ),
        (
          relativePath: 'lesson.en.srt',
          status: FolderEntryStatus.pendingDownload,
          byteLength: null,
          modifiedAt: null,
        ),
      ]);
      addTearDown(gateway.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [folderAccessGatewayProvider.overrideWithValue(gateway)],
          child: const MaterialApp(home: Scaffold(body: FolderSourcePanel())),
        ),
      );
      await tester.pump();

      expect(find.text('選擇資料夾'), findsOneWidget);
      await tester.tap(find.text('選擇資料夾'));
      await tester.pumpAndSettle();

      expect(find.text('Test source'), findsOneWidget);
      expect(find.text('可讀取 1 個檔案，1 個仍在下載'), findsOneWidget);
      expect(find.text('重新掃描'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
