import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/files/app_media_store.dart';
import '../../core/sync/sqlite_sync_outbox.dart';
import '../../core/sync/sync_contracts.dart';
import '../auth/platform_social_sign_in.dart';
import '../auth/social_sign_in.dart';
import '../library/data/sqlite_material_repository.dart';
import '../library/library_view_model.dart';
import '../progress/domain/progress_models.dart';
import '../progress/data/sqlite_progress_repository.dart';
import '../progress/services/progress_sync_coordinator.dart';
import 'data/firebase_account_session.dart';
import 'data/firebase_endpoint.dart';
import 'data/firebase_material_transport.dart';
import 'data/firebase_progress_transport.dart';
import 'data/firebase_subtitle_sync.dart';
import 'services/cloud_material_download_service.dart';
import 'services/cloud_sync_coordinator.dart';

final firebaseEndpointProvider = Provider<FirebaseEndpoint?>(
  (ref) => FirebaseEndpoint.fromEnvironment(),
);

final firebaseHttpProvider = Provider<FirebaseHttp>((ref) {
  final client = FirebaseHttp();
  ref.onDispose(client.close);
  return client;
});

final firebaseAuthSessionProvider = Provider<FirebaseAccountSession?>((ref) {
  final endpoint = ref.watch(firebaseEndpointProvider);
  return endpoint == null
      ? null
      : FirebaseAccountSession(endpoint, ref.watch(firebaseHttpProvider));
});

final socialSignInProvider = Provider<SocialSignIn?>((ref) {
  final endpoint = ref.watch(firebaseEndpointProvider);
  if (endpoint == null || endpoint.isEmulator) return null;
  return PlatformSocialSignIn(
    project: endpoint.project,
    apiKey: endpoint.apiKey,
  );
});

typedef FirebaseSessionState = ({String? uid, bool consent});

final firebaseSessionProvider =
    NotifierProvider<FirebaseSessionController, FirebaseSessionState>(
      FirebaseSessionController.new,
    );

final class FirebaseSessionController extends Notifier<FirebaseSessionState> {
  SocialProvider? _signedInProvider;
  bool _changingAccount = false;

  @override
  FirebaseSessionState build() => (uid: null, consent: false);

  Future<void> signIn(String email, String password) async {
    await _signIn((session) => session.signIn(email, password));
  }

  Future<void> signInWithProvider(SocialProvider provider) async {
    final platform = ref.read(socialSignInProvider);
    if (platform == null || !platform.isConfigured(provider)) {
      throw StateError('The sign-in provider is not configured.');
    }
    await _signIn((session) async {
      try {
        return await session.signInWithProvider(
          provider,
          () => platform.signIn(provider),
        );
      } catch (_) {
        try {
          await platform.signOut(provider);
        } catch (_) {
          // Keep the original sign-in error.
        }
        rethrow;
      }
    }, provider: provider);
  }

  Future<void> _signIn(
    Future<String?> Function(FirebaseAccountSession) authenticate, {
    SocialProvider? provider,
  }) async {
    if (_changingAccount || state.uid != null) return;
    final session = ref.read(firebaseAuthSessionProvider);
    if (session == null) throw StateError('Firebase is not configured.');
    _changingAccount = true;
    try {
      final uid = await authenticate(session);
      if (!ref.mounted || uid == null) return;
      _signedInProvider = provider;
      state = (uid: uid, consent: false);
    } finally {
      _changingAccount = false;
    }
  }

  Future<void> signOut() async {
    if (_changingAccount) return;
    final provider = _signedInProvider;
    final platform = ref.read(socialSignInProvider);
    _changingAccount = true;
    ref.read(firebaseAuthSessionProvider)?.signOut();
    _signedInProvider = null;
    state = (uid: null, consent: false);
    try {
      if (provider != null && platform != null) {
        await platform.signOut(provider);
      }
    } finally {
      _changingAccount = false;
    }
  }

  void setConsent(bool enabled) {
    final uid = state.uid;
    if (uid != null) state = (uid: uid, consent: enabled);
  }
}

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
  if (endpoint == null || session?.uid != account.ownerId) return null;
  final http = ref.watch(firebaseHttpProvider);
  final transport = FirebaseMaterialTransport(endpoint, session!, http);
  final database = ref.watch(localDatabaseProvider.future);
  final mediaFiles = ref.watch(accountDatabaseServiceProvider.future);
  final db = await database;
  final files = await mediaFiles;
  final repository = SqliteMaterialRepository(scope: account, database: db);
  final progress = SqliteProgressRepository(scope: account, db: db);
  final progressTransport = endpoint.progressRegion == null
      ? null
      : FirebaseProgressTransport(endpoint, session, http, transport);
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
    subtitles: FirebaseSubtitleSync(
      uid: account.ownerId,
      transport: transport,
      repository: repository,
      consent: consent,
    ),
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

