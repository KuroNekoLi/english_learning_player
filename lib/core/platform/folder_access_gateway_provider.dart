import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'folder_access_gateway.dart';
import 'method_channel_folder_access_gateway.dart';

final folderAccessGatewayProvider = Provider<FolderAccessGateway>((ref) {
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    return const MethodChannelFolderAccessGateway();
  }
  return const _UnsupportedFolderAccessGateway();
});

final class _UnsupportedFolderAccessGateway implements FolderAccessGateway {
  const _UnsupportedFolderAccessGateway();

  FolderAccessException get _unsupported =>
      const FolderAccessException(FolderFailure.providerUnavailable);

  @override
  Future<FolderHandle?> pickFolder(String bindingId) async =>
      throw _unsupported;

  @override
  Future<GrantStatus> restoreGrant(String bindingId) async =>
      GrantStatus.missing;

  @override
  Future<List<FolderEntry>> scan(String bindingId) async => throw _unsupported;

  @override
  Stream<void> watch(String bindingId) => Stream<void>.error(_unsupported);

  @override
  Future<Uri> stageFile(String bindingId, String relativePath) async =>
      throw _unsupported;

  @override
  Future<void> disconnect(String bindingId) async => throw _unsupported;
}
