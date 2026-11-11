import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'account_scope.dart';
import 'local_database.dart';

final class AccountDatabaseService {
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
    return LocalDatabase.open(File(p.join(directory.path, 'library.sqlite')));
  }

  Directory mediaDirectory(AccountScope scope) =>
      Directory(p.join(_supportDirectory.path, 'media', scope.storageKey));
}
