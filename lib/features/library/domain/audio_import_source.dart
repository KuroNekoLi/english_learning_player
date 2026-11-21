/// A repeatable stream factory; browser storage can replay it to fall back from
/// OPFS to IndexedDB without persisting a partial object.
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
