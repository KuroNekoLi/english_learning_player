import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/account_database_providers.dart';
import '../subtitles/services/subtitle_import_service.dart';
import '../subtitles/subtitle_dependencies.dart';
import 'library_dependencies.dart';
import 'material_repository.dart';
import 'services/media_selection_import_service.dart';

final libraryViewModelProvider = FutureProvider<List<LearningMaterial>>((
  ref,
) async {
  final repository = await ref.watch(materialRepositoryProvider.future);
  return repository.listMaterials();
}, retry: (_, _) => null);

final librarySubtitleImportProvider =
    Provider<Future<int?> Function(LearningMaterial)>((ref) {
      return (material) async {
        bool isCurrent() =>
            ref.mounted &&
            ref.read(accountScopeProvider).ownerId == material.ownerId;
        if (!isCurrent()) return null;
        final source = await ref
            .read(subtitleFilePickerProvider)
            .pickSubtitle();
        if (source == null || !isCurrent()) return null;
        final repository = await ref.read(materialRepositoryProvider.future);
        if (!isCurrent()) return null;
        final tracks = await SubtitleImportService(repository: repository)
            .importManualSource(
              material: material,
              source: source,
              isCurrent: isCurrent,
            );
        return isCurrent() ? tracks.length : null;
      };
    });

/// Do not start an import if the account changed while the picker was open.
final libraryImportProvider =
    Provider<
      Future<MediaSelectionImportResult?> Function({
        void Function(List<MediaFileImportProgress>)? onProgress,
      })
    >((ref) {
      return ({onProgress}) async {
        final owner = ref.read(accountScopeProvider).ownerId;
        bool isCurrent() =>
            ref.mounted && ref.read(accountScopeProvider).ownerId == owner;
        final files = await ref.read(audioFilePickerProvider).pickMediaFiles();
        if (files.isEmpty || !isCurrent()) return null;
        final audioImporter = ref.read(audioImportServiceProvider.future);
        final repository = await ref.read(materialRepositoryProvider.future);
        final importer = await audioImporter;
        if (!isCurrent()) return null;
        final result =
            await MediaSelectionImportService(
              ownerId: owner,
              repository: repository,
              audioImporter: importer,
              subtitleImporter: SubtitleImportService(repository: repository),
            ).importFiles(
              files,
              onProgress: (progress) {
                if (isCurrent()) onProgress?.call(progress);
              },
            );
        if (!isCurrent()) return null;
        ref.invalidate(libraryViewModelProvider);
        return result;
      };
    });
