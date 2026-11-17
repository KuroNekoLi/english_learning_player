import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';

import '../../subtitles/domain/subtitle_filename_matcher.dart';
import '../../subtitles/domain/subtitle_models.dart';
import '../../subtitles/services/subtitle_import_service.dart';
import '../domain/audio_import_source.dart';
import '../material_repository.dart';
import 'audio_import_service.dart';

final class MediaSelectionImportService {
  MediaSelectionImportService({
    required this.ownerId,
    required MaterialRepository repository,
    required AudioImportService audioImporter,
    required SubtitleImportService subtitleImporter,
    SubtitleFilenameMatcher matcher = const SubtitleFilenameMatcher(),
  }) : _repository = repository,
       _audioImporter = audioImporter,
       _subtitleImporter = subtitleImporter,
       _matcher = matcher;

  final String ownerId;
  final MaterialRepository _repository;
  final AudioImportService _audioImporter;
  final SubtitleImportService _subtitleImporter;
  final SubtitleFilenameMatcher _matcher;

  Future<MediaSelectionImportResult> importFiles(
    List<AudioImportSource> files,
  ) async {
    final audioFiles = files.where(_isAudio).toList();
    final subtitleFiles = files.where(_isSubtitle).toList();
    final importedMaterials = <LearningMaterial>[];
    var audioFailures = 0;
    for (final file in audioFiles) {
      try {
        importedMaterials.add(
          (await _audioImporter.importAudio(file)).material,
        );
      } catch (_) {
        audioFailures++;
      }
    }

    final candidates = <LearningMaterial>{...importedMaterials};
    if (audioFiles.isEmpty && subtitleFiles.isNotEmpty) {
      candidates.addAll(await _repository.listMaterials());
    }
    var subtitlesImported = 0;
    var ambiguousSubtitles = 0;
    var subtitleFailures = 0;
    for (final material in candidates) {
      final tracks = await _repository.listSubtitleTracks(material.id);
      final manual = <SubtitleLanguage, String>{
        for (final track in tracks)
          if (track.isSelected &&
              track.selectionMode == SubtitleSelectionMode.manual)
            if (_language(track.languageTag) case final language?)
              language: track.sourceName,
      };
      final matches = _matcher.match(
        audioFileName: '${material.title}.m4a',
        subtitleFileNames: subtitleFiles.map((file) => file.name),
        manualSelections: manual,
      );
      for (final language in SubtitleLanguage.values) {
        final match = matches[language]!;
        if (match.status == SubtitleMatchStatus.ambiguous) {
          ambiguousSubtitles++;
          continue;
        }
        final fileName = match.selectedSourceName;
        final file = subtitleFiles
            .where((candidate) => p.basename(candidate.name) == fileName)
            .firstOrNull;
        if (file == null || fileName == null) continue;
        final bytes = await file.openRead().expand((chunk) => chunk).toList();
        final existing = tracks.any(
          (track) =>
              track.sourceName == fileName &&
              listEquals(track.originalBytes, bytes),
        );
        if (existing) continue;
        try {
          await _subtitleImporter.importBytes(
            ownerId: ownerId,
            materialId: material.id,
            languageTag: language == SubtitleLanguage.english ? 'en' : 'zh-TW',
            sourceName: fileName,
            bytes: bytes,
            manual: false,
          );
          subtitlesImported++;
        } catch (_) {
          subtitleFailures++;
        }
      }
    }

    return MediaSelectionImportResult(
      importedMaterials: importedMaterials,
      subtitlesImported: subtitlesImported,
      ambiguousSubtitles: ambiguousSubtitles,
      audioFailures: audioFailures,
      subtitleFailures: subtitleFailures,
    );
  }

  bool _isAudio(AudioImportSource file) =>
      const ['.m4a', '.mp3'].contains(p.extension(file.name).toLowerCase());

  bool _isSubtitle(AudioImportSource file) =>
      p.extension(file.name).toLowerCase() == '.srt';

  SubtitleLanguage? _language(String languageTag) {
    final language = languageTag.toLowerCase();
    if (language == 'en' || language.startsWith('en-')) {
      return SubtitleLanguage.english;
    }
    if (language == 'zh' || language.startsWith('zh-')) {
      return SubtitleLanguage.chinese;
    }
    return null;
  }
}

final class MediaSelectionImportResult {
  MediaSelectionImportResult({
    required List<LearningMaterial> importedMaterials,
    required this.subtitlesImported,
    required this.ambiguousSubtitles,
    required this.audioFailures,
    required this.subtitleFailures,
  }) : importedMaterials = List.unmodifiable(importedMaterials);

  final List<LearningMaterial> importedMaterials;
  final int subtitlesImported;
  final int ambiguousSubtitles;
  final int audioFailures;
  final int subtitleFailures;
}
