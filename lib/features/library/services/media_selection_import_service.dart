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
    required this._repository,
    required this._audioImporter,
    required this._subtitleImporter,
    this._matcher = const SubtitleFilenameMatcher(),
  });

  final String ownerId;
  final MaterialRepository _repository;
  final AudioImportService _audioImporter;
  final SubtitleImportService _subtitleImporter;
  final SubtitleFilenameMatcher _matcher;

  Future<MediaSelectionImportResult> importFiles(
    List<AudioImportSource> files, {
    void Function(List<MediaFileImportProgress>)? onProgress,
  }) async {
    final audioFiles = files.where(_isAudio).toList();
    final subtitleFiles = files.where(_isSubtitle).toList();
    final fileProgress = audioFiles
        .map((file) => MediaFileImportProgress(sourceName: file.name))
        .toList();
    void publishProgress() => onProgress?.call(List.unmodifiable(fileProgress));
    publishProgress();
    final importedMaterials = <LearningMaterial>[];
    final sourceNamesByMaterial = <String, String>{};
    var audioFailures = 0;
    for (var index = 0; index < audioFiles.length; index++) {
      final file = audioFiles[index];
      fileProgress[index] = fileProgress[index].copyWith(
        status: MediaFileImportStatus.importing,
      );
      publishProgress();
      try {
        final material = (await _audioImporter.importAudio(
          file,
          onProgress: (bytesCopied, totalBytes) {
            fileProgress[index] = fileProgress[index].copyWith(
              bytesCopied: bytesCopied,
              totalBytes: totalBytes,
              status: MediaFileImportStatus.importing,
            );
            publishProgress();
          },
        )).material;
        importedMaterials.add(material);
        sourceNamesByMaterial[material.id] = file.name;
        fileProgress[index] = fileProgress[index].copyWith(
          status: MediaFileImportStatus.completed,
        );
      } catch (_) {
        audioFailures++;
        fileProgress[index] = fileProgress[index].copyWith(
          status: MediaFileImportStatus.failed,
        );
      }
      publishProgress();
    }

    final candidates = <LearningMaterial>{...importedMaterials};
    if (audioFiles.isEmpty && subtitleFiles.isNotEmpty) {
      candidates.addAll(await _repository.listMaterials());
    }
    var subtitlesImported = 0;
    var ambiguousSubtitles = 0;
    var subtitleFailures = 0;
    final matchedSubtitles = <String>{};
    for (final material in candidates) {
      final tracks = await _repository.listSubtitleTracks(material.id);
      final manual = <SubtitleLanguage, String>{
        for (final track in tracks)
          if (track.isSelected &&
              track.selectionMode == SubtitleSelectionMode.manual)
            ?_language(track.languageTag): track.sourceName,
      };
      if (audioFiles.length == 1 && subtitleFiles.length == 1) {
        final file = subtitleFiles.single;
        final fileName = p.basename(file.name);
        try {
          final bytes = await file.openRead().expand((chunk) => chunk).toList();
          if (!_hasSameSource(tracks, fileName, bytes)) {
            final importedTracks = await _subtitleImporter
                .importAutoDetectedBytes(
                  ownerId: ownerId,
                  materialId: material.id,
                  sourceName: fileName,
                  bytes: bytes,
                  manual: true,
                );
            subtitlesImported += importedTracks.length;
          }
          matchedSubtitles.add(fileName);
        } catch (_) {
          subtitleFailures++;
        }
        continue;
      }
      final matches = _matcher.match(
        audioFileName:
            sourceNamesByMaterial[material.id] ?? '${material.title}.m4a',
        subtitleFileNames: subtitleFiles.map((file) => file.name),
        manualSelections: manual,
      );
      final labelledMatches = matches.values.any(
        (match) => match.status != SubtitleMatchStatus.missing,
      );
      final unlabelled = _matcher.matchUnlabelled(
        audioFileName:
            sourceNamesByMaterial[material.id] ?? '${material.title}.m4a',
        subtitleFileNames: subtitleFiles.map((file) => file.name),
      );
      if (!labelledMatches && unlabelled.isNotEmpty) {
        if (unlabelled.length > 1) {
          ambiguousSubtitles++;
          continue;
        }
        final fileName = unlabelled.single;
        final file = subtitleFiles
            .where((candidate) => p.basename(candidate.name) == fileName)
            .firstOrNull;
        if (file != null) {
          try {
            final bytes = await file
                .openRead()
                .expand((chunk) => chunk)
                .toList();
            final existing = _hasSameSource(tracks, fileName, bytes);
            if (!existing) {
              final importedTracks = await _subtitleImporter
                  .importAutoDetectedBytes(
                    ownerId: ownerId,
                    materialId: material.id,
                    sourceName: fileName,
                    bytes: bytes,
                    manual: false,
                  );
              subtitlesImported += importedTracks.length;
            }
            matchedSubtitles.add(fileName);
          } catch (_) {
            subtitleFailures++;
          }
        }
        continue;
      }
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
        final existing = _hasSameSource(tracks, fileName, bytes);
        if (existing) {
          matchedSubtitles.add(fileName);
          continue;
        }
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
          matchedSubtitles.add(fileName);
        } catch (_) {
          subtitleFailures++;
        }
      }
    }
    final unmatchedSubtitles = subtitleFiles
        .where((file) => !matchedSubtitles.contains(p.basename(file.name)))
        .length;

    return MediaSelectionImportResult(
      importedMaterials: importedMaterials,
      subtitlesImported: subtitlesImported,
      ambiguousSubtitles: ambiguousSubtitles,
      audioFailures: audioFailures,
      subtitleFailures: subtitleFailures,
      unmatchedSubtitles: unmatchedSubtitles,
    );
  }

  bool _isAudio(AudioImportSource file) =>
      const ['.m4a', '.mp3'].contains(p.extension(file.name).toLowerCase());

  bool _isSubtitle(AudioImportSource file) =>
      p.extension(file.name).toLowerCase() == '.srt';

  bool _hasSameSource(
    List<SubtitleTrack> tracks,
    String sourceName,
    List<int> bytes,
  ) => tracks.any(
    (track) =>
        (track.sourceName == sourceName ||
            track.sourceName.startsWith('$sourceName ·')) &&
        listEquals(track.originalBytes, bytes),
  );

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

