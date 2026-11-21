import 'account_scope.dart';
import 'local_database.dart';

/// Opens the same account-scoped schema using a platform-specific executor.
abstract interface class AccountDatabaseOpener {
  Future<LocalDatabase> openDatabase(AccountScope scope);
}
