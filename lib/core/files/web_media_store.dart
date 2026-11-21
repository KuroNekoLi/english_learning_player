import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:web/web.dart' as web;
import 'package:uuid/uuid.dart';

import '../db/account_scope.dart';
import '../../features/library/domain/audio_import_source.dart';
import 'audio_file_type.dart';
import 'media_store.dart';

/// Stores account-scoped media in OPFS and falls back to IndexedDB Blobs.
///
/// This fallback currently buffers the selected file before publishing it.
/// It avoids partial playable records but can use substantial memory for large
/// files; chunked OPFS streaming remains a performance follow-up.
final class WebMediaStore implements MediaStore {
  WebMediaStore(this._scope);

  final AccountScope _scope;
  WebMediaBackend? _lastWriteBackend;

  WebMediaBackend? get lastWriteBackend => _lastWriteBackend;

  String get _databaseName => 'elp_media_${_scope.storageKey}';

  @override
  Future<ImportedAudio> copyAndHash(
    AudioImportSource source, {
    Future<void> Function(ImportedAudio)? verifyBeforePublish,
  }) async {
    final type = AudioFileType.fromName(source.name);
    try {
      final imported = await _copyToOpfs(
        source,
        type,
        verifyBeforePublish: verifyBeforePublish,
      );
      _lastWriteBackend = WebMediaBackend.opfs;
      return imported;
    } catch (_) {
      // If OPFS is unavailable or out of quota, replay the source stream into
      // the IndexedDB fallback. AudioRead is a stream factory by contract.
    }

    final bytes = BytesBuilder(copy: false);
    final digestSink = _DigestSink();
    final converter = sha256.startChunkedConversion(digestSink);
    var length = 0;
    try {
      await for (final chunk in source.openRead()) {
        length += chunk.length;
        converter.add(chunk);
        bytes.add(chunk);
      }
      converter.close();
      if (length == 0) throw const AudioImportException('emptyFile');
      final digest = digestSink.digest.toString();
      final key = '$digest.${type.extension}';
      final imported = ImportedAudio(
        sha256: digest,
        byteLength: length,
        mediaType: type.mimeType,
        relativePath: 'media/${_scope.storageKey}/$key',
      );
      await verifyBeforePublish?.call(imported);
      final blob = web.Blob(
        [bytes.takeBytes().toJS].toJS,
        web.BlobPropertyBag(type: type.mimeType),
      );
      final database = await _openDatabase();
      try {
        final tx = database.transaction('media'.toJS, 'readwrite');
        final committed = _transactionComplete(tx);
        tx.objectStore('media').put(blob, key.toJS);
        await committed;
        _lastWriteBackend = WebMediaBackend.indexedDb;
        return imported;
      } finally {
        database.close();
      }
    } catch (_) {
      converter.close();
      rethrow;
    }
  }

  Future<ImportedAudio> _copyToOpfs(
    AudioImportSource source,
    AudioFileType type, {
    Future<void> Function(ImportedAudio)? verifyBeforePublish,
  }) async {
    final directory = await _opfsDirectory(create: true);
    final temporaryName = '.${const Uuid().v4()}.part';
    final temporaryHandle = await directory
        .getFileHandle(
          temporaryName,
          web.FileSystemGetFileOptions(create: true),
        )
        .toDart;
    final temporaryWriter = await temporaryHandle.createWritable().toDart;
    var temporaryClosed = false;
    try {
      final digestSink = _DigestSink();
      final converter = sha256.startChunkedConversion(digestSink);
      var byteLength = 0;
      await for (final chunk in source.openRead()) {
        byteLength += chunk.length;
        converter.add(chunk);
        await temporaryWriter.write(Uint8List.fromList(chunk).toJS).toDart;
      }
      converter.close();
      if (byteLength == 0) throw const AudioImportException('emptyFile');
      await temporaryWriter.close().toDart;
      temporaryClosed = true;

      final digest = digestSink.digest.toString();
      final key = '$digest.${type.extension}';
      final imported = ImportedAudio(
        sha256: digest,
        byteLength: byteLength,
        mediaType: type.mimeType,
        relativePath: 'media/${_scope.storageKey}/$key',
      );
      await verifyBeforePublish?.call(imported);

      final destination = await directory
          .getFileHandle(key, web.FileSystemGetFileOptions(create: true))
          .toDart;
      final destinationWriter = await destination.createWritable().toDart;
      try {
        await destinationWriter
            .write(await temporaryHandle.getFile().toDart)
            .toDart;
        await destinationWriter.close().toDart;
      } catch (_) {
        await destinationWriter.abort().toDart;
        rethrow;
      }
      await directory.removeEntry(temporaryName).toDart;
      return imported;
    } catch (_) {
      if (!temporaryClosed) {
        try {
          await temporaryWriter.abort().toDart;
        } catch (_) {}
      }
      try {
        await directory.removeEntry(temporaryName).toDart;
      } catch (_) {}
      rethrow;
    }
  }

  @override
  Future<StoredMediaReference?> open(String relativePath) async {
    final key = mediaObjectKey(_scope, relativePath);
    try {
      final directory = await _opfsDirectory(create: false);
      final handle = await directory
          .getFileHandle(key, web.FileSystemGetFileOptions(create: false))
          .toDart;
      final file = await handle.getFile().toDart;
      final url = web.URL.createObjectURL(file);
      return StoredMediaReference(
        uri: Uri.parse(url),
        release: () => web.URL.revokeObjectURL(url),
      );
    } catch (_) {
      // Older browser data and OPFS-disabled profiles are read from IndexedDB.
    }
    final database = await _openDatabase();
    try {
      final tx = database.transaction('media'.toJS, 'readonly');
      final completed = _transactionComplete(tx);
      final request = tx.objectStore('media').get(key.toJS);
      final value = await _requestResult(request);
      await completed;
      if (value == null || value.isUndefinedOrNull) return null;
      final url = web.URL.createObjectURL(value as web.Blob);
      return StoredMediaReference(
        uri: Uri.parse(url),
        release: () => web.URL.revokeObjectURL(url),
      );
    } finally {
      database.close();
    }
  }

  Future<web.FileSystemDirectoryHandle> _opfsDirectory({
    required bool create,
  }) async {
    final root = await web.window.navigator.storage.getDirectory().toDart;
    return root
        .getDirectoryHandle(
          'elp_media_${_scope.storageKey}',
          web.FileSystemGetDirectoryOptions(create: create),
        )
        .toDart;
  }

  Future<web.IDBDatabase> _openDatabase() async {
    final request = web.window.indexedDB.open(_databaseName, 1);
    request.onupgradeneeded = ((web.Event _) {
      final database = request.result as web.IDBDatabase;
      database.createObjectStore('media');
    }).toJS;
    return await _requestResult(request) as web.IDBDatabase;
  }

  Future<JSAny?> _requestResult(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) {
      if (!completer.isCompleted) completer.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(request.error?.message ?? 'IndexedDB request failed.'),
        );
      }
    }).toJS;
    return completer.future;
  }

  Future<void> _transactionComplete(web.IDBTransaction transaction) {
    final completer = Completer<void>();
    transaction.oncomplete = ((web.Event _) {
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    transaction.onabort = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(
            transaction.error?.message ?? 'IndexedDB transaction aborted.',
          ),
        );
      }
    }).toJS;
    transaction.onerror = ((web.Event _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(
            transaction.error?.message ?? 'IndexedDB transaction failed.',
          ),
        );
      }
    }).toJS;
    return completer.future;
  }
}

enum WebMediaBackend { opfs, indexedDb }

final class _DigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest value) => digest = value;

  @override
  void close() {}
}
