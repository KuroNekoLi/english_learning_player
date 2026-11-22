import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/db/local_database.dart';
import '../domain/library_change.dart';

/// Local projection and durable queue share a row. Ack applies only to the
/// operation sent, so an edit made during transmission stays queued.
final class SqliteLibraryChanges {
  const SqliteLibraryChanges(this.db, this.owner);

  final LocalDatabase db;
  final String owner;

  Future<List<LibraryChange>> read({
    bool pendingOnly = false,
    int? limit,
  }) async {
    final rows = await db
        .customSelect(
          'SELECT * FROM library_changes WHERE owner_id = ? '
          '${pendingOnly ? 'AND pending = 1 ' : ''}ORDER BY revision, op_id '
          '${limit == null ? '' : 'LIMIT ?'}',
          variables: [
            Variable.withString(owner),
            if (limit != null) Variable.withInt(limit),
          ],
        )
        .get();
    return rows
        .map(
          (row) => LibraryChange(
            field: LibraryField.values.byName(row.read<String>('field')),
            id: row.read<String>('entity_id'),
            value: row.read<String>('value'),
            revision: row.read<int>('revision'),
            opId: row.read<String>('op_id'),
          ),
        )
        .toList();
  }

  /// Called inside the library command transaction.
  Future<void> edit(LibraryField field, String id, String value) async {
    final row = await db
        .customSelect(
          'SELECT COALESCE(MAX(revision), 0) AS latest FROM library_changes WHERE owner_id = ?',
          variables: [Variable.withString(owner)],
        )
        .getSingle();
    final change = LibraryChange(
      field: field,
      id: id,
      value: value,
      revision: row.read<int>('latest') + 1,
      opId: const Uuid().v4(),
    );
    if (!change.isValid) throw ArgumentError('Invalid library change');
    await _save(change, pending: true);
  }

  Future<int> merge(Iterable<LibraryChange> changes) =>
      db.transaction(() async {
        var applied = 0;
        for (final change in changes) {
          applied += await _save(change, pending: false);
        }
        return applied;
      });

  Future<int> _save(LibraryChange change, {required bool pending}) =>
      db.customUpdate(
        '''
        INSERT INTO library_changes (owner_id, field, entity_id, value, revision, op_id, pending)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT (owner_id, field, entity_id) DO UPDATE SET
          value = excluded.value, revision = excluded.revision, op_id = excluded.op_id,
          pending = excluded.pending
        WHERE excluded.revision > library_changes.revision OR
          (excluded.revision = library_changes.revision AND excluded.op_id > library_changes.op_id)
        ''',
        variables: [
          Variable.withString(owner),
          Variable.withString(change.field.name),
          Variable.withString(change.id),
          Variable.withString(change.value),
          Variable.withInt(change.revision),
          Variable.withString(change.opId),
          Variable.withBool(pending),
        ],
      );

  Future<void> acknowledge(LibraryChange change) => db.customStatement(
    'UPDATE library_changes SET pending = 0 WHERE owner_id = ? AND field = ? AND entity_id = ? AND op_id = ?',
    [owner, change.field.name, change.id, change.opId],
  );

  Future<bool> materialDeleted(String id) async =>
      (await db
          .customSelect(
            "SELECT 1 FROM library_changes WHERE owner_id = ? AND field = 'materialDeleted' AND entity_id = ?",
            variables: [Variable.withString(owner), Variable.withString(id)],
          )
          .getSingleOrNull()) !=
      null;
}
