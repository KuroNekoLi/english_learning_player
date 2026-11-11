import 'package:path/path.dart' as p;

final class AudioFileType {
  const AudioFileType(this.extension, this.mimeType);

  final String extension;
  final String mimeType;

  static AudioFileType fromName(String name) {
    switch (p.extension(name).toLowerCase()) {
      case '.mp3':
        return const AudioFileType('mp3', 'audio/mpeg');
      case '.m4a':
        return const AudioFileType('m4a', 'audio/mp4');
      default:
        throw const FormatException('Only MP3 and M4A files are supported.');
    }
  }
}
