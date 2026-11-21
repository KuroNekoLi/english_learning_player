import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/account_database_providers.dart';
import '../../core/files/app_media_store.dart';
import 'data/sqlite_material_repository.dart';
import 'material_repository.dart';
import 'services/audio_file_picker.dart';
import 'services/audio_import_service.dart';

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
