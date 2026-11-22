import '../../../core/sync/sync_contracts.dart';
import '../../library/data/sqlite_library_changes.dart';
import '../../library/domain/library_change.dart';
import 'firebase_documents.dart';

final class FirebaseLibrarySync {
  FirebaseLibrarySync({
    required this.uid,
    required this.documents,
    required this.local,
    required this.consent,
  });

  final String uid;
  final FirebaseDocuments documents;
  final SqliteLibraryChanges local;
  final SyncConsentProvider consent;
  DateTime? _retryAfter;

  List<String> get _path => ['users', uid, 'libraryChanges'];

  Future<bool> hasDue(DateTime now) async =>
      !(_retryAfter?.isAfter(now) ?? false) &&
      (await local.read(pendingOnly: true, limit: 1)).isNotEmpty;

  Future<bool> push() async {
    if (!await hasDue(DateTime.now())) return false;
    final pending = await local.read(pendingOnly: true, limit: 20);
    try {
      for (final change in pending) {
        await _publish(change);
      }
      return true;
    } catch (_) {
      // The SQLite queue survives restart. Pace retries during this run.
      _retryAfter = DateTime.now().add(const Duration(seconds: 30));
      rethrow;
    }
  }

  Future<void> _publish(LibraryChange change) async {
    final path = [..._path, change.key];
    for (var attempt = 0; attempt < 3; attempt++) {
      final existing = await documents.readVersionedDocument(uid, path);
      if (existing != null) {
        final remote = LibraryChange.fromDocument(existing.fields, uid);
        if (remote.key != change.key || existing.updateTime == null) {
          throw const FormatException('Invalid versioned library document');
        }
        if (remote.compareVersion(change) >= 0) {
          await _checkConsent();
          await local.merge([remote]);
          await local.acknowledge(change);
          return;
        }
      }
      try {
        await documents.writeVersionedDocument(
          uid,
          path,
          change.toDocument(uid),
          updateTime: existing?.updateTime,
        );
      } on SyncFailure catch (error) {
        if (const {
          'firebase_http_409',
          'firebase_http_412',
          'library_write_conflict',
        }.contains(error.code)) {
          continue;
        }
        rethrow;
      }
      await _checkConsent();
      await local.acknowledge(change);
      return;
    }
    throw const SyncFailure(
      SyncFailureKind.transient,
      'library_write_conflict',
    );
  }

  Future<void> pull() async {
    final List<Map<String, Object>> records;
    try {
      records = await documents.listDocuments(uid, _path);
    } on SyncFailure catch (error) {
      // Catalog and media remain available with rules deployed by older builds.
      if (error.code == 'firebase_http_403') return;
      rethrow;
    }
    final changes = <LibraryChange>[];
    for (final record in records) {
      try {
        changes.add(LibraryChange.fromDocument(record, uid));
      } on FormatException {
        // Skip an incompatible entry without blocking the remaining library.
      }
    }
    await _checkConsent();
    await local.merge(changes);
  }

  Future<List<CloudMaterialMetadata>> project(
    List<CloudMaterialMetadata> catalog,
  ) async {
    final changes = await local.read();
    final deleted = <String>{};
    final titles = <String, String>{};
    for (final change in changes) {
      if (change.field == LibraryField.materialDeleted) deleted.add(change.id);
      if (change.field == LibraryField.materialTitle) {
        titles[change.id] = change.value;
      }
    }
    return [
      for (final item in catalog)
        if (!deleted.contains(item.materialId))
          if (titles[item.materialId] case final title?)
            CloudMaterialMetadata(
              materialId: item.materialId,
              title: title,
              assetId: item.assetId,
              sha256: item.sha256,
              byteLength: item.byteLength,
              mediaType: item.mediaType,
              storagePath: item.storagePath,
              opId: item.opId,
              payloadHash: item.payloadHash,
            )
          else
            item,
    ];
  }

  Future<void> _checkConsent() async {
    if (!await consent.isCloudSyncEnabled(uid)) {
      throw const SyncFailure(
        SyncFailureKind.permissionDenied,
        'consent_required',
      );
    }
  }
}
