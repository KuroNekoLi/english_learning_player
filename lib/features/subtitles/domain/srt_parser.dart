import 'dart:convert';

import 'subtitle_models.dart';

final class SrtParser {
  const SrtParser();

  static final RegExp _timestampLine = RegExp(
    r'^\s*(\d{1,9}):(\d{2}):(\d{2}),(\d{3})\s*-->\s*'
    r'(\d{1,9}):(\d{2}):(\d{2}),(\d{3})\s*$',
  );

  SubtitleDocument parse(List<int> bytes) {
    late final String decoded;
    try {
      decoded = utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      throw const SubtitleParseException(
        code: 'invalidUtf8',
        recoverable: true,
      );
    }

    final text = decoded.startsWith('\uFEFF') ? decoded.substring(1) : decoded;
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final blocks = normalized
        .split(RegExp(r'\n[\t ]*\n+'))
        .where((block) => block.trim().isNotEmpty)
        .toList(growable: false);
    final cues = <SubtitleCue>[];
    final warnings = <SubtitleParseWarning>[];

    for (var blockIndex = 0; blockIndex < blocks.length; blockIndex++) {
      final lines = blocks[blockIndex].split('\n');
      var timestampIndex = 0;
      var sequence = blockIndex + 1;
      final explicitSequence = int.tryParse(lines.first.trim());
      if (explicitSequence != null) {
        sequence = explicitSequence;
        timestampIndex = 1;
        if (explicitSequence <= 0) {
          warnings.add(
            SubtitleParseWarning(
              code: 'invalidSequence',
              blockIndex: blockIndex,
            ),
          );
        }
      } else {
        warnings.add(
          SubtitleParseWarning(code: 'missingSequence', blockIndex: blockIndex),
        );
      }

      if (timestampIndex >= lines.length) {
        warnings.add(
          SubtitleParseWarning(
            code: 'missingTimestamp',
            blockIndex: blockIndex,
          ),
        );
        continue;
      }
      final match = _timestampLine.firstMatch(lines[timestampIndex]);
      if (match == null) {
        warnings.add(
          SubtitleParseWarning(
            code: 'invalidTimestamp',
            blockIndex: blockIndex,
          ),
        );
        continue;
      }
      final startMs = _timeFrom(match, 1);
      final endMs = _timeFrom(match, 5);
      if (startMs == null || endMs == null) {
        warnings.add(
          SubtitleParseWarning(
            code: 'timestampOutOfRange',
            blockIndex: blockIndex,
          ),
        );
        continue;
      }
      if (endMs <= startMs) {
        warnings.add(
          SubtitleParseWarning(code: 'invalidInterval', blockIndex: blockIndex),
        );
        continue;
      }
      final cueLines = lines.skip(timestampIndex + 1).toList(growable: false);
      if (cueLines.isEmpty || cueLines.every((line) => line.isEmpty)) {
        warnings.add(
          SubtitleParseWarning(code: 'emptyText', blockIndex: blockIndex),
        );
        continue;
      }
      cues.add(
        SubtitleCue(
          id: 'cue-$blockIndex',
          sequence: sequence,
          startMs: startMs,
          endMs: endMs,
          text: cueLines.join('\n'),
        ),
      );
    }

    if (blocks.isEmpty) {
      warnings.add(const SubtitleParseWarning(code: 'emptyDocument'));
    }
    return SubtitleDocument(
      originalBytes: bytes,
      cues: cues,
      warnings: warnings,
    );
  }

  int? _timeFrom(RegExpMatch match, int offset) {
    final hours = int.parse(match[offset]!);
    final minutes = int.parse(match[offset + 1]!);
    final seconds = int.parse(match[offset + 2]!);
    final milliseconds = int.parse(match[offset + 3]!);
    if (minutes > 59 || seconds > 59) return null;
    return (((hours * 60) + minutes) * 60 + seconds) * 1000 + milliseconds;
  }
}

final class SubtitleDocument {
  SubtitleDocument({
    required List<int> originalBytes,
    required List<SubtitleCue> cues,
    required List<SubtitleParseWarning> warnings,
  }) : originalBytes = List.unmodifiable(originalBytes),
       cues = List.unmodifiable(cues),
       warnings = List.unmodifiable(warnings);

  final List<int> originalBytes;
  final List<SubtitleCue> cues;
  final List<SubtitleParseWarning> warnings;
}

final class SubtitleParseWarning {
  const SubtitleParseWarning({required this.code, this.blockIndex});

  final String code;
  final int? blockIndex;
}

final class SubtitleParseException implements Exception {
  const SubtitleParseException({required this.code, required this.recoverable});

  final String code;
  final bool recoverable;
}
