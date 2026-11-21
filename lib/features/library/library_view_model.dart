import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/account_database_service.dart';
import '../../core/db/account_scope.dart';
import '../../core/files/app_media_store.dart';
import 'data/sqlite_material_repository.dart';
import 'material_repository.dart';
import 'services/audio_file_picker.dart';
import 'services/audio_import_service.dart';
import '../subtitles/services/subtitle_import_service.dart';
import 'services/media_selection_import_service.dart';

final accountScopeProvider = Provider<AccountScope>(
  (ref) => AccountScope('local-default'),
);

final accountDatabaseServiceProvider = FutureProvider<AccountDatabaseService>(
  (ref) => AccountDatabaseService.createForApplication(),
);

final localDatabaseProvider = FutureProvider.autoDispose((ref) async {
  final scope = ref.watch(accountScopeProvider);
  final storage = ref.watch(accountDatabaseServiceProvider.future);
  final service = await storage;
  final database = await service.open(scope);
  if (!ref.mounted) {
    await database.close();
    throw StateError('The selected account has changed.');
  }
  ref.onDispose(() => unawaited(database.close()));
  return database;
});

final materialRepositoryProvider = FutureProvider<MaterialRepository>((
  ref,
) async {
  final scope = ref.watch(accountScopeProvider);
  return SqliteMaterialRepository(
    scope: scope,
    database: await ref.watch(localDatabaseProvider.future),
  );
});

final audioFilePickerProvider = Provider<AudioFilePicker>(
  (ref) => NativeAudioFilePicker(),
);

final audioImportServiceProvider = FutureProvider<AudioImportService>((
  ref,
) async {
  final scope = ref.watch(accountScopeProvider);
  final storage = ref.watch(accountDatabaseServiceProvider.future);
  final repository = ref.watch(materialRepositoryProvider.future);
  return AudioImportService(
    repository: await repository,
    mediaStore: AppMediaStore(storage: await storage, scope: scope),
  );
});

final libraryViewModelProvider = FutureProvider<List<LearningMaterial>>((
  ref,
) async {
  final repository = await ref.watch(materialRepositoryProvider.future);
  return repository.listMaterials();
}, retry: (_, _) => null);

/// Do not start an import if the account changed while the picker was open.
final libraryImportProvider =
    Provider<Future<MediaSelectionImportResult?> Function()>((ref) {
      return () async {
        final owner = ref.read(accountScopeProvider).ownerId;
        bool isCurrent() =>
            ref.mounted && ref.read(accountScopeProvider).ownerId == owner;
        final files = await ref.read(audioFilePickerProvider).pickMediaFiles();
        if (files.isEmpty || !isCurrent()) return null;
        final audioImporter = ref.read(audioImportServiceProvider.future);
        final repository = await ref.read(materialRepositoryProvider.future);
        final importer = await audioImporter;
        if (!isCurrent()) return null;
        final result = await MediaSelectionImportService(
          ownerId: owner,
          repository: repository,
          audioImporter: importer,
          subtitleImporter: SubtitleImportService(repository: repository),
        ).importFiles(files);
        if (!isCurrent()) return null;
        ref.invalidate(libraryViewModelProvider);
        return result;
      };
    });
