import 'dart:async';

import '../db/account_scope.dart';
import '../../features/library/domain/audio_import_source.dart';

abstract interface class MediaStore {
  Future<ImportedAudio> copyAndHash(
    AudioImportSource source, {
    Future<void> Function(ImportedAudio)? verifyBeforePublish,
  });

  Future<StoredMediaReference?> open(String relativePath);
}

final class ImportedAudio {
  const ImportedAudio({
    required this.sha256,
    required this.byteLength,
    required this.mediaType,
    required this.relativePath,
  });

  final String sha256;
  final int byteLength;
  final String mediaType;
  final String relativePath;
}

final class StoredMediaReference {
  const StoredMediaReference({required this.uri, this.release});

  final Uri uri;
  final FutureOr<void> Function()? release;
}

final class AudioImportException implements Exception {
  const AudioImportException(this.code);

  final String code;
}

String mediaObjectKey(AccountScope scope, String relativePath) {
  final prefix = 'media/${scope.storageKey}/';
  if (!relativePath.startsWith(prefix) ||
      relativePath.substring(prefix.length).contains('/') ||
      relativePath.endsWith('/')) {
    throw const FormatException('Media path is outside its account scope.');
  }
  return relativePath.substring(prefix.length);
}
