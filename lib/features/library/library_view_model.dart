import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/account_database_providers.dart';
import '../subtitles/services/subtitle_import_service.dart';
import 'library_dependencies.dart';
import 'material_repository.dart';
import 'services/media_selection_import_service.dart';

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
