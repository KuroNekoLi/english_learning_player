import 'package:flutter/services.dart';

import 'folder_access_gateway.dart';

const folderAccessMethodChannel = MethodChannel(
  'english_learning_player/folder_access/methods',
);
const folderAccessEventChannel = EventChannel(
  'english_learning_player/folder_access/events',
);

/// macOS implementation. Native code owns bookmarks and scopes every access.
final class MethodChannelFolderAccessGateway implements FolderAccessGateway {
  const MethodChannelFolderAccessGateway({
    this._methods = folderAccessMethodChannel,
    this._events = folderAccessEventChannel,
  });

  final MethodChannel _methods;
  final EventChannel _events;

  @override
  Future<FolderHandle?> pickFolder(String bindingId) async {
    final value = await _invokeNullable<Map<Object?, Object?>>('pickFolder', {
      'bindingId': bindingId,
    });
    if (value == null) return null;
    return (
      bindingId: value['bindingId']! as String,
      displayLabel: value['displayLabel']! as String,
    );
  }

  @override
  Future<GrantStatus> restoreGrant(String bindingId) async {
    final value = await _invoke<String>('restoreGrant', {
      'bindingId': bindingId,
    });
    return switch (value) {
      'valid' => GrantStatus.valid,
      'stale' => GrantStatus.stale,
      'denied' => GrantStatus.denied,
      _ => GrantStatus.missing,
    };
  }

  @override
  Future<List<FolderEntry>> scan(String bindingId) async {
    final values = await _invoke<List<Object?>>('scan', {
      'bindingId': bindingId,
    });
    return List.unmodifiable(
      values.map((value) {
        final entry = value! as Map<Object?, Object?>;
        final modifiedAtMs = entry['modifiedAtMs'] as int?;
        return (
          relativePath: entry['relativePath']! as String,
          status: entry['status'] == 'pendingDownload'
              ? FolderEntryStatus.pendingDownload
              : FolderEntryStatus.available,
          byteLength: entry['byteLength'] as int?,
          modifiedAt: modifiedAtMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(modifiedAtMs),
        );
      }),
    );
  }

  @override
  Stream<void> watch(String bindingId) => _events
      .receiveBroadcastStream({'bindingId': bindingId})
      .map<void>((_) {});

  @override
  Future<Uri> stageFile(String bindingId, String relativePath) async {
    final value = await _invoke<String>('stageFile', {
      'bindingId': bindingId,
      'relativePath': relativePath,
    });
    return Uri.parse(value);
  }

  @override
  Future<void> disconnect(String bindingId) async {
    try {
      await _methods.invokeMethod<void>('disconnect', {'bindingId': bindingId});
    } on PlatformException catch (error) {
      throw _mapError(error);
    } on MissingPluginException {
      throw const FolderAccessException(FolderFailure.providerUnavailable);
    }
  }

  Future<T> _invoke<T>(String method, Map<String, Object?> arguments) async {
    try {
      final result = await _methods.invokeMethod<T>(method, arguments);
      if (result == null) {
        throw const FolderAccessException(FolderFailure.providerUnavailable);
      }
      return result as T;
    } on PlatformException catch (error) {
      throw _mapError(error);
    } on MissingPluginException {
      throw const FolderAccessException(FolderFailure.providerUnavailable);
    }
  }

  Future<T?> _invokeNullable<T>(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      return await _methods.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw _mapError(error);
    } on MissingPluginException {
      throw const FolderAccessException(FolderFailure.providerUnavailable);
    }
  }

  FolderAccessException _mapError(PlatformException error) =>
      FolderAccessException(switch (error.code) {
        'permissionDenied' => FolderFailure.permissionDenied,
        'providerUnavailable' => FolderFailure.providerUnavailable,
        'fileNotDownloaded' => FolderFailure.fileNotDownloaded,
        'notFound' => FolderFailure.notFound,
        _ => FolderFailure.transientIo,
      });
}
