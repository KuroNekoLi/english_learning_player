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
- Firebase Storage 物件只允許 UID 擁有者讀取、上傳與刪除。因音訊及字幕物件路徑含 SHA-256，更新只允許 bytes 的 MD5/CRC32C 保持一致且保留 owner/hash 身分欄位；不同 bytes 必須以新雜湊建立新物件。App 刪除採教材刪除標記，媒體 GC 仍未提供。直接刪除 Storage 物件可能留下失效教材參照。

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

## 7. WP-17 同帳號自動同步

Web 與原生版共用教材佇列、Firestore 資料格式、Storage 路徑和 SHA-256 驗證。登入有同步設定的環境後，在帳號頁選擇「開啟同步」或「稍後」。SQLite v8 在此裝置以 Firebase 專案與 UID 保存選擇。尚未選擇、讀取失敗、登出與同步關閉都不派送雲端工作。離線帳號的匯入仍留在原本的教材庫。

啟用後，App 或網頁處於使用狀態時每五秒讀取本機待送佇列。有到期的音檔或字幕工作才進行上傳前的 Firestore 權限檢查和傳輸。App 重開或回到前景後會重查，傳輸重試以持久化佇列為準。系統暫停程式後，由下次啟動或回到前景接續。「立即同步」仍可手動觸發，與自動上傳共用傳輸工作。

接收裝置用同帳號在本機開啟同步後，自動載入雲端清單。帳號頁可按需下載音檔及已發布的字幕。使用中每兩分鐘重新整理，並補抓已下載教材晚發布的字幕。播放器下次開啟教材時讀取本機更新的字幕。

自動同步已開啟時，每次目錄刷新會比對本機教材；缺少的雲端教材會自動下載音檔、字幕與進度。教材庫以音訊匯入相同的教材卡片和圓形進度呈現下載；音檔完成後，字幕仍在取得時會在該教材卡片標示字幕下載狀態。傳輸錯誤保留失敗狀態，並在後續目錄刷新重試；沒有自動同步同意時不會下載。

瀏覽器從 OPFS 或 IndexedDB 讀取音檔，逐段產生 multipart Blob，並在送出前取得目前 UID 的 Firebase ID token。上傳沿用每檔 100 MiB 限制，Blob 組裝與大檔記憶體用量須在目標瀏覽器驗收。下載串流經原有校驗後寫入瀏覽器私有儲存。

本機驗收以 demo Firebase Emulator 的合成音訊驗證。正式環境需要同一 Firebase 專案中的 Firestore `(default)` 資料庫、已部署的 `firestore.rules` 和既有 Storage bucket。正式專案的 Firestore 和 Storage 先前已就緒，Web 開發來源 `http://localhost:7357` 已設定 Storage CORS。正式雙裝置收送仍待驗。進度同步另外需要已部署的 `syncProgress` Callable 與對應區域設定。

## 8. 教材分類、名稱與刪除同步

開啟自動同步的同一帳號，在支援此功能的裝置上共用 App 內的分類樹。雲端使用 `users/{uid}/libraryChanges/{field}_{entityId}`，記錄資料夾名稱、父資料夾、教材顯示名稱、教材分類歸屬及各自的刪除標記。分類使用穩定 ID，空資料夾和分組歸屬可先於音檔到達。SQLite v9 升級會補排此裝置既有的手動分類和成員。Mac 來源資料夾的存取權、書籤與路徑依裝置管理。

- 操作先寫本機並保留待送狀態，沿用前景自動同步與「立即同步」。每批最多 20 筆，暫時失敗排後續重試。同一欄位有新修改時，只確認已成功送出的操作 ID，保留尚未送出的版本。
- 名稱與位置分開合併。同欄位的離線衝突比較邏輯版本，再以操作 ID 排序。Firestore 寫入以讀取到的 `updateTime` 為前置條件，遇到競爭時重新讀取比較。多裝置同時移動導致循環時，循環內的資料夾顯示在首頁。[Firestore REST 寫入前置條件](https://firebase.google.com/docs/firestore/reference/rest/v1/Precondition)
- 資料夾刪除後，內容移至最近的上層可用資料夾或首頁。從資料夾內把教材移到另一資料夾會替換目前所在的分類，其他分類仍保留。移到首頁會移出所有分類。
- 教材刪除標記會持續生效，避免離線裝置重新顯示或下載已刪教材。收藏、學習紀錄和檔案內容保留，實體檔案回收仍由 ADR-019 追蹤。新版須先部署對應 Firestore Rules，且每台裝置都需更新 App。既有媒體文件格式不變。

## 9. `kuroneko_li` password 唯讀憑證（ADR-035）

- `kuroneko_li` 是現有 Google UID 上的 Email/Password credential，不建立第二個 UID。Firebase email 欄位使用固定 alias `kuroneko_li@english-learning-player-auth.firebaseapp.com`；使用者只在 UI 輸入 username。
- App 依帳號憑證提供唯讀標示與下載控制；安全邊界為 Firestore／Storage Rules 和 `syncProgress` Callable：只有該 email alias 且 `firebase.sign_in_provider=password` 時拒絕雲端寫入；同 UID 的 Google provider 保留寫入權。其他測試用 Email/Password 使用者不受此條件影響。
- 密碼登入建立獨立本機 `AccountScope`，雲端讀取仍以相同 Firebase UID 進行；reader outbox、進度、書籤與本機教材不會流入 Google writer 的本機資料庫。讀取的遠端進度只存到 reader profile。
- 當前 Rules/Callable 程式碼及 Emulator 測試已新增，但未部署；未啟用 Firebase Email/Password provider 或未部署服務端規則時，不可宣稱唯讀已生效。首次設定需 Google 登入原 UID、在 App 連結固定 username 與全新強密碼，然後以兩種登入方式驗證同一 UID 與寫入拒絕。
