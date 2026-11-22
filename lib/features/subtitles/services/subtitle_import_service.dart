import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../library/domain/audio_import_source.dart';
import '../../library/material_repository.dart';
import '../domain/bilingual_subtitle_splitter.dart';
import '../domain/subtitle_language_detector.dart';
import '../domain/srt_parser.dart';
import '../domain/subtitle_models.dart';

final class SubtitleImportService {
  SubtitleImportService({
    required MaterialRepository repository,
    SrtParser parser = const SrtParser(),
    SubtitleLanguageDetector languageDetector =
        const SubtitleLanguageDetector(),
    Uuid uuid = const Uuid(),
  }) : _repository = repository,
       _parser = parser,
       _languageDetector = languageDetector,
       _uuid = uuid;

  final MaterialRepository _repository;
  final SrtParser _parser;
  final SubtitleLanguageDetector _languageDetector;
  final Uuid _uuid;

  Future<List<SubtitleTrack>> importManualSource({
    required LearningMaterial material,
    required AudioImportSource source,
    bool Function()? isCurrent,
  }) async {
    if (p.extension(source.name).toLowerCase() != '.srt') {
      throw const FormatException('Expected an SRT file.');
    }
    final bytes = await source.openRead().expand((chunk) => chunk).toList();
    if (isCurrent?.call() == false) return const [];
    return importAutoDetectedBytes(
      ownerId: material.ownerId,
      materialId: material.id,
      sourceName: source.name,
      bytes: bytes,
      manual: true,
    );
  }

  Future<SubtitleImportResult> importBytes({
    required String ownerId,
    required String materialId,
    required String languageTag,
    required String sourceName,
    required List<int> bytes,
    required bool manual,
    int revision = 1,
    int offsetMs = 0,
  }) async {
    if (revision < 1) throw ArgumentError.value(revision, 'revision');
    if (!RegExp(
      r'^(en|zh)(?:-[A-Za-z0-9]{2,8})*$',
      caseSensitive: false,
    ).hasMatch(languageTag)) {
      throw FormatException('Unsupported subtitle language tag: $languageTag');
    }
    final document = _parser.parse(bytes);
    final track = SubtitleTrack(
      id: _uuid.v4(),
      ownerId: ownerId,
      materialId: materialId,
      languageTag: languageTag,
      sourceName: p.basename(sourceName),
      originalBytes: document.originalBytes,
      revision: revision,
      offsetMs: offsetMs,
      selectionMode: manual
          ? SubtitleSelectionMode.manual
          : SubtitleSelectionMode.automatic,
      isSelected: false,
      cues: document.cues,
    );
    final saved = await _repository.saveSubtitleTrack(track, manual: manual);
    return SubtitleImportResult(track: saved, warnings: document.warnings);
  }

  /// Imports a mixed English/Chinese SRT as two selectable tracks.
  /// Returns null when the file is not consistently bilingual.
  Future<List<SubtitleTrack>?> importBilingualBytes({
    required String ownerId,
    required String materialId,
    required String sourceName,
    required List<int> bytes,
    required bool manual,
    int revision = 1,
    int offsetMs = 0,
  }) async {
    final document = _parser.parse(bytes);
    final pair = const BilingualSubtitleSplitter().split(document.cues);
    if (pair == null) return null;
    return _saveBilingualTracks(
      ownerId: ownerId,
      materialId: materialId,
      sourceName: sourceName,
      originalBytes: document.originalBytes,
      pair: pair,
      manual: manual,
      revision: revision,
      offsetMs: offsetMs,
    );
  }

  /// Imports a manually selected SRT without asking the user to choose its
  /// language. Bilingual files become English and Chinese tracks; a
  /// single-language file is detected from its name and text.
  Future<List<SubtitleTrack>> importAutoDetectedBytes({
    required String ownerId,
    required String materialId,
    required String sourceName,
    required List<int> bytes,
    required bool manual,
    int revision = 1,
    int offsetMs = 0,
  }) async {
    if (revision < 1) throw ArgumentError.value(revision, 'revision');
    final document = _parser.parse(bytes);
    if (document.cues.isEmpty) {
      throw const FormatException('The SRT has no valid subtitle cues.');
    }
    final pair = const BilingualSubtitleSplitter().split(document.cues);
    if (pair != null) {
      return _saveBilingualTracks(
        ownerId: ownerId,
        materialId: materialId,
        sourceName: sourceName,
        originalBytes: document.originalBytes,
        pair: pair,
        manual: manual,
        revision: revision,
        offsetMs: offsetMs,
      );
    }

    final languageTag = _languageDetector.detect(
      sourceName: sourceName,
      cues: document.cues,
    );
    if (languageTag == null) {
      throw const SubtitleLanguageDetectionException();
    }
    final track = SubtitleTrack(
      id: _uuid.v4(),
      ownerId: ownerId,
      materialId: materialId,
      languageTag: languageTag,
      sourceName: p.basename(sourceName),
      originalBytes: document.originalBytes,
      revision: revision,
      offsetMs: offsetMs,
      selectionMode: manual
          ? SubtitleSelectionMode.manual
          : SubtitleSelectionMode.automatic,
      isSelected: false,
      cues: document.cues,
    );
    return [await _repository.saveSubtitleTrack(track, manual: manual)];
  }

  Future<List<SubtitleTrack>> _saveBilingualTracks({
    required String ownerId,
    required String materialId,
    required String sourceName,
    required List<int> originalBytes,
    required BilingualSubtitlePair pair,
    required bool manual,
    required int revision,
    required int offsetMs,
  }) async {
    final basename = p.basename(sourceName);
    final mode = manual
        ? SubtitleSelectionMode.manual
        : SubtitleSelectionMode.automatic;
    final tracks = [
      SubtitleTrack(
        id: _uuid.v4(),
        ownerId: ownerId,
        materialId: materialId,
        languageTag: 'en',
        sourceName: '$basename · EN',
        originalBytes: originalBytes,
        revision: revision,
        offsetMs: offsetMs,
        selectionMode: mode,
        isSelected: false,
        cues: pair.english,
      ),
      SubtitleTrack(
        id: _uuid.v4(),
        ownerId: ownerId,
        materialId: materialId,
        languageTag: 'zh-TW',
        sourceName: '$basename · 繁中',
        originalBytes: originalBytes,
        revision: revision,
        offsetMs: offsetMs,
        selectionMode: mode,
        isSelected: false,
        cues: pair.chinese,
      ),
    ];
    if (_repository case final SubtitleTrackBatchWriter writer) {
      return List.unmodifiable(
        await writer.saveSubtitleTracks(tracks, manual: manual),
      );
    }
    final saved = <SubtitleTrack>[];
    for (final track in tracks) {
      saved.add(await _repository.saveSubtitleTrack(track, manual: manual));
    }
    return List.unmodifiable(saved);
  }
}

final class SubtitleLanguageDetectionException implements Exception {
  const SubtitleLanguageDetectionException();
}

final class SubtitleImportResult {
  SubtitleImportResult({
    required this.track,
    required List<SubtitleParseWarning> warnings,
  }) : warnings = List.unmodifiable(warnings);

  final SubtitleTrack track;
  final List<SubtitleParseWarning> warnings;
}
