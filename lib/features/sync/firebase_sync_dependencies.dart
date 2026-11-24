import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/firebase/firebase_endpoint.dart';
import '../../core/db/account_database_providers.dart';
import '../auth/data/firebase_identity_session.dart';
import '../library/library_dependencies.dart';
import 'data/firebase_sync_session_native.dart'
    if (dart.library.js_interop) 'data/firebase_sync_session_web.dart'
    as platform;
import '../../core/sync/sqlite_sync_outbox.dart';
import '../../core/sync/sync_contracts.dart';
import '../library/data/sqlite_material_repository.dart';
import '../library/data/sqlite_library_changes.dart';
import 'data/firebase_library_sync.dart';
import '../progress/data/sqlite_progress_repository.dart';
import '../progress/services/progress_sync_coordinator.dart';
import 'data/firebase_material_transport.dart';
import 'data/firebase_progress_transport.dart';
import 'data/firebase_subtitle_sync.dart';
import 'services/cloud_material_download_service.dart';
import 'services/cloud_sync_coordinator.dart';
import 'services/firebase_sync_runtime.dart';
import 'sync_preference.dart';

export 'services/firebase_sync_runtime.dart';

final firebaseMediaEndpointProvider = platform.firebaseMediaEndpointProvider;

final firebaseSyncRuntimeProvider = FutureProvider<FirebaseSyncRuntime?>((
  ref,
) async {
  final account = ref.watch(accountScopeProvider);
  final endpoint = ref.watch(firebaseMediaEndpointProvider);
  final session = platform.watchSyncSession(ref);
  if (endpoint == null ||
      !endpoint.isMediaSyncConfigured ||
      session == null ||
      session.uid != account.cloudUid) {
    return null;
  }
  final key = (uid: account.cloudUid, project: endpoint.project);
  final preferenceStore = ref.watch(syncPreferenceStoreProvider.future);
  bool optedInHere(String uid) =>
      ref.mounted &&
      uid == account.cloudUid &&
      platform.isCurrentSyncAccount(ref, uid) &&
      ref.read(syncPreferenceProvider(key)).asData?.value ==
          SyncPreference.enabled;
  final consent = _Consent((uid) async {
    if (!optedInHere(uid)) return false;
    final stored = await (await preferenceStore).read(key);
    return stored == SyncPreference.enabled && optedInHere(uid);
  });
  final http = FirebaseHttp();
  ref.onDispose(http.close);
  final identity = _GuardedSession(session, consent);
  final transport = FirebaseMaterialTransport(endpoint, identity, http);
  final database = ref.watch(localDatabaseProvider.future);
  final mediaFiles = ref.watch(mediaStoreProvider.future);
  final db = await database;
  final files = await mediaFiles;
  final repository = SqliteMaterialRepository(scope: account, database: db);
  final progress = SqliteProgressRepository(scope: account, db: db);
  final progressTransport = endpoint.progressRegion == null
      ? null
      : FirebaseProgressTransport(
          endpoint,
          identity,
          http,
          transport.documents,
        );
  final outbox = SqliteSyncOutbox(scope: account, db: db);
  final subtitles = FirebaseSubtitleSync(
    uid: account.cloudUid,
    documents: transport.documents,
    objects: transport.objects,
    repository: repository,
    consent: consent,
  );
  final library = FirebaseLibrarySync(
    uid: account.cloudUid,
    documents: transport.documents,
    local: SqliteLibraryChanges(db, account.ownerId),
    consent: consent,
  );
  return FirebaseSyncRuntime(
    uid: account.cloudUid,
    scopeId: account.ownerId,
    isReadOnly: session.isReadOnly,
    hasDueMedia: (now) async =>
        await outbox.hasDueMedia(now) || await library.hasDue(now),
    library: library,
    transport: transport,
    coordinator: session.isReadOnly
        ? null
        : CloudSyncCoordinator(
            scope: account,
            identityProvider: session,
            consentProvider: consent,
            outbox: outbox,
            materials: repository,
            mediaStore: files,
            transport: transport,
            publishSubtitles: subtitles.publish,
          ),
    downloader: CloudMaterialDownloadService(
      scope: account,
      remoteOwnerUid: account.cloudUid,
      identityProvider: session,
      consentProvider: consent,
      transport: transport,
      repository: repository,
      mediaStore: files,
    ),
    consent: consent,
    repository: repository,
    subtitles: subtitles,
    progress: progress,
    progressTransport: progressTransport,
    progressCoordinator: progressTransport == null || session.isReadOnly
        ? null
        : ProgressSyncCoordinator(
            scope: account,
            repository: progress,
            identityProvider: session,
            consentProvider: consent,
            transport: progressTransport,
            clock: DateTime.now,
            random: () => 0.5,
          ),
  );
}, retry: (_, _) => null);

final class _Consent implements SyncConsentProvider {
  const _Consent(this.enabled);

  final Future<bool> Function(String) enabled;

  @override
  Future<bool> isCloudSyncEnabled(String uid) => enabled(uid);
}

/// Recheck the current UID and consent on every remote request.
final class _GuardedSession implements FirebaseIdentitySession {
  const _GuardedSession(this.session, this.consent);
  final FirebaseIdentitySession session;
  final SyncConsentProvider consent;

  @override
  String? get uid => session.uid;

  @override
  bool get isReadOnly => session.isReadOnly;

  @override
  Future<SyncIdentity?> currentIdentity() => session.currentIdentity();

  @override
  Future<String> tokenFor(String expectedUid) async {
    final token = await session.tokenFor(expectedUid);
    if (!await consent.isCloudSyncEnabled(expectedUid)) {
      throw const SyncFailure(
        SyncFailureKind.permissionDenied,
        'consent_required',
      );
    }
    return token;
  }
}
