# WP-08 交棒：本機 outbox 與雲端同步邊界

- 日期：2026-11-13
- 分支：`codex/wp-08-cloud-sync`
- 基準：WP-07 `92bab4760c5b247c7d6cba1d26d7283aff6086f5`
- 範圍：LocalReady 音訊教材 → durable outbox → 可替換 Auth/Storage/Firestore service boundary。沒有開始 WP-09 progress sync。

## 已實作

- Drift schema 升至 v4：`sync_outbox` 保存 owner/opId/entity/versioned JSON/SHA-256/attempts/retry time/lease/state/error；`material_sync_state` 以 overlay 表呈現 `localReady/uploading/cloudReady/error`，保留 WP-02 `materials.status=localReady` 限制。v1-v3 升級會為既有教材建立待同步 outbox。
- `SqliteMaterialRepository.insertAudio` 在教材建立的同一 transaction 寫入 outbox。重覆來源與 hash 返回原教材，不會再排第二個雲端操作。媒體相對路徑不在 payload。
- `lib/features/sync/services/cloud_sync_coordinator.dart` 要求明確 `SyncConsentProvider` 同意後才派送，並驗證 uid == `AccountScope.ownerId`、payload hash、私有媒體存在/大小/SHA-256，派送 asset → material metadata；核對 Storage receipt 的 uid path/hash/size/MIME 後才完成 outbox 和更新 CloudReady。上傳或 metadata 部分失敗會保留原 opId 重送。Core sync contracts 不依賴 Feature Repository。
- retry：1s 起、cap 60s、jitter `[cap/2, cap]`；第 8 次暫時錯誤轉 `needsAttention`。Auth 缺失暫停至相同 UID 恢復；權限/資料錯誤需處理原因後可用原 opId 手動重試。過期 lease 可重新領取。
- Firebase Rules 是 fail-closed emulator 測試規則，Firestore/Storage 都 UID scoped；測試 owner allow、anonymous/cross UID deny、錯誤欄位、MIME、同一教材冪等更新及 Storage object 不可覆寫。transport 遇到已存在 object 必須先核驗並重用，不能覆寫。

## 公開接口

- `SyncIdentityProvider.currentIdentity()` → `SyncIdentity?`（null 表示未登入）
- `SyncConsentProvider.isCloudSyncEnabled(uid)` → false 時保留本機 outbox，不傳輸
- `SyncOutbox.claimNext/complete/deferForAuthentication/fail/resumeAuthenticated/retryNeedsAttention`
- `CloudSyncTransport.uploadAsset/publishAsset/publishMaterial`
- `CloudSyncCoordinator.runOne()` → idle / waitingForAuthentication / uploaded / retryScheduled / needsAttention
- `CloudAssetReceipt` 必須回報已驗證 storage path、SHA-256、位元數、MIME。實際 Firebase adapter 若無法提供 read-back 或可信後端 hash 驗證，禁止回報為已驗證 receipt。

## 測試 / 驗收

- Flutter：`test/core/sync/cloud_sync_coordinator_test.dart` 有 13 cases，覆蓋成功、部分 metadata 失敗同 opId 重送、DB 重開後續送、登出/回登入、同步同意閘門、傳輸期間切帳號、permission denied、損壞本機檔、8 次 retry/手動重試、重覆匯入、outbox owner scope 及教材/outbox 原子回滾。
- Migration：WP-02 v1 測試現同時確認升級會將既有教材排入待同步佇列。
- Rules Emulator：`npm run test:rules`（Node 22、Firebase CLI 15.36.0；使用 `demo-english-learning-player`）。Firestore 2 case、Storage 1 case，共 3 case；執行成功，emulators 自動停止。
- `dart format --output=none --set-exit-if-changed .`：**PASS**，59 個 Dart files，0 changed。
- `flutter analyze`：**PASS**，No issues found。
- `flutter test --reporter expanded`：**PASS**，80 tests。
- `git diff --check`：**PASS**。
- Android：`flutter build apk --debug` **PASS**，產物 `build/app/outputs/flutter-apk/app-debug.apk`。直接設 `JAVA_HOME` 仍受 Flutter 使用者設定中的 JDK 25 覆蓋而 **FAIL**；以暫存 `XDG_CONFIG_HOME` 設為既有 Corretto 17 後通過，沒有修改使用者設定/Gradle 設定。Doctor 提示 Android licenses 未全接受、插件要求建議 NDK 27；未接受 licenses 或更改 NDK，本 build 使用目前 NDK 26.3.11579264 通過。
- iOS：`flutter build ios --debug --no-codesign` **PASS**，產物 `build/ios/iphoneos/Runner.app`；未簽章、未安裝真機。
- macOS：`flutter build macos --debug` **PASS**，產物 `build/macos/Build/Products/Debug/english_learning_player.app`；Xcode 報多個 destination 並選第一項，沒有真機/發佈簽章驗證。
- `npm audit --omit=dev`：**PASS**，無 production dependency 漏洞。完整 npm audit 對 Node emulator test-only devDependencies 回報 5 high/14 moderate；該 npm 工具鏈不進 Flutter app/發布產物，相關套件未加入 Dart `pubspec.yaml`。

## BLOCKED / 風險

- **BLOCKED：FlutterFire production/emulator adapter 與端到端 Auth。** Stage 1 已記錄 Android/iOS 最低版本衝突、macOS Keychain `SecItemAdd -34018`、provider/SwiftPM 未決；本 WP 沒有提高最低 OS 或新增 FlutterFire 套件。Fake transport 驗證的是 coordinator 契約，不代表 Firebase app 已連線。
- **BLOCKED：遠端 SHA-256 證明。** Security Rules 只能檢查上傳 metadata，不能計算物件位元的 SHA-256。adapter 必須 read-back 重算，或使用核准的可信後端；其流量/費率未決。現階段 Fake receipt 只驗證協調器的契約行為。
- **OPEN：** Firebase 專案、計費/區域、正式 Auth providers、profile→UID mapping、storage 媒體大小/預算。Rules 暫設 100 MiB 是保護性測試上限，不是核准的產品限制。
- 本 WP 暫只把匯入音訊與教材 metadata 排入 outbox；字幕二進位、播放進度、書籤/墓碑尚未送雲端。Progress/衝突明確留給 WP-09；其餘雲端 payload 清單需在正式 transport 前由 ADR 決定。
- Sync coordinator 由上層工作排程器呼叫；背景自動派送與 connectivity listener 尚未接線，沒有聲稱離線期間即時自動同步。

## 建議後續

**下一個 WP：WP-09**，先依 ADR-012 擴充 canonical progress transaction、receipt、候選衝突與兩 session sequence。WP-09 前先由決策人處理 ADR-010/011/017/018 的 production FlutterFire 前置條件；未完成時仍可用本地 outbox contract/fake 進行 progress 邏輯測試，不要把本 handoff 的 emulator-only status 說成 production sync。
