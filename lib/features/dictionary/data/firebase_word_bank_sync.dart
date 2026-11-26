import '../../../core/sync/sync_contracts.dart';
import '../../sync/data/firebase_documents.dart';
import 'dictionary_repository.dart';
import 'word_bank_repository.dart';

final class FirebaseWordBankSync {
  FirebaseWordBankSync({
    required this.uid,
    required this.documents,
    required this.local,
    required this.consent,
    required this.readOnly,
  });

  final String uid;
  final FirebaseDocuments documents;
  final WordBankRepository local;
  final SyncConsentProvider consent;
  final bool readOnly;
  Future<bool>? _pass;
  DateTime? _retryAfter;

  List<String> get _collection => ['users', uid, 'wordBank'];

  Future<bool> run({required bool refresh}) => _pass ??= _run(refresh: refresh);

  Future<bool> _run({required bool refresh}) async {
    try {
      if (!refresh && (_retryAfter?.isAfter(DateTime.now()) ?? false)) {
        return false;
      }
      final pending = readOnly ? [] : await local.pending();
      if (pending.isEmpty && !refresh) return false;
      await _checkConsent();
      var changed = false;
      if (refresh) {
        final records = await documents.listDocuments(uid, _collection);
        final changes = <WordBankChange>[];
        for (final record in records) {
          try {
            changes.add(_decode(record));
          } on FormatException {
            continue;
          } on TypeError {
            continue;
          }
        }
        await _checkConsent();
        changed = await local.merge(changes);
      }

      // Re-read the queue because a pull can resolve a migrated favorite.
      if (!readOnly) {
        for (final item in await local.pending()) {
          final reconciled = await _publish(
            item.change,
            migrated: item.migrated,
          );
          changed = changed || reconciled;
        }
      }
      _retryAfter = null;
      return changed;
    } catch (_) {
      _retryAfter = DateTime.now().add(const Duration(seconds: 30));
      rethrow;
    } finally {
      _pass = null;
    }
  }

  Future<bool> _publish(WordBankChange change, {required bool migrated}) async {
    final path = [..._collection, change.word];
    for (var attempt = 0; attempt < 3; attempt++) {
      final current = await documents.readVersionedDocument(uid, path);
      final remote = current == null ? null : _decode(current.fields);
      if (remote != null) {
        if (remote.word != change.word || current!.updateTime == null) {
          throw const FormatException('Invalid versioned word bank record');
        }
        if (remote.opId == change.opId) {
          await _checkConsent();
          await local.acknowledge(change, remote.revision);
          return false;
        }
        if (migrated || remote.revision > change.revision) {
          await _checkConsent();
          await local.acceptConflict(change, remote);
          return true;
        }
      }
      final revision = (remote?.revision ?? 0) + 1;
      try {
        await documents.writeVersionedDocument(uid, path, {
          'schemaVersion': 1,
          'ownerId': uid,
          'word': change.word,
          'payload': change.payload,
          'savedAtMs': change.savedAtMs,
          'opId': change.opId,
          'revision': revision,
        }, updateTime: current?.updateTime);
      } on SyncFailure catch (error) {
        if (const {
          'firebase_http_409',
          'firebase_http_412',
          'library_write_conflict',
        }.contains(error.code)) {
          continue;
        }
        rethrow;
      }
      await _checkConsent();
      await local.acknowledge(change, revision);
      return false;
    }
    throw const SyncFailure(
      SyncFailureKind.transient,
      'word_bank_write_conflict',
    );
  }

  WordBankChange _decode(Map<String, Object> record) {
    if (record
        case {
          'schemaVersion': 1,
          'ownerId': final String owner,
          'word': final String word,
          'payload': final String payload,
          'savedAtMs': final int savedAtMs,
          'opId': final String opId,
          'revision': final int revision,
        }
        when owner == uid &&
            word.isNotEmpty &&
            normalizeDictionaryWord(word) == word &&
            revision > 0 &&
            savedAtMs > 0) {
      if (payload.isEmpty ||
          normalizeDictionaryWord(decodeSavedWord(payload).word) == word) {
        return (
          word: word,
          payload: payload,
          savedAtMs: savedAtMs,
          revision: revision,
          opId: opId,
        );
      }
    }
    throw const FormatException('Invalid word bank record');
  }

  Future<void> _checkConsent() async {
    if (!await consent.isCloudSyncEnabled(uid)) {
      throw const SyncFailure(
        SyncFailureKind.permissionDenied,
        'consent_required',
      );
    }
  }
}
