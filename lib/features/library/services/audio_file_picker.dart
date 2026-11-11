import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';

import '../domain/audio_import_source.dart';

abstract interface class AudioFilePicker {
  Future<AudioImportSource?> pickAudio();
}

final class NativeAudioFilePicker implements AudioFilePicker {
  static const _audioFiles = XTypeGroup(
    label: 'Audio',
    extensions: ['m4a', 'mp3'],
    mimeTypes: ['audio/mp4', 'audio/mpeg'],
    uniformTypeIdentifiers: ['public.mpeg-4-audio', 'public.mp3'],
  );

  @override
  Future<AudioImportSource?> pickAudio() async {
    final file = await openFile(acceptedTypeGroups: [_audioFiles]);
    if (file == null) return null;
    return AudioImportSource(
      sourceKey: sha256.convert(utf8.encode(file.path)).toString(),
      name: file.name,
      openRead: file.openRead,
    );
  }
}
