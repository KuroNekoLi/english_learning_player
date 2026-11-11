typedef FolderHandle = ({String bindingId, String displayLabel});

enum GrantStatus { valid, stale, denied, missing }

enum FolderFailure {
  permissionDenied,
  providerUnavailable,
  fileNotDownloaded,
  notFound,
  transientIo,
}

final class FolderAccessException implements Exception {
  const FolderAccessException(this.failure);

  final FolderFailure failure;
}

enum FolderEntryStatus { available, pendingDownload }

typedef FolderEntry = ({
  String relativePath,
  FolderEntryStatus status,
  int? byteLength,
  DateTime? modifiedAt,
});

/// macOS adapter owns bookmark bytes and coordinates source reads.
abstract interface class FolderAccessGateway {
  /// Returns null on cancellation. The caller supplies a fresh local binding ID.
  Future<FolderHandle?> pickFolder(String bindingId);
  Future<GrantStatus> restoreGrant(String bindingId);

  /// A complete inventory or an error. Pending entries still exist at source.
  Future<List<FolderEntry>> scan(String bindingId);

  /// An event invalidates the inventory. Cancel the subscription to stop watching.
  Stream<void> watch(String bindingId);

  /// Coordinates reading one available entry into an app-owned staging file.
  /// Deletes partial staging data on failure. Source files are read-only.
  Future<Uri> stageFile(String bindingId, String relativePath);

  Future<void> disconnect(String bindingId);
}
