import 'dart:async';

import 'package:english_learning_player/core/platform/folder_access_gateway.dart';

final class FakeFolderAccessGateway implements FolderAccessGateway {
  FakeFolderAccessGateway(this.entries);

  final List<FolderEntry> entries;
  final _changes = StreamController<void>.broadcast();
  String? _bindingId;
  bool cancelPick = false;
  bool denyGrant = false;
  int scanCount = 0;

  @override
  Future<FolderHandle?> pickFolder(String bindingId) async {
    if (cancelPick) return null;
    _bindingId = bindingId;
    return (bindingId: bindingId, displayLabel: 'Test source');
  }

  @override
  Future<GrantStatus> restoreGrant(String bindingId) async {
    if (_bindingId != bindingId) return GrantStatus.missing;
    return denyGrant ? GrantStatus.denied : GrantStatus.valid;
  }

  @override
  Future<List<FolderEntry>> scan(String bindingId) async {
    await _checkGrant(bindingId);
    scanCount++;
    return List.unmodifiable(entries);
  }

  @override
  Stream<void> watch(String bindingId) async* {
    await _checkGrant(bindingId);
    yield* _changes.stream;
  }

  @override
  Future<Uri> stageFile(String bindingId, String relativePath) async {
    final entries = await scan(bindingId);
    final entry = entries
        .where((entry) => entry.relativePath == relativePath)
        .firstOrNull;
    if (entry == null) {
      throw const FolderAccessException(FolderFailure.notFound);
    }
    if (entry.status == FolderEntryStatus.pendingDownload) {
      throw const FolderAccessException(FolderFailure.fileNotDownloaded);
    }
    return Uri(
      scheme: 'file',
      pathSegments: ['', 'test-staging', relativePath],
    );
  }

  @override
  Future<void> disconnect(String bindingId) async {
    if (_bindingId == bindingId) {
      _bindingId = null;
      await _changes.close();
    }
  }

  Future<void> dispose() =>
      _changes.isClosed ? Future<void>.value() : _changes.close();

  void notifyChange() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> _checkGrant(String bindingId) async {
    switch (await restoreGrant(bindingId)) {
      case GrantStatus.valid:
        return;
      case GrantStatus.missing:
        throw const FolderAccessException(FolderFailure.notFound);
      case GrantStatus.denied:
      case GrantStatus.stale:
        throw const FolderAccessException(FolderFailure.permissionDenied);
    }
  }
}
