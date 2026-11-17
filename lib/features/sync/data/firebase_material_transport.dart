import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

import '../../../core/sync/sync_contracts.dart';
import '../services/cloud_material_download_service.dart';
import 'firebase_account_session.dart';
import 'firebase_endpoint.dart';

final class FirebaseMaterialTransport
    implements CloudSyncTransport, CloudMaterialDownloadTransport {
  const FirebaseMaterialTransport(this.endpoint, this.session, this.http);

  final FirebaseEndpoint endpoint;
  final FirebaseAccountSession session;
  final FirebaseHttp http;

  @override
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
          readAudio(uid: uid, storagePath: path).map((chunk) {
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

  @override
  Future<void> publishAsset({
    required String uid,
    required CloudAssetMetadata metadata,
  }) async {
    final path = ['users', uid, 'mediaAssets', metadata.assetId];
    final record = metadata.toFirestoreDocument(uid);
    final existing = await readDocument(uid, path);
    if (existing != null) {
      // Multiple local materials can reference the same immutable audio asset.
      for (final field in record.keys.where(
        (key) => key != 'opId' && key != 'payloadHash',
      )) {
        if (record[field] != existing[field]) _invalidAsset();
      }
      return;
    }
    try {
      await writeDocument(uid, path, record, createOnly: true);
    } on SyncFailure catch (error) {
      if (error.kind != SyncFailureKind.permissionDenied &&
          error.code != 'firebase_http_409' &&
          error.code != 'firebase_http_400' &&
          error.code != 'firebase_http_412') {
        rethrow;
      }
      final raced = await readDocument(uid, path);
      if (raced == null) rethrow;
      for (final field in record.keys.where(
        (key) => key != 'opId' && key != 'payloadHash',
      )) {
        if (record[field] != raced[field]) _invalidAsset();
      }
    }
  }

  @override
  Future<void> publishMaterial({
    required String uid,
    required CloudMaterialMetadata metadata,
  }) => writeDocument(uid, [
    'users',
    uid,
    'materials',
    metadata.materialId,
  ], metadata.toFirestoreDocument(uid));

  Future<List<CloudMaterialMetadata>> listMaterials(String uid) async {
    final documents = await listDocuments(uid, ['users', uid, 'materials']);
    final materials = <CloudMaterialMetadata>[];
    for (final json in documents) {
      if (json['ownerId'] != uid ||
          json['status'] != 'cloudReady' ||
          json['schemaVersion'] != 1) {
        continue;
      }
      try {
        materials.add(
          CloudMaterialMetadata(
            materialId: json['materialId'] as String,
            title: json['title'] as String,
            assetId: json['audioAssetId'] as String,
            sha256: json['assetSha256'] as String,
            byteLength: json['byteLength'] as int,
            mediaType: json['mediaType'] as String,
            storagePath: json['storagePath'] as String,
            opId: json['opId'] as String,
            payloadHash: json['payloadHash'] as String,
          ),
        );
      } on TypeError {
        continue;
      }
    }
    return List.unmodifiable(materials);
  }

  Future<List<Map<String, Object>>> listDocuments(
    String uid,
    List<String> path,
  ) async {
    _requireOwner(uid, path);
    final records = <Map<String, Object>>[];
    final seenTokens = <String>{};
    String? page;
    do {
      final response = await http.send(
        'GET',
        endpoint.firestore(path, {
          'pageSize': '100',
          if (page != null) 'pageToken': page,
        }),
        authorization: 'Bearer ${await session.tokenFor(uid)}',
      );
      await http.requireSuccess(response);
      final json = await http.json(response);
      final documents = json['documents'];
      if (documents is List) {
        for (final document in documents.whereType<Map<String, dynamic>>()) {
          records.add(_fromFields(document));
        }
      }
      page = json['nextPageToken'] as String?;
    } while (page != null && page.isNotEmpty && seenTokens.add(page));
    return records;
  }

  Future<Map<String, Object>?> readDocument(
    String uid,
    List<String> path,
  ) async {
    _requireOwner(uid, path);
    final response = await http.send(
      'GET',
      endpoint.firestore(path),
      authorization: 'Bearer ${await session.tokenFor(uid)}',
    );
    if (response.statusCode == 404) {
      await http.read(response).drain<void>();
      return null;
    }
    await http.requireSuccess(response);
    return _fromFields(await http.json(response));
  }

  Future<void> writeDocument(
    String uid,
    List<String> path,
    Map<String, Object> record, {
    bool createOnly = false,
  }) async {
    _requireOwner(uid, path);
    final response = await http.send(
      'PATCH',
      endpoint.firestore(
        path,
        createOnly ? {'currentDocument.exists': 'false'} : null,
      ),
      authorization: 'Bearer ${await session.tokenFor(uid)}',
      contentType: ContentType.json,
      bytes: FirebaseHttp.encode({
        'fields': record.map((key, value) => MapEntry(key, _value(value))),
      }),
    );
    await http.requireSuccess(response);
    await http.read(response).drain<void>();
  }

  @override
  Stream<List<int>> readAudio({
    required String uid,
    required String storagePath,
  }) => readObject(uid, storagePath);

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

  static void _requireOwner(String uid, List<String> path) {
    if (path.length < 3 ||
        path[0] != 'users' ||
        path[1] != uid ||
        path.any(
          (part) =>
              part.isEmpty || part == '.' || part == '..' || part.contains('/'),
        )) {
      throw const SyncFailure(
        SyncFailureKind.permissionDenied,
        'invalid_owner_path',
      );
    }
  }

  static Map<String, Object> _value(Object value) => switch (value) {
    String() => {'stringValue': value},
    int() => {'integerValue': value.toString()},
    bool() => {'booleanValue': value},
    _ => throw const SyncFailure(
      SyncFailureKind.invalidData,
      'unsupported_firestore_value',
    ),
  };

  static Map<String, Object> _fromFields(Map<String, dynamic> document) {
    final fields = document['fields'];
    if (fields is! Map<String, dynamic>) return const {};
    final record = <String, Object>{};
    for (final entry in fields.entries) {
      final field = entry.value;
      if (field is! Map<String, dynamic>) continue;
      final map = field['mapValue'];
      final value =
          field['stringValue'] ??
          int.tryParse('${field['integerValue']}') ??
          field['booleanValue'] ??
          (map is Map<String, dynamic> ? _fromFields(map) : null);
      if (value is String ||
          value is int ||
          value is bool ||
          value is Map<String, Object>) {
        record[entry.key] = value as Object;
      }
    }
    return record;
  }
}
