import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/account_database_service.dart';
import '../../core/db/account_scope.dart';
import '../../core/files/app_media_store.dart';
import 'data/sqlite_material_repository.dart';
import 'material_repository.dart';
import 'services/audio_file_picker.dart';
import 'services/audio_import_service.dart';

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
