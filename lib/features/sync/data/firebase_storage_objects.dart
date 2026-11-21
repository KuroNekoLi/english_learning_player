import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import 'dart:io';

import '../../../core/sync/sync_contracts.dart';
import 'firebase_account_session.dart';
import 'firebase_endpoint.dart';

final class FirebaseStorageObjects {
  const FirebaseStorageObjects(this.endpoint, this.session, this.http);

  final FirebaseEndpoint endpoint;
  final FirebaseAccountSession session;
  final FirebaseHttp http;

  Future<CloudAssetReceipt> uploadAsset({
    required String uid,
    required CloudMediaAsset asset,
    required File localFile,
    required String opId,
    required String payloadHash,
  }) async {
    if (asset.byteLength <= 0 ||
        asset.byteLength > 104857600 ||
        !const {'audio/mp4', 'audio/mpeg'}.contains(asset.mediaType) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(asset.sha256)) {
      throw const SyncFailure(
        SyncFailureKind.invalidData,
        'invalid_media_metadata',
      );
    }
    final path = 'users/$uid/assets/${asset.id}/${asset.sha256}';
    var metadata = await _objectMetadata(uid, path);
    if (metadata == null) {
      final boundary = const Uuid().v4();
      final fields = {
        'name': path,
        'contentType': asset.mediaType,
        'metadata': {
          'ownerId': uid,
          'assetId': asset.id,
          'sha256': asset.sha256,
          'opId': opId,
          'payloadHash': payloadHash,
        },
      };
      final leading = utf8.encode(
        '--$boundary\r\nContent-Type: application/json; charset=utf-8\r\n\r\n'
        '${jsonEncode(fields)}\r\n--$boundary\r\n'
        'Content-Type: ${asset.mediaType}\r\n\r\n',
      );
      final trailing = utf8.encode('\r\n--$boundary--');
      Stream<List<int>> parts() async* {
        yield leading;
        yield* localFile.openRead();
        yield trailing;
      }

      final response = await http.send(
        'POST',
        endpoint.storage(query: {'name': path}),
        authorization: 'Firebase ${await session.tokenFor(uid)}',
        contentType: ContentType(
          'multipart',
          'related',
          parameters: {'boundary': boundary},
        ),
        headers: const {'X-Goog-Upload-Protocol': 'multipart'},
        body: parts(),
        length: leading.length + asset.byteLength + trailing.length,
      );
      if (response.statusCode == 403 || response.statusCode == 409) {
        // Another retry may have created the immutable object.
        await http.read(response).drain<void>();
        metadata = await _objectMetadata(uid, path);
        if (metadata == null) {
          throw const SyncFailure(
            SyncFailureKind.permissionDenied,
            'storage_write_denied',
          );
        }
      } else {
        await http.requireSuccess(response);
        metadata = await http.json(response);
      }
    }
    final custom = metadata['metadata'];
    if (metadata['name'] != path ||
        metadata['contentType'] != asset.mediaType ||
        int.tryParse('${metadata['size']}') != asset.byteLength ||
        custom is! Map ||
        custom['ownerId'] != uid ||
        custom['assetId'] != asset.id ||
        custom['sha256'] != asset.sha256) {
      _invalidAsset();
    }

    var length = 0;
    final digest = await sha256
        .bind(
          readObject(uid, path).map((chunk) {
            length += chunk.length;
            if (length > asset.byteLength) _invalidAsset();
            return chunk;
          }),
        )
        .first;
    if (length != asset.byteLength || digest.toString() != asset.sha256) {
      _invalidAsset();
    }
    return CloudAssetReceipt(
      storagePath: path,
      sha256: digest.toString(),
      byteLength: length,
      mediaType: asset.mediaType,
    );
  }

  Stream<List<int>> readObject(String uid, String path) async* {
    if (!path.startsWith('users/$uid/')) {
      throw const SyncFailure(
        SyncFailureKind.permissionDenied,
        'invalid_owner_path',
      );
    }
    final response = await http.send(
      'GET',
      endpoint.storage(object: path, query: const {'alt': 'media'}),
      authorization: 'Firebase ${await session.tokenFor(uid)}',
    );
    await http.requireSuccess(response);
    yield* http.read(response);
  }

  Future<void> putSubtitleObject({
    required String uid,
    required String path,
    required List<int> bytes,
    required String digest,
  }) async {
    var existing = await _objectMetadata(uid, path);
    if (existing == null) {
      final boundary = const Uuid().v4();
      const type = 'application/x-subrip';
      final metadata = {
        'name': path,
        'contentType': type,
        'metadata': {'ownerId': uid, 'sha256': digest},
      };
      final response = await http.send(
        'POST',
        endpoint.storage(query: {'name': path}),
        authorization: 'Firebase ${await session.tokenFor(uid)}',
        contentType: ContentType(
          'multipart',
          'related',
          parameters: {'boundary': boundary},
        ),
        headers: const {'X-Goog-Upload-Protocol': 'multipart'},
        bytes: [
          ...utf8.encode(
            '--$boundary\r\nContent-Type: application/json; charset=utf-8\r\n\r\n'
            '${jsonEncode(metadata)}\r\n--$boundary\r\nContent-Type: $type\r\n\r\n',
          ),
          ...bytes,
          ...utf8.encode('\r\n--$boundary--'),
        ],
      );
      if (response.statusCode == 403 || response.statusCode == 409) {
        await http.read(response).drain<void>();
        existing = await _objectMetadata(uid, path);
        if (existing == null) {
          throw const SyncFailure(
            SyncFailureKind.permissionDenied,
            'subtitle_write_denied',
          );
        }
      } else {
        await http.requireSuccess(response);
        existing = await http.json(response);
      }
    }
    if (existing['name'] != path ||
        existing['contentType'] != 'application/x-subrip' ||
        int.tryParse('${existing['size']}') != bytes.length) {
      _invalidAsset();
    }
  }

  Future<Map<String, dynamic>?> _objectMetadata(String uid, String path) async {
    final response = await http.send(
      'GET',
      endpoint.storage(object: path),
      authorization: 'Firebase ${await session.tokenFor(uid)}',
    );
    if (response.statusCode == 404) {
      await http.read(response).drain<void>();
      return null;
    }
    await http.requireSuccess(response);
    return http.json(response);
  }

  static Never _invalidAsset() => throw const SyncFailure(
    SyncFailureKind.invalidData,
    'cloud_asset_integrity_mismatch',
  );
}
