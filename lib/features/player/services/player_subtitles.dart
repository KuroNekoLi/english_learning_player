import '../../library/domain/audio_import_source.dart';
import '../../library/material_repository.dart';
import '../../subtitles/domain/subtitle_models.dart';
import '../../subtitles/services/subtitle_import_service.dart';

final class PlayerSubtitles {
  const PlayerSubtitles(this.repository);

  final MaterialRepository repository;

  Future<List<SubtitleTrack>> import(
    LearningMaterial material,
    AudioImportSource source,
    String languageTag,
  ) async {
    final bytes = await source.openRead().expand((chunk) => chunk).toList();
    final importer = SubtitleImportService(repository: repository);
    final bilingual = await importer.importBilingualBytes(
      ownerId: material.ownerId,
      materialId: material.id,
      sourceName: source.name,
      bytes: bytes,
      manual: true,
    );
    if (bilingual == null) {
      await importer.importBytes(
        ownerId: material.ownerId,
        materialId: material.id,
        languageTag: languageTag,
        sourceName: source.name,
        bytes: bytes,
        manual: true,
      );
    }
    return repository.listSubtitleTracks(material.id);
  }

  Future<List<SubtitleTrack>> save(
    SubtitleTrack track, {
    required bool manual,
  }) async {
    await repository.saveSubtitleTrack(track, manual: manual);
    return repository.listSubtitleTracks(track.materialId);
  }
}
