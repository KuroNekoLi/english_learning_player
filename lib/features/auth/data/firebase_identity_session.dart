import '../../../core/sync/sync_identity.dart';

/// The authenticated Firebase identity consumed by sync transports.
///
/// Provider SDKs own refresh and persistence; callers request a token only
/// after supplying the UID they expect to act as.
abstract interface class FirebaseIdentitySession
    implements SyncIdentityProvider {
  String? get uid;

  Future<String> tokenFor(String expectedUid);
}
