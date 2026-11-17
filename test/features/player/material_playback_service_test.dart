import 'dart:async';
import 'dart:io';

import 'package:english_learning_player/core/db/account_database_service.dart';
import 'package:english_learning_player/core/db/account_scope.dart';
import 'package:english_learning_player/core/files/app_media_store.dart';
import 'package:english_learning_player/features/library/data/sqlite_material_repository.dart';
import 'package:english_learning_player/features/library/domain/audio_import_source.dart';
import 'package:english_learning_player/features/library/services/audio_import_service.dart';
import 'package:english_learning_player/features/player/services/material_playback_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:english_learning_player/features/library/library_view_model.dart';
import 'package:english_learning_player/features/player/player_dependencies.dart';

void main() {
  late Directory root;
  late AccountDatabaseService storage;
  late AccountScope scope;
  late SqliteMaterialRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('elp-player-service-');
    storage = AccountDatabaseService(supportDirectory: root);
    scope = AccountScope('player-owner');
    repository = SqliteMaterialRepository(
      scope: scope,
      database: await storage.open(scope),
    );
  });

  tearDown(() async {
    await repository.close();
    await root.delete(recursive: true);
  });

  test('resolves the app-private media copy for a selected material', () async {
    final importer = AudioImportService(
      repository: repository,
      mediaStore: AppMediaStore(storage: storage, scope: scope),
    );
    final imported = await importer.importAudio(
      AudioImportSource(
        sourceKey: 'source-key',
        name: 'lesson.m4a',
        openRead: () async* {
          yield [1, 2, 3, 4];
        },
      ),
    );
    final asset = await repository.audioAssetForMaterial(imported.material.id);
    expect(asset?.id, imported.material.audioAssetId);

    final bundle = await MaterialPlaybackService(
      repository: repository,
      storage: storage,
      scope: scope,
    ).load(imported.material);

    expect(bundle.source.materialId, imported.material.id);
    expect(bundle.source.uri.scheme, 'file');
    expect(await File.fromUri(bundle.source.uri).exists(), isTrue);
    expect(bundle.subtitleTracks, isEmpty);
    expect(bundle.englishTrack, isNull);
  });

  test(
    'one-shot player read survives async dependencies without a listener',
    () async {
      final pendingRepository = Completer<SqliteMaterialRepository>();
      final container = ProviderContainer(
        overrides: [
          accountScopeProvider.overrideWithValue(scope),
          materialRepositoryProvider.overrideWith(
            (ref) => pendingRepository.future,
          ),
          accountDatabaseServiceProvider.overrideWith((ref) async => storage),
        ],
      );
      addTearDown(container.dispose);
      final loader = container.read(materialPlaybackLoaderProvider.future);
      await container.pump();
      pendingRepository.complete(repository);
      expect(await loader, isA<MaterialPlaybackService>());
    },
  );

  test('rejects a media path outside the account namespace', () {
    expect(
      () => storage.resolveMediaFile(scope, 'media/another-account/a.m4a'),
      throwsFormatException,
    );
    expect(
      () => storage.resolveMediaFile(scope, '/tmp/unrelated.m4a'),
      throwsFormatException,
    );
    expect(
      () => storage.resolveMediaFile(
        scope,
        'media/${scope.storageKey}/../outside.m4a',
      ),
      throwsFormatException,
    );
  });
}
