typedef AudioRead = Stream<List<int>> Function();

final class AudioImportSource {
  const AudioImportSource({
    required this.sourceKey,
    required this.name,
    required this.openRead,
  });

  /// A locally hashed identifier for the selected source, never its raw path.
  final String sourceKey;
  final String name;
  final AudioRead openRead;
}
