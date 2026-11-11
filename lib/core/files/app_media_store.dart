import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../db/account_scope.dart';
import '../db/account_database_service.dart';
import '../../features/library/domain/audio_import_source.dart';
import 'audio_file_type.dart';

final class AppMediaStore {
  const AppMediaStore({
    required AccountDatabaseService storage,
    required AccountScope scope,
  }) : _storage = storage,
       _scope = scope;

  final AccountDatabaseService _storage;
  final AccountScope _scope;

  Future<ImportedAudio> copyAndHash(AudioImportSource source) async {
    final type = AudioFileType.fromName(source.name);
    final directory = _storage.mediaDirectory(_scope);
    await directory.create(recursive: true);
    final temporary = File(
      p.join(directory.path, '.${DateTime.now().microsecondsSinceEpoch}.part'),
    );
    final digestSink = _DigestSink();
    final converter = sha256.startChunkedConversion(digestSink);
    final output = temporary.openWrite();
    var byteLength = 0;
    try {
      await for (final chunk in source.openRead()) {
        byteLength += chunk.length;
        converter.add(chunk);
        output.add(chunk);
      }
      converter.close();
      await output.flush();
      await output.close();
      if (byteLength == 0) throw const AudioImportException('emptyFile');
      final digest = digestSink.digest.toString();
      final relativePath = p.join(
        'media',
        _scope.storageKey,
        '$digest.${type.extension}',
      );
      final destination = File(
        p.join(directory.path, '$digest.${type.extension}'),
      );
      if (await destination.exists()) {
        await temporary.delete();
        if (await destination.length() != byteLength ||
            await sha256
                    .bind(destination.openRead())
                    .first
                    .then((value) => value.toString()) !=
                digest) {
          throw const AudioImportException('storedAssetCorrupt');
        }
      } else {
        await temporary.rename(destination.path);
      }
      return ImportedAudio(
        sha256: digest,
        byteLength: byteLength,
        mediaType: type.mimeType,
        relativePath: relativePath,
      );
    } catch (_) {
      converter.close();
      await output.close();
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }
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

final class AudioImportException implements Exception {
  const AudioImportException(this.code);

  final String code;
}

final class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest value) => digest = value;

  @override
  void close() {}
}
