import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:english_learning_player/core/db/local_database.dart';
import 'package:english_learning_player/features/dictionary/data/firebase_word_bank_sync.dart';
import 'package:english_learning_player/features/dictionary/data/word_bank_repository.dart';
import 'package:english_learning_player/features/dictionary/domain/word.dart';
import 'package:english_learning_player/features/dictionary/domain/original_word_context.dart';
import 'package:english_learning_player/features/library/data/sqlite_library_folder_repository.dart';
import 'package:english_learning_player/features/library/data/sqlite_library_changes.dart';
import 'package:english_learning_player/features/library/material_repository.dart';
import 'package:english_learning_player/features/sync/data/firebase_documents.dart';
import 'package:english_learning_player/features/sync/data/firebase_library_sync.dart';
import 'package:english_learning_player/core/db/account_database_service.dart';
import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/core/files/app_media_store.dart';
import 'package:english_learning_player/core/sync/sqlite_sync_outbox.dart';
import 'package:english_learning_player/core/sync/progress_policy.dart';
import 'package:english_learning_player/core/sync/sync_contracts.dart';
import 'package:english_learning_player/features/auth/social_sign_in.dart';
import 'package:english_learning_player/features/library/data/sqlite_material_repository.dart';
import 'package:english_learning_player/features/library/domain/audio_import_source.dart';
import 'package:english_learning_player/features/library/services/audio_import_service.dart';
import 'package:english_learning_player/features/progress/data/sqlite_progress_repository.dart';
import 'package:english_learning_player/features/progress/services/progress_sync_coordinator.dart';
import 'package:english_learning_player/features/sync/data/firebase_progress_transport.dart';
import 'package:english_learning_player/features/sync/data/firebase_subtitle_sync.dart';
import 'package:english_learning_player/features/subtitles/services/subtitle_import_service.dart';
import 'package:english_learning_player/features/auth/data/firebase_account_session.dart';
import 'package:english_learning_player/core/firebase/firebase_endpoint.dart';
import 'package:english_learning_player/features/sync/data/firebase_material_transport.dart';
import 'package:english_learning_player/features/sync/services/cloud_material_download_service.dart';
import 'package:english_learning_player/features/sync/services/cloud_sync_coordinator.dart';
import 'package:english_learning_player/core/db/account_database_providers.dart';
import 'package:english_learning_player/features/sync/firebase_sync_dependencies.dart';
import 'package:english_learning_player/features/sync/firebase_sync_view_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_cloud_sync.dart';