enum MediaFileImportStatus { pending, importing, completed, failed }

final class MediaFileImportProgress {
  const MediaFileImportProgress({
    required this.sourceName,
    this.bytesCopied = 0,
    this.totalBytes,
    this.status = MediaFileImportStatus.pending,
  });

  final String sourceName;
  final int bytesCopied;
  final int? totalBytes;
  final MediaFileImportStatus status;

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    if (status == MediaFileImportStatus.completed) return 1;
    // Leave room for final hashing and persistence after all bytes are read.
    return (bytesCopied / total).clamp(0, 0.95).toDouble();
  }

  MediaFileImportProgress copyWith({
    int? bytesCopied,
    int? totalBytes,
    MediaFileImportStatus? status,
  }) => MediaFileImportProgress(
    sourceName: sourceName,
    bytesCopied: bytesCopied ?? this.bytesCopied,
    totalBytes: totalBytes ?? this.totalBytes,
    status: status ?? this.status,
  );
}

final class MediaSelectionImportResult {
  MediaSelectionImportResult({
    required List<LearningMaterial> importedMaterials,
    required this.subtitlesImported,
    required this.ambiguousSubtitles,
    required this.audioFailures,
    required this.subtitleFailures,
    required this.unmatchedSubtitles,
  }) : importedMaterials = List.unmodifiable(importedMaterials);

  final List<LearningMaterial> importedMaterials;
  final int subtitlesImported;
  final int ambiguousSubtitles;
  final int audioFailures;
  final int subtitleFailures;
  final int unmatchedSubtitles;
}
