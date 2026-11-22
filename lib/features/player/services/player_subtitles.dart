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
  ) async {
    final importer = SubtitleImportService(repository: repository);
    await importer.importManualSource(material: material, source: source);
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
