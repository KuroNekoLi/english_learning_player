import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/folder_access_gateway.dart';
import '../../core/platform/folder_access_gateway_provider.dart';
import '../subtitles/services/subtitle_import_service.dart';
import 'material_repository.dart';
import 'services/folder_import_reconciler.dart';
import 'library_view_model.dart';

const macFolderBindingId = 'primary-icloud-source';

final folderSourceViewModelProvider =
    NotifierProvider<FolderSourceViewModel, FolderSourceState>(
      FolderSourceViewModel.new,
    );

final class FolderSourceState {
  const FolderSourceState({
    this.grantStatus = GrantStatus.missing,
    this.displayLabel,
    this.entries = const [],
    this.isBusy = false,
    this.error,
    this.reconciliationSummary,
  });

  final GrantStatus grantStatus;
  final String? displayLabel;
  final List<FolderEntry> entries;
  final bool isBusy;
  final String? error;
  final String? reconciliationSummary;

  int get availableCount => entries
      .where((entry) => entry.status == FolderEntryStatus.available)
      .length;
  int get pendingCount => entries
      .where((entry) => entry.status == FolderEntryStatus.pendingDownload)
      .length;

  FolderSourceState copyWith({
    GrantStatus? grantStatus,
    String? displayLabel,
    List<FolderEntry>? entries,
    bool? isBusy,
    String? error,
    bool clearError = false,
    String? reconciliationSummary,
  }) => FolderSourceState(
    grantStatus: grantStatus ?? this.grantStatus,
    displayLabel: displayLabel ?? this.displayLabel,
    entries: entries ?? this.entries,
    isBusy: isBusy ?? this.isBusy,
    error: clearError ? null : error ?? this.error,
    reconciliationSummary: reconciliationSummary ?? this.reconciliationSummary,
  );
}

final class FolderSourceViewModel extends Notifier<FolderSourceState> {
  late FolderAccessGateway _gateway;
  StreamSubscription<void>? _watchSubscription;
  Timer? _rescanTimer;

  @override
  FolderSourceState build() {
    _gateway = ref.watch(folderAccessGatewayProvider);
    ref.onDispose(() {
      _rescanTimer?.cancel();
      unawaited(_watchSubscription?.cancel());
    });
    unawaited(_restore());
    return const FolderSourceState();
  }

  Future<void> connect() async {
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final folder = await _gateway.pickFolder(macFolderBindingId);
      if (folder == null) {
        state = state.copyWith(isBusy: false);
        return;
      }
      state = state.copyWith(
        grantStatus: GrantStatus.valid,
        displayLabel: folder.displayLabel,
      );
      await _refresh();
      if (state.grantStatus != GrantStatus.denied) await _startWatching();
    } on FolderAccessException catch (error) {
      state = state.copyWith(isBusy: false, error: _message(error.failure));
    } catch (_) {
      state = state.copyWith(isBusy: false, error: '無法授權資料夾');
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(isBusy: true, clearError: true);
    await _refresh();
  }

  Future<void> disconnect() async {
    state = state.copyWith(isBusy: true, clearError: true);
    await _watchSubscription?.cancel();
    _watchSubscription = null;
    try {
      await _gateway.disconnect(macFolderBindingId);
      state = const FolderSourceState();
    } on FolderAccessException catch (error) {
      state = state.copyWith(isBusy: false, error: _message(error.failure));
    } catch (_) {
      state = state.copyWith(isBusy: false, error: '無法解除資料夾授權');
    }
  }

  Future<void> reconcile() async {
    if (state.grantStatus != GrantStatus.valid) return;
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      final repository = await ref.read(materialRepositoryProvider.future);
      final importService = await ref.read(audioImportServiceProvider.future);
      final scope = ref.read(accountScopeProvider);
      final result = await FolderImportReconciler(
        gateway: _gateway,
        repository: repository as FolderReconciliationRepository,
        materials: repository,
        audioImporter: importService,
        subtitleImporter: SubtitleImportService(repository: repository),
        ownerId: scope.ownerId,
      ).reconcile();
      state = state.copyWith(
        isBusy: false,
        reconciliationSummary:
            '新增音訊 ${result.importedAudio}、改名沿用 ${result.renamedAudio}、'
            '字幕 ${result.importedSubtitles}；待下載 ${result.pendingDownload}、'
            '歧義 ${result.ambiguousSubtitles}、失敗 ${result.failures}',
      );
      ref.invalidate(libraryViewModelProvider);
      await _refresh();
    } catch (_) {
      state = state.copyWith(isBusy: false, error: '資料夾匯入與清單更新失敗');
    }
  }

  Future<void> _restore() async {
    try {
      final status = await _gateway.restoreGrant(macFolderBindingId);
      state = state.copyWith(
        grantStatus: status,
        displayLabel: status == GrantStatus.valid || status == GrantStatus.stale
            ? '已授權資料夾'
            : null,
      );
      if (status == GrantStatus.valid || status == GrantStatus.stale) {
        await _refresh();
        if (state.grantStatus != GrantStatus.denied) await _startWatching();
      }
    } on FolderAccessException catch (error) {
      final status = switch (error.failure) {
        FolderFailure.notFound => GrantStatus.missing,
        FolderFailure.permissionDenied => GrantStatus.denied,
        _ => state.grantStatus,
      };
      state = state.copyWith(
        grantStatus: status,
        error: switch (error.failure) {
          FolderFailure.notFound => null,
          FolderFailure.permissionDenied => '資料夾授權已撤銷，請重新選取',
          FolderFailure.providerUnavailable => '此平台不支援 iCloud 資料夾授權',
          FolderFailure.fileNotDownloaded => '資料夾授權仍有效，但來源尚未完整下載',
          FolderFailure.transientIo => '資料夾授權暫時無法讀取，請稍後重試',
        },
        clearError: error.failure == FolderFailure.notFound,
      );
    } catch (_) {
      state = state.copyWith(
        grantStatus: GrantStatus.denied,
        error: '資料夾授權無法恢復，請重新選取',
      );
    }
  }

  Future<void> _refresh() async {
    try {
      final entries = await _gateway.scan(macFolderBindingId);
      state = state.copyWith(
        grantStatus: GrantStatus.valid,
        entries: entries,
        isBusy: false,
        clearError: true,
      );
    } on FolderAccessException catch (error) {
      state = state.copyWith(
        grantStatus: error.failure == FolderFailure.permissionDenied
            ? GrantStatus.denied
            : state.grantStatus,
        isBusy: false,
        error: _message(error.failure),
      );
    } catch (_) {
      state = state.copyWith(isBusy: false, error: '資料夾掃描失敗');
    }
  }

  Future<void> _startWatching() async {
    await _watchSubscription?.cancel();
    _watchSubscription = _gateway
        .watch(macFolderBindingId)
        .listen(
          (_) {
            _rescanTimer?.cancel();
            _rescanTimer = Timer(const Duration(milliseconds: 350), () {
              unawaited(_refresh());
            });
          },
          onError: (_) {
            state = state.copyWith(error: '資料夾監看中斷，請重新整理');
          },
        );
  }

  String _message(FolderFailure failure) => switch (failure) {
    FolderFailure.permissionDenied => '資料夾權限已撤銷，請重新選取',
    FolderFailure.providerUnavailable => '此平台不支援 iCloud 資料夾授權',
    FolderFailure.fileNotDownloaded => '檔案尚未從 iCloud 下載',
    FolderFailure.notFound => '資料夾或檔案不存在',
    FolderFailure.transientIo => '資料夾讀取失敗，請稍後重試',
  };
}
