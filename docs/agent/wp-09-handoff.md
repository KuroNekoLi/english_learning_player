# WP-09 交棒：進度同步與衝突處理

- 日期：2026-11-17
- 分支：`codex/wp-09-progress-sync`
- 基準：WP-08 `038772829e76bf9cef850f344ce7d37c931b6443`
- 範圍：SQLite v5 local checkpoint/canonical/conflict/outbox、播放器 checkpoint 與 resume、ADR-012 fake transaction contract。沒有開始 WP-10。

## 交付介面

- `ProgressRepository.recordCheckpoint(stream, positionMs, state, nowMs)`：同一 SQLite transaction 寫 progress outbox payload 與遞增的 session sequence；使用該 session 已確認的 baseRevision。
- `ProgressRepository.canonical(materialId)`、`mergeRemoteCanonical(checkpoint, revision, nowMs)`：只接受 owner 範圍內已確認 canonical；revision 不倒退。merge 不呼叫 AudioEngine。
- `ProgressRepository.unresolvedCandidates(materialId)`：取得待使用者選擇的衝突位置。
- `ProgressRepository.resolveCandidate(...)`：產生含 candidateId/觀察 revision 的 immutable `resolveProgress` outbox；收到交易 ack 前不改 canonical、不隱藏候選。
- `ProgressSyncTransport.commit(uid, opId, payloadHash, checkpoint, resolution?)`：正式 adapter 必須以單一服務端交易處理 receipt、session high-water、canonical revision 與 resolution candidate。
- `ProgressSyncCoordinator.runOne()`：UID + cloud consent 閘門、resume auth queue、claim progress op、送出/應用 ack；暫時失敗指數退避，8 次後 needsAttention，可用相同 opId 手動 retry。
- `PlaybackProgressRecorder`：snapshot 15 秒 checkpoint；seek/pause/material change/lifecycle dispose 可強制 checkpoint。

## 本機資料與播放器行為

- Drift schema v5 新增 `playback_progress`、`progress_stream_state`、`progress_conflicts`、`progress_device_identity`；v4→v5 migration 不重寫教材與 WP-08 material outbox。
- `sync_outbox` 仍共用穩定 owner/opId/hash 欄位；WP-08 `SqliteSyncOutbox.claimNext` 限定 `entity_type='material'`，不會把 progress payload 送入媒體上傳流程。
- 每個 player open 使用新的 session UUID；profile DB 持久化 device UUID。正常開啟讀取本機已確認 canonical；有 `initialCueId` 時以明確 cue 導航為準。雲端 snapshot merge 不會觸發播放中的 seek。
- 同步 consent 關閉時不 claim 操作，原 outbox 保留。沒有同 UID auth 時不派送；同 UID 恢復後可 resume。資料庫與 Device ID 依 AccountScope 隔離。

## 測試對照

`test/features/progress/progress_sync_test.dart` 覆蓋：原子 checkpoint/outbox；canonical/sequence；離線衝突候選；remote merge 不需播放依賴；receipt replay/hash mismatch；candidate resolve 需交易確認；auth/consent 閘門；8 次 retry/同 opId 手動重試；重開 DB/device ID/帳號隔離；v4→v5 migration；15 秒與事件 checkpoint。`test/features/player/player_page_test.dart` 增加正常開啟 canonical resume、cue seek checkpoint，並驗證活動播放收到 remote canonical merge 時不 seek。

## 驗收結果

- `dart format --output=none --set-exit-if-changed .`：**PASS**，68 Dart files、0 changed。
- `flutter analyze`：**PASS**，No issues found。
- `flutter test --reporter expanded`：**PASS**，91 tests。
- `git diff --check`：**PASS**。
- Android/iOS/macOS builds：未執行；WP-09 只新增 Flutter/Dart 資料與狀態邏輯，沒有原生 adapter 變更。真機 lifecycle/跨裝置雲端驗證列 BLOCKED。
- 未建立 Firebase 專案、未啟用或觸發雲端付費資源。

## 阻擋與風險

- **BLOCKED：Firebase transaction / rules adapter 與真實跨裝置測試。** `ProgressSyncTransport` 已定義契約，測試使用 `FakeProgressLedger`；WP-08 handoff 的 FlutterFire Apple/Core 設定仍受 ADR-005/010/011/017/018 阻擋。尚未建立 Firebase 專案或任何雲端計費資源。
- **BLOCKED：真機播放/lifecycle smoke 與 Android/iOS/macOS build。** 本 WP 的 flutter unit/widget test 未驗證三平台 plugin 或實機 lifecycle。
- resolution 的正式 Firestore adapter 必須原子檢查 observed canonical revision 和 candidateId；如失效，回傳最新 canonical 並保留候選。不得以 client time 或 position 大小裁決。

## 後續建議

下一個相依高風險工作是 **WP-13**：多裝置離線交錯、登入切換、拒絕權限與播放中的 no-seek 整合測試；在配置正式 adapter 前，先處理 ADR-010/011/017/018 外部前置條件。不要將 fake ledger 測試描述為 Firebase transaction 已驗證。
