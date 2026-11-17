# WP-13 交棒：進度同步安全與離線交錯

- 日期：2026-11-17
- 分支：`codex/wp-13-sync-safety`
- 基準：WP-12 `34273df4f5592acfb45bffce6fe1a16ee9ddd0bd`
- 範圍：只補 WP-13 的本機/Fake transport 整合測試與同步 coordinator UID 守門；沒有開始 WP-14。

## 實作與行為

- `ProgressSyncCoordinator` 在 consent 檢查後、resume 後、claim 後及 commit ack 前重驗身份 UID。切帳號時不開始新傳輸；已 claim 的操作改為 `waitingForAuth`，保留同一 opId。原 UID 恢復後重送同一 opId，fake receipt 證明不重複套用。
- 權限拒絕為永久失敗：`needsAttention`、attempts 不增加、canonical 不變；暫時性錯誤沿用 ADR-009 退避與 8 次上限。
- 兩個獨立本機資料庫模擬同 UID 不同裝置離線，各自從 revision 0 排入 checkpoint。Fake ledger 先接受一筆，後一筆保留為衝突候選，不以 client 時間或位置大小覆寫 canonical。
- WP-12 遠端 playlist/folder metadata 已依使用者要求記為後續整合項，更新在 `docs/11-work-packages.md` 與 ADR-028；此項不納入 WP-13。後續需核准資料 schema、Rules/授權與 transport，並禁止同步本機相對路徑或 security bookmark。

## 涉及介面

- `ProgressSyncCoordinator.runOne()`：同 UID + consent gate、progress outbox claim、transport commit、身份重驗、canonical/candidate ack。
- `ProgressSyncTransport.commit(uid, opId, payloadHash, checkpoint, resolution?)`：本 WP 只用 fake ledger。正式 transport 必須把目前登入 UID 和寫入 UID 綁定，並在服務端原子執行 ADR-012 receipt/sequence/revision/resolution 規則。
- `ProgressRepository.waitForAuthentication(opId, now)` / `resumeAuthenticated(now)`：切換時保留操作，不遺失 opId。

## 測試對照

`test/features/progress/progress_sync_test.dart` 新增五項：

1. 兩裝置離線 checkpoint 交錯提交後，一筆維持 canonical、另一筆保存 unresolved candidate。
2. consent check 期間 UID 由 A 切至 B 時不 claim/派送，操作仍 queued；A 恢復後可提交。
3. claim 後、transport 前 UID 由 A 切至 B 時操作進 `waitingForAuth` 且不派送；A 恢復後可提交。
4. Fake transport 已提交但回覆前切至 B 時不套用本機 ack；A 恢復後相同 opId 回放 receipt，canonical 安全更新。
5. permissionDenied 進 `needsAttention`，attempts=0，canonical 不變。

既有 WP-09 測試仍覆蓋 sequence/baseRevision、candidate resolve、receipt/hash mismatch、transient retry、登入/consent、DB 重開及 account-scope 隔離；`test/features/player/player_page_test.dart` 驗證遠端 canonical 更新不在播放中觸發 seek。

## 驗收

- `dart format --output=none --set-exit-if-changed .`：PASS（82 Dart files，0 changed）。
- `flutter analyze`：PASS（No issues found）。
- `flutter test`：PASS（114 tests）。
- `git diff --check`：PASS。
- Firebase Emulator、Firestore/Auth 正式 adapter、Rules 與兩實機交錯：BLOCKED，未配置 Firebase 專案，沒有雲端計費資源。
- WP-12 遠端 playlist/folder metadata：仍為後續整合項，不代表已送出雲端。
- 本 WP 沒有修改原生平台；本次不以 Dart tests 代替三平台 build 或真機同步驗證。

## 修改檔案

- `lib/features/progress/services/progress_sync_coordinator.dart`
- `test/fakes/fake_cloud_sync.dart`
- `test/features/progress/progress_sync_test.dart`
- `docs/11-work-packages.md`
- `docs/12-decisions-and-risks.md`
- `docs/README.md`
- `docs/agent/wp-13-handoff.md`

## Stage 3 重驗

- SQLite 在同一交易中先驗證回覆的 owner、教材、revision。不符時寫入待處理原因 `invalid_progress_receipt`，canonical 和候選維持原狀。衝突回覆僅能更新同一來源串流中序號較舊的候選。
- PASS：Dart 格式、Flutter Analyze、Flutter Test（116 項）。
- PASS：`npm run test:rules`（Corretto 21，demo project，4 項）。以本機 Firestore Emulator 的兩個 SDK client 執行參考交易，驗證同時提交形成一筆 canonical 與一筆候選、同 opId 回放、hash 變更拒絕、過期 sequence 不覆寫。以測試工具提供的規則停用 context 模擬受信任寫入者，並另用實際規則驗證一般 owner、其他 UID、匿名都無法直接改寫進度及 receipt。
- BLOCKED：通往受信任寫入者的正式 Flutter Auth／Firestore transport、正式規則與部署，以及 iPhone／Android 的實際離線交錯仍待整合。
