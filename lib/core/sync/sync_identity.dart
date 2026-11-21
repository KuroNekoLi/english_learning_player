/// Firebase identity contracts shared by native and browser auth adapters.
///
/// This file deliberately has no `dart:io` dependency so Web authentication can
/// provide the same UID contract without importing native transports.
final class SyncIdentity {
  const SyncIdentity(this.uid);

  final String uid;
}

abstract interface class SyncIdentityProvider {
  Future<SyncIdentity?> currentIdentity();
}
