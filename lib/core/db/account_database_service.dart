import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'account_scope.dart';
import 'account_database_opener.dart';
import 'local_database.dart';

final class AccountDatabaseService implements AccountDatabaseOpener {
  const AccountDatabaseService({required Directory supportDirectory})
    : _supportDirectory = supportDirectory;

  final Directory _supportDirectory;

  static Future<AccountDatabaseService> createForApplication() async =>
      AccountDatabaseService(
        supportDirectory: await getApplicationSupportDirectory(),
      );

  Future<LocalDatabase> open(AccountScope scope) async {
    final directory = Directory(
      p.join(_supportDirectory.path, 'profiles', scope.storageKey),
    );
    await directory.create(recursive: true);
    return LocalDatabase(
      NativeDatabase.createInBackground(
        File(p.join(directory.path, 'library.sqlite')),
      ),
    );
  }

  @override
  Future<LocalDatabase> openDatabase(AccountScope scope) => open(scope);

  Directory mediaDirectory(AccountScope scope) =>
      Directory(p.join(_supportDirectory.path, 'media', scope.storageKey));

  File resolveMediaFile(AccountScope scope, String relativePath) {
    final normalized = p.normalize(relativePath);
    final parts = p.split(normalized);
    if (p.isAbsolute(relativePath) ||
        parts.length != 3 ||
        parts[0] != 'media' ||
        parts[1] != scope.storageKey ||
        parts[2].isEmpty ||
        parts[2] == '.' ||
        parts[2] == '..') {
      throw const FormatException('Media path is outside its account scope.');
    }
    return File(p.join(mediaDirectory(scope).path, parts[2]));
  }
}