final class FirebaseSyncRuntime {
  const FirebaseSyncRuntime({
    required this.uid,
    required this.transport,
    required this.coordinator,
    required this.downloader,
    required this.consent,
    required this.repository,
    required this.subtitles,
    required this.progress,
    required this.progressTransport,
    required this.progressCoordinator,
  });

  final String uid;
  final FirebaseMaterialTransport transport;
  final CloudSyncCoordinator coordinator;
  final CloudMaterialDownloadService downloader;
  final SyncConsentProvider consent;
  final SqliteMaterialRepository repository;
  final FirebaseSubtitleSync subtitles;
  final SqliteProgressRepository progress;
  final FirebaseProgressTransport? progressTransport;
  final ProgressSyncCoordinator? progressCoordinator;

  Future<List<CloudMaterialMetadata>> refresh() async {
    await _checkConsent();
    final catalog = await transport.listMaterials(uid);
    final local = (await repository.listMaterials())
        .map((item) => item.id)
        .toSet();
    final authored = await repository.uploadedMaterialIds();
    for (final item in catalog.where(
      (item) => local.contains(item.materialId),
    )) {
      if (!authored.contains(item.materialId)) {
        await subtitles.download(item.materialId);
      }
      await _pullProgress(item.materialId);
    }
    return catalog;
  }

  Future<void> download(CloudMaterialMetadata metadata) async {
    await downloader.download(metadata);
    await subtitles.download(metadata.materialId);
    await _pullProgress(metadata.materialId);
  }

  Future<List<ProgressCandidate>> conflicts(String materialId) =>
      progress.unresolvedCandidates(materialId);

  Future<void> resolve(ProgressCandidate candidate, bool useCandidate) async {
    final materialId = candidate.checkpoint.stream.materialId;
    final local = await progress.canonical(materialId);
    if (local == null) return;
    await progress.resolveCandidate(
      candidateId: candidate.id,
      observedCanonicalRevision: local.revision,
      useCandidatePosition: useCandidate,
      resolutionStream: (
        ownerId: uid,
        materialId: materialId,
        deviceId: await progress.deviceId(),
        sessionId: const Uuid().v4(),
      ),
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> _pullProgress(String materialId) async {
    final source = progressTransport;
    if (source == null) return;
    await _checkConsent();
    final progressSnapshot = await source.canonical(uid, materialId);
    await _checkConsent();
    if (progressSnapshot != null) {
      await progress.mergeRemoteCanonical(
        checkpoint: progressSnapshot.checkpoint,
        revision: progressSnapshot.revision,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  Future<void> _checkConsent() async {
    if (!await consent.isCloudSyncEnabled(uid)) {
      throw const SyncFailure(
        SyncFailureKind.permissionDenied,
        'consent_required',
      );
    }
  }

  /// Bound a foreground sync pass and stop at a retry or authorization boundary.
  Future<SyncRunResult> sync() async {
    for (var i = 0; i < 20; i++) {
      final status = await coordinator.runOne();
      if (status == SyncRunResult.idle) {
        for (final materialId in await repository.uploadedMaterialIds()) {
          await subtitles.publish(materialId);
        }
        return _syncProgress();
      }
      if (status != SyncRunResult.uploaded) return status;
    }
    return SyncRunResult.uploaded;
  }

  Future<SyncRunResult> _syncProgress() async {
    final runner = progressCoordinator;
    if (runner == null) return SyncRunResult.idle;
    for (var i = 0; i < 20; i++) {
      switch (await runner.runOne()) {
        case ProgressSyncRunResult.committed:
          continue;
        case ProgressSyncRunResult.idle:
          return SyncRunResult.idle;
        case ProgressSyncRunResult.waitingForConsent:
          return SyncRunResult.waitingForConsent;
        case ProgressSyncRunResult.waitingForAuthentication:
          return SyncRunResult.waitingForAuthentication;
        case ProgressSyncRunResult.retryScheduled:
          return SyncRunResult.retryScheduled;
        case ProgressSyncRunResult.needsAttention:
          return SyncRunResult.needsAttention;
      }
    }
    return SyncRunResult.uploaded;
  }
}

final class _Consent implements SyncConsentProvider {
  const _Consent(this.enabled);

  final bool Function(String) enabled;

  @override
  Future<bool> isCloudSyncEnabled(String uid) async => enabled(uid);
}
