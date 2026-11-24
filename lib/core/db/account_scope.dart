import 'dart:convert';

import 'package:crypto/crypto.dart';

final class AccountScope {
  AccountScope(this.ownerId, {String? cloudUid})
    : cloudUid = cloudUid ?? ownerId {
    if (ownerId.trim().isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId', 'Must not be empty.');
    }
  }

  final String ownerId;

  /// Firebase UID when this local profile reads another access mode's cloud.
  final String cloudUid;

  String get storageKey => sha256.convert(utf8.encode(ownerId)).toString();
}