void main() {
  test('Firebase emulator: word bank converges across devices and preserves a removal', () async {
    final endpoint = FirebaseEndpoint(
      project: 'demo-english-learning-player',
      bucket: 'demo-english-learning-player.appspot.com',
      apiKey: 'fake-api-key',
      emulatorHost: '127.0.0.1',
    );
    final http = FirebaseHttp();
    addTearDown(http.close);
    final first = FirebaseAccountSession(endpoint, http);
    final second = FirebaseAccountSession(endpoint, http);
    final credential = ProviderIdToken(
      jsonEncode({
        'sub': 'word-bank-${DateTime.now().microsecondsSinceEpoch}',
        'email': 'word-bank@example.test',
        'email_verified': true,
      }),
    );
    final uid = (await first.signInWithProvider(
      SocialProvider.google,
      () async => credential,
    ))!;
    expect(
      await second.signInWithProvider(
        SocialProvider.google,
        () async => credential,
      ),
      uid,
    );
    final dbA = LocalDatabase(NativeDatabase.memory());
    final dbB = LocalDatabase(NativeDatabase.memory());
    addTearDown(dbA.close);
    addTearDown(dbB.close);
    final a = WordBankRepository(dbA);
    final b = WordBankRepository(dbB);
    FirebaseWordBankSync sync(
      WordBankRepository local,
      FirebaseAccountSession session,
    ) => FirebaseWordBankSync(
      uid: uid,
      documents: FirebaseDocuments(endpoint, session, http),
      local: local,
      consent: FakeSyncConsentProvider(),
      readOnly: false,
    );
    final syncA = sync(a, first);
    final syncB = sync(b, second);
    const word = Word(
      word: 'refine',
      pronunciations: WordPronunciations(),
      entries: [],
    );
    const originalContext = OriginalWordContext(
      materialId: 'lesson-1',
      materialTitle: 'Example lesson',
      startMs: 45000,
      endMs: 48000,
      english: 'It looks murky.',
      translations: ['看起來很模糊。'],
    );
    await a.save(word, context: originalContext);
    expect((await a.list()).single.word.word, 'refine');
    expect(await b.list(), isEmpty);
    await syncA.run(refresh: false);
    expect(await a.pending(), isEmpty);
    expect(await syncB.run(refresh: true), isTrue);
    expect((await b.list()).single.word.word, 'refine');
    expect((await b.list()).single.originalContext?.materialId, 'lesson-1');
    expect((await b.list()).single.originalContext?.english, 'It looks murky.');
    await a.remove('refine');
    await b.save(
      word,
    ); // Another edit still based on the first remote revision.
    await syncA.run(refresh: false);
    await syncB.run(refresh: true);
    expect(await b.list(), isEmpty);
    expect(await b.pending(), isEmpty);
    await syncA.run(refresh: true);
    expect(await a.list(), isEmpty);
    await b.save(word);
    await syncB.run(refresh: false);
    await syncA.run(refresh: true);
    expect((await a.list()).single.word.word, 'refine');
  }, skip: Platform.environment['ELP_RUN_FIREBASE_TEST'] != '1');

  test('Firebase emulator: Google and Apple exchange mock credentials for isolated UIDs', () async {
    final http = FirebaseHttp();
    addTearDown(http.close);
    final endpoint = FirebaseEndpoint(
      project: 'demo-english-learning-player',
      bucket: 'demo-english-learning-player.appspot.com',
      apiKey: 'fake-api-key',
      emulatorHost: '127.0.0.1',
    );
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final uids = <String, String>{};
    for (final provider in SocialProvider.values) {
      final session = FirebaseAccountSession(endpoint, http);
      final mockCredential = ProviderIdToken(
        jsonEncode({
          'sub': '${provider.name}-$stamp',
          'email': '${provider.name}-$stamp@example.test',
          'email_verified': true,
        }),
        rawNonce: provider == SocialProvider.apple
            ? 'emulator-only-nonce'
            : null,
      );
      Future<SocialSignInResult?> authorize() async => mockCredential;
      final uid = await session.signInWithProvider(provider, authorize);
      expect(uid, isNotNull);
      expect(await session.tokenFor(uid!), isNotEmpty);
      uids[provider.name] = uid;
      session.signOut();
      await expectLater(session.tokenFor(uid), throwsA(isA<SyncFailure>()));
      expect(await session.signInWithProvider(provider, authorize), uid);
    }
    expect(uids.values.toSet(), hasLength(2));
  }, skip: Platform.environment['ELP_RUN_FIREBASE_TEST'] != '1');

  test(
    'Firebase emulator: two authenticated clients upload, download, and isolate accounts',
    () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final root = await Directory.systemTemp.createTemp('elp-firebase-');
      addTearDown(() => root.delete(recursive: true));
      final http = FirebaseHttp();
      addTearDown(http.close);
      final endpoint = FirebaseEndpoint(
        project: 'demo-english-learning-player',
        bucket: 'demo-english-learning-player.appspot.com',
        apiKey: 'fake-api-key',
        emulatorHost: '127.0.0.1',
        progressRegion: 'us-central1',
      );
      final stamp = DateTime.now().microsecondsSinceEpoch;
      const password = 'emulator-fixture-only';

      Future<String> register(String email) async {
        final response = await http.send(
          'POST',
          endpoint.auth('signUp'),
          contentType: 'application/json',
          bytes: FirebaseHttp.encode({
            'email': email,
            'password': password,
            'returnSecureToken': true,
          }),
        );
        await http.requireSuccess(response);
        return (await http.json(response))['localId'] as String;
      }

      final ownerEmail =
          Platform.environment['ELP_SMOKE_EMAIL'] ??
          'stage3-$stamp@example.test';
      final uid = await register(ownerEmail);
      final sender = FirebaseAccountSession(endpoint, http);
      final receiver = FirebaseAccountSession(endpoint, http);
      expect(await sender.signIn(ownerEmail, password), uid);
      expect(await receiver.signIn(ownerEmail, password), uid);
      final scope = AccountScope(uid);
      final consent = FakeSyncConsentProvider();
      final senderFiles = AccountDatabaseService(
        supportDirectory: Directory('${root.path}/sender'),
      );
      final receiverFiles = AccountDatabaseService(
        supportDirectory: Directory('${root.path}/receiver'),
      );
      final senderDb = await senderFiles.open(scope);
      final receiverDb = await receiverFiles.open(scope);
      addTearDown(senderDb.close);
      addTearDown(receiverDb.close);
      final senderRepository = SqliteMaterialRepository(
        scope: scope,
        database: senderDb,
      );
      final receiverRepository = SqliteMaterialRepository(
        scope: scope,
        database: receiverDb,
      );
      final importer = AudioImportService(
        repository: senderRepository,
        mediaStore: AppMediaStore(storage: senderFiles, scope: scope),
      );
      final smokeMedia = Platform.environment['ELP_SMOKE_M4A'];
      final bytes = smokeMedia == null
          ? [1, 5, 9, 23]
          : await File(smokeMedia).readAsBytes();
      final first = await importer.importAudio(
        AudioImportSource(
          sourceKey: 'one',
          name: 'firebase-lesson.m4a',
          openRead: () => Stream.value(bytes),
        ),
      );
      final second = await importer.importAudio(
        AudioImportSource(
          sourceKey: 'two',
          name: 'firebase-duplicate.m4a',
          openRead: () => Stream.value(bytes),
        ),
      );
      final sending = FirebaseMaterialTransport(endpoint, sender, http);
      final publishingSubtitles = FirebaseSubtitleSync(
        uid: uid,
        documents: sending.documents,
        objects: sending.objects,
        repository: senderRepository,
        consent: consent,
      );
      final senderOutbox = SqliteSyncOutbox(scope: scope, db: senderDb);
      final coordinator = CloudSyncCoordinator(
        scope: scope,
        identityProvider: sender,
        consentProvider: consent,
        outbox: senderOutbox,
        materials: senderRepository,
        mediaStore: AppMediaStore(storage: senderFiles, scope: scope),
        transport: sending,
        publishSubtitles: publishingSubtitles.publish,
      );
      expect(
        await coordinator.runOne(),
        SyncRunResult.uploaded,
        reason: 'Storage write, read-back and Firestore publish',
      );
      expect(
        await coordinator.runOne(),
        SyncRunResult.uploaded,
        reason: 'Second material reuses an immutable remote asset',
      );
      final receiving = FirebaseMaterialTransport(endpoint, receiver, http);
      final catalog = await receiving.listMaterials(uid);
      expect(
        catalog.map((entry) => entry.materialId),
        unorderedEquals([first.material.id, second.material.id]),
      );
      final receiverDownloader = CloudMaterialDownloadService(
        scope: scope,
        identityProvider: receiver,
        consentProvider: consent,
        transport: receiving,
        repository: receiverRepository,
        mediaStore: AppMediaStore(storage: receiverFiles, scope: scope),
      );
      final downloaded = await receiverDownloader.download(catalog.first);
      final asset = (await receiverRepository.audioAssetForMaterial(
        downloaded.id,
      ))!;
      expect(
        await receiverFiles
            .resolveMediaFile(scope, asset.relativePath)
            .readAsBytes(),
        bytes,
      );
      expect(
        await receiverDb.customSelect('SELECT * FROM sync_outbox').get(),
        isEmpty,
      );

      final subtitleImport = SubtitleImportService(
        repository: senderRepository,
      );
      final bilingualBytes = utf8.encode(
        '1\n00:00:00,300 --> 00:00:03,500\nCloud sentence\n雲端字幕\n',
      );
      final imported = await subtitleImport.importBilingualBytes(
        ownerId: uid,
        materialId: downloaded.id,
        sourceName: 'synthetic-bilingual.srt',
        bytes: bilingualBytes,
        manual: true,
        offsetMs: 100,
      );
      expect(imported, hasLength(2));
      final librarySending = FirebaseLibrarySync(
        uid: uid,
        documents: sending.documents,
        local: SqliteLibraryChanges(senderDb, uid),
        consent: consent,
      );
      await SqliteLibraryFolderRepository(
        scope,
        senderDb,
      ).createFolder('Synced empty folder');
      final sendingRuntime = FirebaseSyncRuntime(
        library: librarySending,
        uid: uid,
        hasDueMedia: (now) async =>
            await senderOutbox.hasDueMedia(now) ||
            await librarySending.hasDue(now),
        transport: sending,
        coordinator: coordinator,
        downloader: CloudMaterialDownloadService(
          scope: scope,
          identityProvider: sender,
          consentProvider: consent,
          transport: sending,
          repository: senderRepository,
          mediaStore: AppMediaStore(storage: senderFiles, scope: scope),
        ),
        consent: consent,
        repository: senderRepository,
        subtitles: publishingSubtitles,
        progress: SqliteProgressRepository(scope: scope, db: senderDb),
        progressTransport: null,
        progressCoordinator: null,
      );
      final container = ProviderContainer(
        overrides: [
          accountScopeProvider.overrideWithValue(scope),
          firebaseSyncRuntimeProvider.overrideWith(
            (ref) async => sendingRuntime,
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(firebaseSyncViewModelProvider, (_, _) {});
      final sync = container.read(firebaseSyncViewModelProvider.notifier);
      expect(await senderOutbox.hasDueMedia(DateTime.now()), isTrue);
      consent.enabled = false;
      await sync.syncAutomatically(refreshCatalog: false);
      expect(await senderOutbox.hasDueMedia(DateTime.now()), isTrue);
      consent.enabled = true;
      await sync.syncAutomatically(refreshCatalog: false);
      expect(await senderOutbox.hasDueMedia(DateTime.now()), isFalse);
      final subtitleOperation = await senderDb
          .customSelect(
            "SELECT state FROM sync_outbox WHERE entity_type = 'subtitle'",
          )
          .getSingle();
      expect(subtitleOperation.read<String>('state'), 'completed');
      final receivingSubtitles = FirebaseSubtitleSync(
        uid: uid,
        documents: receiving.documents,
        objects: receiving.objects,
        repository: receiverRepository,
        consent: consent,
      );
      final receiverOutbox = SqliteSyncOutbox(scope: scope, db: receiverDb);
      final receiverRuntime = FirebaseSyncRuntime(
        uid: uid,
        library: FirebaseLibrarySync(
          uid: uid,
          documents: receiving.documents,
          local: SqliteLibraryChanges(receiverDb, uid),
          consent: consent,
        ),
        hasDueMedia: receiverOutbox.hasDueMedia,
        transport: receiving,
        coordinator: CloudSyncCoordinator(
          scope: scope,
          identityProvider: receiver,
          consentProvider: consent,
          outbox: receiverOutbox,
          materials: receiverRepository,
          mediaStore: AppMediaStore(storage: receiverFiles, scope: scope),
          transport: receiving,
        ),
        downloader: receiverDownloader,
        consent: consent,
        repository: receiverRepository,
        subtitles: receivingSubtitles,
        progress: SqliteProgressRepository(scope: scope, db: receiverDb),
        progressTransport: null,
        progressCoordinator: null,
      );
      expect(
        await receiverRepository.listSubtitleTracks(downloaded.id),
        isEmpty,
      );
      expect(await receiverRuntime.refresh(), hasLength(2));
      expect(
        (await SqliteLibraryFolderRepository(
          scope,
          receiverDb,
        ).listFolders()).single.title,
        'Synced empty folder',
      );
      await receivingSubtitles.download(downloaded.id);
      await receivingSubtitles.download(downloaded.id);
      expect(
        await receiverDb.customSelect('SELECT * FROM sync_outbox').get(),
        isEmpty,
      );
      final subtitleTracks = await receiverRepository.listSubtitleTracks(
        downloaded.id,
      );
      expect(subtitleTracks, hasLength(2));
      expect(
        subtitleTracks.map((track) => track.languageTag),
        unorderedEquals(['en', 'zh-tw']),
      );
      expect(
        subtitleTracks.every(
          (track) => track.isSelected && track.offsetMs == 100,
        ),
        isTrue,
      );

      expect(
        subtitleTracks
            .singleWhere((track) => track.languageTag == 'en')
            .cues
            .single
            .text,
        'Cloud sentence',
      );
      expect(
        subtitleTracks
            .singleWhere((track) => track.languageTag == 'zh-tw')
            .cues
            .single
            .text,
        '雲端字幕',
      );
      expect(
        subtitleTracks.every(
          (track) => track.originalBytes.length == bilingualBytes.length,
        ),
        isTrue,
      );

      final macProgress = SqliteProgressRepository(scope: scope, db: senderDb);
      final phoneProgress = SqliteProgressRepository(
        scope: scope,
        db: receiverDb,
      );
      final macTransport = FirebaseProgressTransport(
        endpoint,
        sender,
        http,
        sending.documents,
      );
      final phoneTransport = FirebaseProgressTransport(
        endpoint,
        receiver,
        http,
        receiving.documents,
      );
      final now = DateTime.now().toUtc();
      ProgressStream stream(String device) => (
        ownerId: uid,
        materialId: downloaded.id,
        deviceId: device,
        sessionId: 'session',
      );
      await macProgress.recordCheckpoint(
        stream: stream('mac'),
        positionMs: 1800,
        state: CheckpointState.paused,
        nowMs: now.millisecondsSinceEpoch,
      );
      await phoneProgress.recordCheckpoint(
        stream: stream('phone'),
        positionMs: 2400,
        state: CheckpointState.paused,
        nowMs: now.millisecondsSinceEpoch,
      );
      Future<ProgressSyncRunResult> syncProgress(
        SqliteProgressRepository progress,
        FirebaseAccountSession account,
        FirebaseProgressTransport transport,
      ) => ProgressSyncCoordinator(
        scope: scope,
        repository: progress,
        identityProvider: account,
        consentProvider: consent,
        transport: transport,
        clock: () => now,
        random: () => 0.5,
      ).runOne();

      expect(
        await syncProgress(macProgress, sender, macTransport),
        ProgressSyncRunResult.committed,
      );
      expect(
        await syncProgress(phoneProgress, receiver, phoneTransport),
        ProgressSyncRunResult.committed,
      );
      final candidates = await phoneProgress.unresolvedCandidates(
        downloaded.id,
      );
      expect(candidates.single.checkpoint.positionMs, 2400);
      final confirmed = (await phoneTransport.canonical(uid, downloaded.id))!;
      expect(confirmed.checkpoint.positionMs, 1800);
      expect(confirmed.revision, 1);
      await phoneProgress.resolveCandidate(
        candidateId: candidates.single.id,
        observedCanonicalRevision: 1,
        useCandidatePosition: true,
        resolutionStream: stream('phone'),
        nowMs: now.millisecondsSinceEpoch,
      );
      expect(
        await syncProgress(phoneProgress, receiver, phoneTransport),
        ProgressSyncRunResult.committed,
      );
      expect(
        (await macTransport.canonical(
          uid,
          downloaded.id,
        ))?.checkpoint.positionMs,
        2400,
      );
      expect(await phoneProgress.unresolvedCandidates(downloaded.id), isEmpty);

      final otherEmail = 'other-$stamp@example.test';
      final otherUid = await register(otherEmail);
      await receiver.signIn(otherEmail, password);
      expect(await receiving.listMaterials(otherUid), isEmpty);
      await expectLater(
        receiving.listMaterials(uid),
        throwsA(isA<SyncFailure>()),
      );
    },
    skip: Platform.environment['ELP_RUN_FIREBASE_TEST'] != '1'
        ? 'Run with Auth, Firestore and Storage Firebase Emulators.'
        : false,
  );
  test('Firebase emulator: two clients converge on folders, placements and deletion', () async {
    final endpoint = FirebaseEndpoint(
      project: 'demo-english-learning-player',
      bucket: 'demo-english-learning-player.appspot.com',
      apiKey: 'fake-api-key',
      emulatorHost: '127.0.0.1',
    );
    final http = FirebaseHttp();
    addTearDown(http.close);
    final first = FirebaseAccountSession(endpoint, http);
    final second = FirebaseAccountSession(endpoint, http);
    Future<SocialSignInResult?> authorize() async => ProviderIdToken(
      jsonEncode({
        'sub': 'folder-test-${DateTime.now().microsecondsSinceEpoch}',
        'email': 'folders@example.test',
        'email_verified': true,
      }),
    );
    final credential = await authorize();
    final uid = (await first.signInWithProvider(
      SocialProvider.google,
      () async => credential,
    ))!;
    expect(
      await second.signInWithProvider(
        SocialProvider.google,
        () async => credential,
      ),
      uid,
    );
    final scope = AccountScope(uid);
    final a = LocalDatabase(NativeDatabase.memory());
    final b = LocalDatabase(NativeDatabase.memory());
    addTearDown(a.close);
    addTearDown(b.close);
    final folderA = SqliteLibraryFolderRepository(scope, a);
    final folderB = SqliteLibraryFolderRepository(scope, b);
    final syncA = FirebaseLibrarySync(
      uid: uid,
      documents: FirebaseDocuments(endpoint, first, http),
      local: SqliteLibraryChanges(a, uid),
      consent: FakeSyncConsentProvider(),
    );
    final syncB = FirebaseLibrarySync(
      uid: uid,
      documents: FirebaseDocuments(endpoint, second, http),
      local: SqliteLibraryChanges(b, uid),
      consent: FakeSyncConsentProvider(),
    );
    await folderA.createFolder('Parent');
    await folderA.createFolder('Child');
    final [child, parent] = await folderA.listFolders();
    await folderA.moveFolder(child.id, parent.id);
    final materialA = SqliteMaterialRepository(scope: scope, database: a);
    final materialB = SqliteMaterialRepository(scope: scope, database: b);
    const asset = StoredAudioAsset(
      id: 'asset',
      sha256: 'hash',
      byteLength: 1,
      mediaType: 'audio/mpeg',
      relativePath: 'asset.mp3',
    );
    await materialA.insertAudio(
      asset: asset,
      sourceKey: 'asset',
      title: 'Original',
      materialId: 'lesson',
      createdAt: DateTime.utc(2026),
    );
    await folderA.moveMaterial('lesson', child.id);
    await folderA.renameMaterial('lesson', 'Updated');
    expect(await syncA.push(), isTrue);
    await syncB.pull();
    expect((await folderB.listFolders()).first.parentId, parent.id);
    expect(await folderB.materialIds(child.id), isEmpty);

    await materialB.cacheCloudAudio(
      materialId: 'lesson',
      asset: asset,
      cachedAt: DateTime.utc(2026),
      title: 'Original',
    );
    expect(await folderB.materialIds(child.id), {'lesson'});
    expect((await materialB.listMaterials()).single.title, 'Updated');

    // Two offline changes to the same field use the stable version ordering.
    await folderA.renameFolder(child.id, 'Child A');
    await folderB.renameFolder(child.id, 'Child B');
    await Future.wait([syncA.push(), syncB.push()]);
    await syncA.pull();
    await syncB.pull();
    expect(
      (await folderA.listFolders()).first.title,
      (await folderB.listFolders()).first.title,
    );

    await folderB.deleteFolder(child.id);
    await folderB.deleteMaterial('lesson');
    await syncB.push();
    await syncA.pull();
    expect((await folderA.listFolders()).single.id, parent.id);
    expect(await materialA.listMaterials(), isEmpty);
    expect(await syncA.local.materialDeleted('lesson'), isTrue);
  }, skip: Platform.environment['ELP_RUN_FIREBASE_TEST'] != '1');
}
