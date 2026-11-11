import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../library/material_repository.dart';
import '../domain/srt_parser.dart';
import '../domain/subtitle_models.dart';

final class SubtitleImportService {
  SubtitleImportService({
    required MaterialRepository repository,
    SrtParser parser = const SrtParser(),
    Uuid uuid = const Uuid(),
  }) : _repository = repository,
       _parser = parser,
       _uuid = uuid;

  final MaterialRepository _repository;
  final SrtParser _parser;
  final Uuid _uuid;

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
}

final class SubtitleImportResult {
  SubtitleImportResult({
    required this.track,
    required List<SubtitleParseWarning> warnings,
  }) : warnings = List.unmodifiable(warnings);

  final SubtitleTrack track;
  final List<SubtitleParseWarning> warnings;
}
