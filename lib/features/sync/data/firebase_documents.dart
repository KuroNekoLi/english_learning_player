import '../../../core/sync/sync_contracts.dart';
import '../../auth/data/firebase_identity_session.dart';
import '../../../core/firebase/firebase_endpoint.dart';

final class FirebaseDocuments {
  const FirebaseDocuments(this.endpoint, this.session, this.http);

  final FirebaseEndpoint endpoint;
  final FirebaseIdentitySession session;
  final FirebaseHttp http;

  Future<void> checkCollectionAccess(String uid, List<String> path) async {
    _requireOwner(uid, path);
    final response = await http.send(
      'GET',
      endpoint.firestore(path, {'pageSize': '1'}),
      authorization: () async => 'Bearer ${await session.tokenFor(uid)}',
    );
    await http.requireSuccess(response);
    await http.read(response).drain<void>();
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
        endpoint.firestore(path, {'pageSize': '100', 'pageToken': ?page}),
        authorization: () async => 'Bearer ${await session.tokenFor(uid)}',
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
  ) async => (await readVersionedDocument(uid, path))?.fields;

  Future<({Map<String, Object> fields, String? updateTime})?>
  readVersionedDocument(String uid, List<String> path) async {
    _requireOwner(uid, path);
    final response = await http.send(
      'GET',
      endpoint.firestore(path),
      authorization: () async => 'Bearer ${await session.tokenFor(uid)}',
    );
    if (response.statusCode == 404) {
      await http.read(response).drain<void>();
      return null;
    }
    await http.requireSuccess(response);
    final record = await http.json(response);
    return (
      fields: _fromFields(record),
      updateTime: record['updateTime'] as String?,
    );
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
      authorization: () async => 'Bearer ${await session.tokenFor(uid)}',
      contentType: 'application/json',
      bytes: FirebaseHttp.encode({
        'fields': record.map((key, value) => MapEntry(key, _value(value))),
      }),
    );
    await http.requireSuccess(response);
    await http.read(response).drain<void>();
  }

  /// Replace one document only if it still matches the version read by the
  /// caller. A null version means the document must not exist.
  Future<void> writeVersionedDocument(
    String uid,
    List<String> path,
    Map<String, Object> record, {
    required String? updateTime,
  }) async {
    _requireOwner(uid, path);
    final root = endpoint.firestore(const []);
    final response = await http.send(
      'POST',
      root.replace(
        pathSegments: [
          ...root.pathSegments.take(root.pathSegments.length - 1),
          'documents:commit',
        ],
      ),
      authorization: () async => 'Bearer ${await session.tokenFor(uid)}',
      contentType: 'application/json',
      bytes: FirebaseHttp.encode({
        'writes': [
          {
            'update': {
              'name': [...root.pathSegments.skip(1), ...path].join('/'),
              'fields': record.map(
                (key, value) => MapEntry(key, _value(value)),
              ),
            },
            'currentDocument': updateTime == null
                ? {'exists': false}
                : {'updateTime': updateTime},
          },
        ],
      }),
    );
    if (response.statusCode == 400) {
      final error = (await http.json(response))['error'];
      final conflict = error is Map && error['status'] == 'FAILED_PRECONDITION';
      throw SyncFailure(
        conflict ? SyncFailureKind.transient : SyncFailureKind.invalidData,
        conflict ? 'library_write_conflict' : 'firebase_http_400',
      );
    }
    await http.requireSuccess(response);
    await http.read(response).drain<void>();
  }

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
