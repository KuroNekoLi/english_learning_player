import 'dart:convert';

enum LibraryField {
  folderName,
  folderParent,
  folderDeleted,
  materialTitle,
  materialFolders,
  materialDeleted,
}

/// Each field has its own version so concurrent rename and move both survive.
final class LibraryChange {
  const LibraryChange({
    required this.field,
    required this.id,
    required this.value,
    required this.revision,
    required this.opId,
  });

  final LibraryField field;
  final String id;
  final String value;
  final int revision;
  final String opId;

  String get key => '${field.name}_$id';

  int compareVersion(LibraryChange other) {
    final order = revision.compareTo(other.revision);
    return order == 0 ? opId.compareTo(other.opId) : order;
  }

  Set<String> get folderIds =>
      (jsonDecode(value) as List).cast<String>().toSet();

  Map<String, Object> toDocument(String owner) => {
    'ownerId': owner,
    'schemaVersion': 1,
    'field': field.name,
    'entityId': id,
    'value': value,
    'revision': revision,
    'opId': opId,
  };

  static final _id = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
  static final _opId = RegExp(r'^[a-f0-9-]{36}$');

  static LibraryChange fromDocument(Map<String, Object> data, String owner) {
    try {
      if (data['ownerId'] != owner || data['schemaVersion'] != 1) {
        throw const FormatException('Invalid library owner or schema');
      }
      final change = LibraryChange(
        field: LibraryField.values.byName(data['field'] as String),
        id: data['entityId'] as String,
        value: data['value'] as String,
        revision: data['revision'] as int,
        opId: data['opId'] as String,
      );
      if (change.isValid) return change;
    } on ArgumentError {
      // Unknown field.
    } on TypeError {
      // Incompatible record.
    }
    throw const FormatException('Invalid library change');
  }

  bool get isValid =>
      _id.hasMatch(id) &&
      _opId.hasMatch(opId) &&
      revision > 0 &&
      revision <= 9007199254740991 &&
      switch (field) {
        LibraryField.folderName || LibraryField.materialTitle =>
          value.trim().isNotEmpty && value.runes.length <= 80,
        LibraryField.folderDeleted ||
        LibraryField.materialDeleted => value == '1',
        LibraryField.folderParent =>
          value.isEmpty || (_id.hasMatch(value) && value != id),
        LibraryField.materialFolders => _validFolders(),
      };

  bool _validFolders() {
    if (value.length > 32768) return false;
    try {
      final folders = jsonDecode(value);
      return folders is List &&
          folders.every((id) => id is String && _id.hasMatch(id));
    } on FormatException {
      return false;
    }
  }
}
