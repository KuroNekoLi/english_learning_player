import 'library_change.dart';

/// Projects portable folders and assignments even before their audio arrives.
final class LibraryStructure {
  LibraryStructure(Iterable<LibraryChange> changes) {
    for (final change in changes) {
      switch (change.field) {
        case LibraryField.folderName:
          names[change.id] = change.value;
        case LibraryField.folderParent:
          _parents[change.id] = change.value;
        case LibraryField.folderDeleted:
          _removedFolders.add(change.id);
        case LibraryField.materialFolders:
          _memberships[change.id] = change.folderIds;
        case LibraryField.materialDeleted:
          removedMaterials.add(change.id);
        case LibraryField.materialTitle:
          break;
      }
    }

    // Concurrent moves can create a cycle. Every member of that cycle
    // resolves to root, independently of the order documents were received.
    final visited = <String>{};
    for (final id in names.keys) {
      final path = <String>{};
      String? current = id;
      while (current != null &&
          names.containsKey(current) &&
          !visited.contains(current)) {
        if (!path.add(current)) {
          var member = current;
          do {
            _cycle.add(member);
            member = _parents[member]!;
          } while (member != current);
          break;
        }
        current = _parents[current];
      }
      visited.addAll(path);
    }
  }

  final names = <String, String>{};
  final _parents = <String, String>{};
  final _removedFolders = <String>{};
  final _memberships = <String, Set<String>>{};
  final removedMaterials = <String>{};
  final _cycle = <String>{};

  bool folderExists(String id) =>
      names.containsKey(id) && !_removedFolders.contains(id);

  String? parentOf(String id) =>
      _cycle.contains(id) ? null : _liveFolder(_parents[id]);

  String? _liveFolder(String? id) {
    while (id != null && names.containsKey(id)) {
      if (folderExists(id)) return id;
      if (_cycle.contains(id)) return null;
      id = _parents[id];
    }
    return null;
  }

  Set<String> foldersFor(String id) => {
    for (final folder in _memberships[id] ?? const <String>{})
      if (_liveFolder(folder) case final live?) live,
  };

  // Preserve placements whose folders haven't arrived yet. Deletions resolve
  // to the nearest surviving ancestor.
  Set<String> placementsForEdit(String id) => {
    for (final folder in _memberships[id] ?? const <String>{})
      if (!names.containsKey(folder))
        folder
      else if (_liveFolder(folder) case final live?)
        live,
  };
}
