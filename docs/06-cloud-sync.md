# Firebase 跨裝置同步規格

## 1. 責任與順序
本機 Repository 更新 → transaction 寫 SQLite + SyncOutbox → SyncCoordinator 消費佇列 → Firebase Auth 身分檢核 → Storage 媒體傳輸 → Firestore metadata 交易/寫入 → 其他裝置前景重新整理或下載 → 本機 Repository merge → UI。

音檔與字幕二進位放 Cloud Storage，metadata/進度/收藏放 Firestore；不得將大型 base64 直接塞 Firestore。

內嵌雙語 SRT 的兩個語言軌可以共用原始檔案內容。字幕 manifest 的選用欄位 `cueProjection` 記錄 `bilingual`（下載後以本機相同規則取出對應語言）或 `original`（使用解析後的原字幕）。舊 manifest 未記錄此欄位時，英中軌的 SHA-256 相同才嘗試拆軌。發布會寫入此欄位的客戶端前，需先部署支援此欄位的 Firestore Rules。

字幕儲存時在同一筆 SQLite 交易中排入 `publishSubtitles`。新增或修改選中的字幕會更新該教材的待送工作。工作領取後讀取當下選中的字幕軌，並在同帳號的 `uploadMaterial` 完成後發布。下載到本機的教材和字幕仍只寫入快取。本機資料庫 v6 → v7 會為既有本機來源教材的已選字幕補排。暫時失敗使用既有 lease 與重試間隔。撤回同意時交還工作，待同意後再次同步。

## 2. 可靠性契約
- 每項 outbox 有 `opId`（冪等）、`entityId`、`revision`、`attempts`、`nextRetryAt`、`lastError`。
- 連線錯誤採 exponential backoff + jitter，認證錯誤暫停待登入；對明確不可重試的權限錯誤展示原因。
- 媒體先上傳校驗 SHA-256、內容型態與大小，再發佈 `cloudReady` metadata；不可先寫可下載但缺檔案的資料。
- 手機預設「按需下載」；顯示 cloud-only/downloading/local-ready/error 狀態；本機快取容量上限可設定。
- 雲端資料與本地資料分層；FireStore 的離線快取不能取代檔案快取和 outbox 冪等操作。
- 來源檔案被移除：標記 sourceMissing；除非使用者明確執行刪除，不刪雲端資產或收藏。

重試分類、jitter、持久化 lease 與重送規則見 [ADR-009](12-decisions-and-risks.md)。

## 3. 播放進度合併（ADR-012）
| 情境 | 規則 |
|---|---|
| Mac 暫停、iPhone 尚未播 | iPhone 開啟時讀取已確認的 Mac 進度 |
| Mac 與 iPhone 同時播放 | 正在播放的一方不被遠端更新強制 Seek |
| 同一 session 連續更新 | sequence 遞增，過期 sequence 不覆蓋較新值 |
| 離線 A 停在 5m，線上 B 停在 12m | A 恢復上線時保留候選衝突，不能無條件覆蓋 B |
| 兩候選無法排序 | 顯示選擇上次播放位置，選擇後才寫 canonical 版本 |
| 裝置時間不準 | 不以 client clock 作唯一依據 |

每筆 checkpoint 保存上次確認的 canonical revision。提交交易先查 opId receipt、再檢查該 session 的 sequence 及 baseRevision，版本不同時保留候選。純 Dart 規則已有測試，交易、Rules 與兩裝置整合由 WP-08／09／13 驗證。見 [ADR-012](12-decisions-and-risks.md)。

WP-09 的本機實作以 `ProgressRepository` 原子保存 checkpoint 與 `sync_outbox`。上層透過 `ProgressSyncTransport` 將穩定 opId/hash、checkpoint 和可選的 candidate resolution 送入伺服器交易；只有交易回覆後才更新本機 canonical 或標記候選已解決。PlayerViewModel 在正常教材開啟時讀取已確認 canonical；播放器執行中只合併資料，不將遠端 snapshot 回送為 seek 命令。正式 Firestore adapter/Rules 尚未接線，fake transaction 僅驗證契約。

預設每 15 秒寫本地 checkpoint 並排隊；暫停、seek 完成、切教材與生命周期退出寫 checkpoint。是否每 15 秒上傳遠端取決於前景/電量/成本；應合併 outbox 同實體連續進度。不要無限制每幀寫 Firestore。

## 4. 使用者與資料安全
- Firebase Auth UID 是每個路徑授權核心；Auth providers（Apple/Google/Email）由 ADR 決定。不同 Apple/Google 帳號要有安全明確的 Link Account 流程。
- Firestore/Storage Security Rules 拒絕讀寫其他 UID，限制文件允許欄位與可變更欄位；拒絕未登入用戶訪問私有教材。
- 使用 Firebase Emulator 寫正向、反向和隨機 UID 嘗試；不得只靠 Flutter UI 隱藏資料。
- Storage 不使用永久公開下載 URL；下載方式需驗證授權、Token 有效期限與快取安全。避免在 log 印出登入憑證與簽署 URL。
- 上傳大小限制與 Blaze 支出風險必須在上線前確認；使用者必須知道匯入教材會上傳至所選雲端帳號。

## 5. 觀察與重試
每一教材展示最後同步時間、cloud ready 或 error、失敗原因、手動重試；App 網路恢復觸發 outbox 重送，重啟後不遺失。匿名 telemetry 需另行同意；不得記錄字幕全文。

## 6. 最小整合測試
- A 裝置上傳同一內容兩次 → 僅一份對應資產。
- 模擬上傳成功但 Firestore 寫入失敗 → 重試成功，不會產生重複教材。
- 使用者 A 無法讀取 B 的 Storage/Firestore。
- 手機斷線收藏 2 句 → 復線後保留且不重覆。
- 登出 A 登入 B → 不能看到 A 私人教材或傳輸隊列。
- A/B 交錯播放進度測試，不發生意外 Seek。
