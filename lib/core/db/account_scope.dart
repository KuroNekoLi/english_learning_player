import 'dart:convert';

import 'package:crypto/crypto.dart';

final class AccountScope {
  AccountScope(this.ownerId) {
    if (ownerId.trim().isEmpty) {
      throw ArgumentError.value(ownerId, 'ownerId', 'Must not be empty.');
    }
  }

  final String ownerId;

  String get storageKey => sha256.convert(utf8.encode(ownerId)).toString();
}
