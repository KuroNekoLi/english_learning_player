import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/account_database_providers.dart';
import '../../core/files/media_store.dart';
import '../../core/files/media_store_factory.dart';
import 'data/sqlite_material_repository.dart';
import 'material_repository.dart';
import 'services/audio_file_picker.dart';
import 'services/audio_file_picker_factory.dart';
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
  (ref) => createAudioFilePicker(),
);

final mediaStoreProvider = FutureProvider<MediaStore>((ref) async {
  final scope = ref.watch(accountScopeProvider);
  final opener = await ref.watch(accountDatabaseServiceProvider.future);
  return createMediaStore(opener, scope);
});

final audioImportServiceProvider = FutureProvider<AudioImportService>((
  ref,
) async {
  final repository = ref.watch(materialRepositoryProvider.future);
  return AudioImportService(
    repository: await repository,
    mediaStore: await ref.watch(mediaStoreProvider.future),
  );
});
