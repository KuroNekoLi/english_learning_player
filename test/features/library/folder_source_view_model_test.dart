import 'package:english_learning_player/core/platform/folder_access_gateway.dart';
import 'package:english_learning_player/core/platform/folder_access_gateway_provider.dart';
import 'package:english_learning_player/features/library/folder_source_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_folder_access_gateway.dart';

void main() {
  test(
    'T-FOLDER-05 missing bookmark starts unconnected without an error',
    () async {
      final gateway = FakeFolderAccessGateway(const []);
      final container = ProviderContainer(
        overrides: [folderAccessGatewayProvider.overrideWithValue(gateway)],
      );
      addTearDown(container.dispose);
      addTearDown(gateway.dispose);

      container.read(folderSourceViewModelProvider);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(folderSourceViewModelProvider);
      expect(state.grantStatus, GrantStatus.missing);
      expect(state.error, isNull);
    },
  );

  test(
    'T-FOLDER-06 connect preserves pending iCloud files in inventory',
    () async {
      final gateway = FakeFolderAccessGateway([
        (
          relativePath: 'lesson.m4a',
          status: FolderEntryStatus.available,
          byteLength: 10,
          modifiedAt: null,
        ),
        (
          relativePath: 'lesson.zh.srt',
          status: FolderEntryStatus.pendingDownload,
          byteLength: null,
          modifiedAt: null,
        ),
      ]);
      final container = ProviderContainer(
        overrides: [folderAccessGatewayProvider.overrideWithValue(gateway)],
      );
      addTearDown(container.dispose);
      addTearDown(gateway.dispose);

      await container.read(folderSourceViewModelProvider.notifier).connect();
      final state = container.read(folderSourceViewModelProvider);

      expect(state.grantStatus, GrantStatus.valid);
      expect(state.displayLabel, 'Test source');
      expect(state.availableCount, 1);
      expect(state.pendingCount, 1);
    },
  );

  test('T-FOLDER-07 permission revocation remains repairable', () async {
    final gateway = FakeFolderAccessGateway(const []);
    gateway.denyGrant = true;
    final container = ProviderContainer(
      overrides: [folderAccessGatewayProvider.overrideWithValue(gateway)],
    );
    addTearDown(container.dispose);
    addTearDown(gateway.dispose);

    await container.read(folderSourceViewModelProvider.notifier).connect();
    final state = container.read(folderSourceViewModelProvider);

    expect(state.grantStatus, GrantStatus.denied);
    expect(state.error, contains('權限'));
  });

  test('T-FOLDER-08 watch notifications schedule a full rescan', () async {
    final gateway = FakeFolderAccessGateway([
      (
        relativePath: 'lesson.m4a',
        status: FolderEntryStatus.available,
        byteLength: 10,
        modifiedAt: null,
      ),
    ]);
    final container = ProviderContainer(
      overrides: [folderAccessGatewayProvider.overrideWithValue(gateway)],
    );
    addTearDown(container.dispose);
    addTearDown(gateway.dispose);
    final viewModel = container.read(folderSourceViewModelProvider.notifier);

    await viewModel.connect();
    await Future<void>.delayed(Duration.zero);
    gateway.entries.add((
      relativePath: 'lesson.zh.srt',
      status: FolderEntryStatus.pendingDownload,
      byteLength: null,
      modifiedAt: null,
    ));
    gateway.notifyChange();
    await Future<void>.delayed(const Duration(milliseconds: 450));

    expect(gateway.scanCount, 2);
    expect(container.read(folderSourceViewModelProvider).pendingCount, 1);
  });

  test('T-FOLDER-09 disconnect cancels source and drops inventory', () async {
    final gateway = FakeFolderAccessGateway([
      (
        relativePath: 'lesson.m4a',
        status: FolderEntryStatus.available,
        byteLength: 10,
        modifiedAt: null,
      ),
    ]);
    final container = ProviderContainer(
      overrides: [folderAccessGatewayProvider.overrideWithValue(gateway)],
    );
    addTearDown(container.dispose);
    addTearDown(gateway.dispose);
    final viewModel = container.read(folderSourceViewModelProvider.notifier);

    await viewModel.connect();
    await viewModel.disconnect();

    expect(
      container.read(folderSourceViewModelProvider).grantStatus,
      GrantStatus.missing,
    );
    expect(container.read(folderSourceViewModelProvider).entries, isEmpty);
    expect(await gateway.restoreGrant(macFolderBindingId), GrantStatus.missing);
  });
}
