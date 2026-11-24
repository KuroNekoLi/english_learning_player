# 可拆派 Work Packages（WP）與驗收契約

**單位原則**：每 WP 含「接收 → 處理 → 輸出 → 驗證」，代碼與測試一起提交。依賴完成才開始下一 WP。目前的交付與驗收以各工作包交棒及 Gate 紀錄為準。

| ID | 階段/模型 | 依賴 | 輸入 → 處理 → 輸出 | 最低驗收 |
|---|---|---|---|---|
| WP-00 | S1 Sol High | 初始 repo | Flutter 專案 → SDK/套件/Android+iOS+Mac 相容性盤查 → versions/阻礙清單 | 真實 analyze/test/build 報告與可重現命令 |
| WP-01 | S1 Sol High | 00 | docs → 凍結 interface、schema、ADR、mock → 可測骨架 | AudioEngine/Repo/FolderGateway 假實作可被測試；未決明列 |
| WP-02 | S2 Luna High | 01 | 手動選檔 → copy/app support、hash、SQLite record → LocalReady Material | 重啟可載入；匯入重覆檔不重覆；跨帳號本機資料隔離 |
| WP-03 | S2 Luna High | 01,02 | SRT bytes + 音檔名稱 → parser/matcher/aligner → tracks/cues | T-SRT-01..09，手動優先與一對多驗證 |
| WP-04 | S2 Luna High | 01,02 | 播放命令 → AudioEngine/just_audio → snapshots | T-AUDIO-01..08，loop 取消、切換競態與倍速 |
| WP-05 | S2 Luna High | 03,04 | 播放與 cue → LearningSession reveal/loop → learning state | T-LEARN-01..05，next cue 重置字幕遮蔽 |
| WP-06 | S2 Luna High | 02-05 | models/state → Mobile/Mac responsive UI → Library/Player/Sheet | 320dp & 1280px、文字縮放、Widget tests |
| WP-07 | S2 Luna High | 03,06 | user bookmark action → SQLite anchor → Favorites playback | 重啟與字幕更新不遺失，能重定位 |
| WP-08 | S2 Luna High | 01,02 | LocalReady + Auth → Storage/Firestore outbox → CloudReady | Emulator 正反權限、斷線/重試/去重 |
| WP-09 | S2 Luna High | 04,08 | progress events → local checkpoint/outbox/merge → canonical progress | T-SYNC-01..10；不可遠端強制 seek |
| WP-10 | S2 Luna High | 04 | 音訊事件 → platform media session → background controls | Android/iOS smoke + Mac 限制清單 |
| WP-11 | S3 Sol High | 01,02,08 | Mac 用戶 folder 授權 → bookmark/scan events → Gateway result | 權限恢復/撤銷、部分下載、sandbox package |
| WP-12 | S3 Sol High | 03,08,11 | folder scan → reconcile playlist + import/outbox → remote metadata | 本機掃描重整／清單／素材 outbox 已完成；後續已接入 App 分類樹、教材歸屬及刪除標記的 Firebase 同步，正式跨裝置驗收待發布。來源綁定依裝置管理。晚到 SRT、rename、刪來源不刪收藏已自動測試 |
| WP-13 | S3 Sol High | 08,09 | 多裝置離線操作 → conflict/auth/queued writes → safe merge | 本機 fake ledger 交錯寫、consent 後/claim 後切帳號、提交後切帳號同 opId 回放、權限拒絕均已測；Firebase/實機跨裝置 BLOCKED |
| WP-14 | S3 Sol High | 06,10-13 | Mac iCloud folder → Firebase → iPhone / Android → 播放續播 | 實機 E2E 證據。Mac 原生匯入、Emulator 下載和本機雙 profile 接收已驗；iPhone／Android 完整鏈路 BLOCKED，見 [WP-14 交棒](agent/wp-14-handoff.md) |
| WP-15 | S4 Luna High | 02-14 | FR/fixtures → 回歸與失敗注入 → QA 報告 | docs/08 Gate D 的測試面向；各 FR 有結果 |
| WP-16 | S4 Sol High | 15 | code/data flow → 架構/安全審查 → findings + release decision | P0/P1 無隱藏 blocker，風險與決策可追 |
| WP-17 | 平台擴充 | 02–09、14 登入契約 | 瀏覽器選檔 → Drift WasmDatabase＋私有媒體儲存 → Google Web OAuth → Web 本機學習及同帳號同步 | T-WEB-01..06；Web build、離線升級、分頁與 UID 隔離、真實 Google OAuth、跨裝置續播及原生回歸。見 [Web 平台規格](14-web-platform.md)。 |
| WP-18 | Auth／同步安全 | WP-14、WP-17 | Google owner UID → Callable 建立獨立 Email/Password reader UID 並設定 owner claim → reader 唯讀下載 profile | 原生/Web 登入、Firestore/Storage deny-write Emulator 測試、Callable deny-write、reader 本機資料隔離；Console provider、allowlist UID、Rules/Functions 正式部署與真實登入另列 BLOCKED。見 [WP-18 交棒](agent/wp-18-readonly-account-handoff.md)。 |

## 工作包共通 Definition of Done
1. 產出既有模組介面可使用，不引入未核准的隱藏相依。
2. 至少一個成功、一個失敗、一個邊界案例可自動化測試。
3. 執行 `dart format`, `flutter analyze`, `flutter test`，並照實回報受影響的原生裝置與 Web 瀏覽器結果。WP-17 維護 Web 發布證據。
4. 影響資料模型與雲端規則需對應 migration / Emulator test。
5. 不編造資源、不引入真實教材或機密、不自行推送遠端。
6. 把未完成、阻礙與規格變更提議記到 ADR 或交棒摘要。

## 最佳切分與並行
- WP-03 Subtitle 和 WP-04 Audio 可在 WP-01 契約凍結、WP-02 fixture 存在後分支並行。
- WP-05 依賴兩者，WP-06 聚合其 state，不要 UI 先引入 player SDK。
- WP-08 的雲端暫用 FakeAuth/Emulator；WP-09 的競態在 Stage 3 再做真實跨裝置交錯測試。
- WP-11 Native Adapter 與 WP-12 ImportReconciler 要有 fake gateway，不能以 iCloud GUI 操作當唯一測試。
- 不以程式碼行數或 token 使用量當完成標準，只看行為與驗證證據。
