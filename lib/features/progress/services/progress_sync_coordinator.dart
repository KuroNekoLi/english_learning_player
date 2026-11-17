import '../../../core/db/account_scope.dart';
import '../../../core/sync/sync_contracts.dart';
import '../../../core/sync/progress_policy.dart';
import '../data/progress_repository.dart';
import '../domain/progress_models.dart';

abstract interface class ProgressSyncTransport {
  /// Must implement ADR-012 receipt, sequence high-water and canonical revision
  /// checks atomically in the authenticated owner's transaction.
  Future<ProgressCommitResult> commit({
    required String uid,
    required String opId,
    required String payloadHash,
    required ProgressCheckpoint checkpoint,
    ProgressResolution? resolution,
  });
}

enum ProgressSyncRunResult {
  idle,
  waitingForAuthentication,
  waitingForConsent,
  committed,
  retryScheduled,
  needsAttention,
}

final class ProgressSyncCoordinator {
  ProgressSyncCoordinator({
    required AccountScope scope,
    required ProgressRepository repository,
    required SyncIdentityProvider identityProvider,
    required SyncConsentProvider consentProvider,
    required ProgressSyncTransport transport,
    required DateTime Function() clock,
    required double Function() random,
  }) : _scope = scope,
       _repository = repository,
       _identityProvider = identityProvider,
       _consentProvider = consentProvider,
       _transport = transport,
       _clock = clock,
       _random = random;

  final AccountScope _scope;
  final ProgressRepository _repository;
  final SyncIdentityProvider _identityProvider;
  final SyncConsentProvider _consentProvider;
  final ProgressSyncTransport _transport;
  final DateTime Function() _clock;
  final double Function() _random;

  Future<ProgressSyncRunResult> runOne() async {
    final now = _clock().toUtc();
    final identity = await _identityProvider.currentIdentity();
    if (identity == null || identity.uid != _scope.ownerId) {
      return ProgressSyncRunResult.waitingForAuthentication;
    }
    if (!await _consentProvider.isCloudSyncEnabled(identity.uid)) {
      return ProgressSyncRunResult.waitingForConsent;
    }
    await _repository.resumeAuthenticated(now);
    final operation = await _repository.claimNext(now);
    if (operation == null) return ProgressSyncRunResult.idle;
    try {
      final result = await _transport.commit(
        uid: identity.uid,
        opId: operation.opId,
        payloadHash: operation.payloadHash,
        checkpoint: operation.checkpoint,
        resolution: operation.resolution,
      );
      final currentIdentity = await _identityProvider.currentIdentity();
      if (currentIdentity?.uid != identity.uid) {
        await _repository.waitForAuthentication(
          operation.opId,
          _clock().toUtc(),
        );
        return ProgressSyncRunResult.waitingForAuthentication;
      }
      await _repository.applyCommitResult(
        opId: operation.opId,
        payloadHash: operation.payloadHash,
        result: result,
        nowMs: _clock().toUtc().millisecondsSinceEpoch,
      );
      return ProgressSyncRunResult.committed;
    } on SyncFailure catch (failure) {
      if (failure.kind == SyncFailureKind.unauthenticated) {
        await _repository.waitForAuthentication(
          operation.opId,
          _clock().toUtc(),
        );
        return ProgressSyncRunResult.waitingForAuthentication;
      }
      final retryable = failure.kind == SyncFailureKind.transient;
      final nextAttempt = operation.attempts + (retryable ? 1 : 0);
      final retryAt = retryable
          ? nextRetryAt(now, nextAttempt, _random())
          : now;
      await _repository.defer(
        opId: operation.opId,
        code: failure.code,
        retryable: retryable,
        now: now,
        retryAt: retryAt,
      );
      return retryable && nextAttempt < 8
          ? ProgressSyncRunResult.retryScheduled
          : ProgressSyncRunResult.needsAttention;
    }
  }
}

DateTime nextRetryAt(DateTime now, int attempt, double random) {
  final exponent = attempt <= 1 ? 0 : attempt - 1;
  final capSeconds = 1 << (exponent > 6 ? 6 : exponent);
  final cap = capSeconds > 60 ? 60 : capSeconds;
  final bounded = random.clamp(0.0, 1.0).toDouble();
  final delay = ((cap / 2) + bounded * (cap / 2)).round();
  return now.add(Duration(seconds: delay));
}
