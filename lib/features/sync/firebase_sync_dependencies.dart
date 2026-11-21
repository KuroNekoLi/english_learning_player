import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/files/app_media_store.dart';
import '../../core/sync/sqlite_sync_outbox.dart';
import '../../core/sync/sync_contracts.dart';
import '../auth/firebase_session_controller.dart';
import '../library/data/sqlite_material_repository.dart';
import '../../core/db/account_database_providers.dart';
import '../../core/db/account_database_service.dart';
import '../progress/data/sqlite_progress_repository.dart';
import '../progress/services/progress_sync_coordinator.dart';
import 'data/firebase_material_transport.dart';
import 'data/firebase_progress_transport.dart';
import 'data/firebase_subtitle_sync.dart';
import 'services/cloud_material_download_service.dart';
import 'services/cloud_sync_coordinator.dart';
import 'services/firebase_sync_runtime.dart';

export '../auth/firebase_session_controller.dart';
export 'services/firebase_sync_runtime.dart';

final firebaseSyncRuntimeProvider = FutureProvider<FirebaseSyncRuntime?>((
  ref,
) async {
  final account = ref.watch(accountScopeProvider);
  final endpoint = ref.watch(firebaseEndpointProvider);
  final session = ref.watch(firebaseAuthSessionProvider);
  final consent = _Consent((uid) {
    if (!ref.mounted) return false;
    final state = ref.read(firebaseSessionProvider);
    return state.uid == uid && state.consent;
  });
  if (endpoint == null ||
      !endpoint.isMediaSyncConfigured ||
      session?.uid != account.ownerId) {
    return null;
  }
  final http = ref.watch(firebaseHttpProvider);
  final transport = FirebaseMaterialTransport(endpoint, session!, http);
  final database = ref.watch(localDatabaseProvider.future);
  final mediaFiles = ref.watch(accountDatabaseServiceProvider.future);
  final db = await database;
  final files = await mediaFiles as AccountDatabaseService;
  final repository = SqliteMaterialRepository(scope: account, database: db);
  final progress = SqliteProgressRepository(scope: account, db: db);
  final progressTransport = endpoint.progressRegion == null
      ? null
      : FirebaseProgressTransport(endpoint, session, http, transport.documents);
  final subtitles = FirebaseSubtitleSync(
    uid: account.ownerId,
    documents: transport.documents,
    objects: transport.objects,
    repository: repository,
    consent: consent,
  );
  return FirebaseSyncRuntime(
    uid: account.ownerId,
    transport: transport,
    coordinator: CloudSyncCoordinator(
      scope: account,
      identityProvider: session,
      consentProvider: consent,
      outbox: SqliteSyncOutbox(scope: account, db: db),
      materials: repository,
      mediaFiles: files,
      transport: transport,
      publishSubtitles: subtitles.publish,
    ),
    downloader: CloudMaterialDownloadService(
      scope: account,
      identityProvider: session,
      consentProvider: consent,
      transport: transport,
      repository: repository,
      mediaStore: AppMediaStore(storage: files, scope: account),
    ),
    consent: consent,
    repository: repository,
    subtitles: subtitles,
    progress: progress,
    progressTransport: progressTransport,
    progressCoordinator: progressTransport == null
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

  final bool Function(String) enabled;

  @override
  Future<bool> isCloudSyncEnabled(String uid) async => enabled(uid);
}
