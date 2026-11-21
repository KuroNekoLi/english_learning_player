# WP-17 第二段交棒：Web 教材庫、媒體與播放

日期：2026-11-21。分支：`codex/wp-17-web-smoke`。基準：`5eea693`。本段只接入 Web 本機教材庫、檔案選取、瀏覽器私有媒體副本與既有播放器；未實作 Web OAuth、正式同步、資料夾監看或雲端資源。

## 實作與介面

- `AccountDatabaseOpener.openDatabase(AccountScope)` 將 Repository 上游與平台資料庫解耦。條件匯入保留原生 `AccountDatabaseService`，Web 使用 `WebAccountDatabaseService` 與既有 `LocalDatabase` schema。Web 寫入只接受 Drift 回報的安全持久模式。
- `MediaStore.copyAndHash(AudioImportSource, verifyBeforePublish)` 與 `MediaStore.open(relativePath)` 將媒體副本和平台檔案 API 隔離。原生由 `AppMediaStore` 實作，Web 由 `WebMediaStore` 實作；Web 先寫 OPFS，失敗時退至 IndexedDB Blob。Web 路徑以 `AccountScope.storageKey` 隔離。
- `AudioFilePicker.pickMediaFiles()` 的 Web 實作支援手動選擇 M4A、MP3、SRT，沿用 `MediaSelectionImportService`、現有 SHA-256 與字幕檔名配對流程。
- `MaterialPlaybackService` 經 `MediaStore` 取得播放 URI，由 `AudioEngine`/`JustAudioAdapter` 載入 Blob URL。來源替換、卸載及 dispose 會釋放 Blob URL；字幕查詢失敗也會立即釋放。
- `lib/main.dart` 依平台條件進入原生或 Web 啟動路徑。Web 顯示教材庫並導向既有播放器，不初始化原生 AudioService。

## 實際驗收

- `dart format --output=none --set-exit-if-changed .`：PASS，163 files，0 changed。
- `flutter analyze --no-pub`：PASS，No issues found。
- `flutter test --no-pub`：PASS，156 passed、2 skipped（Firebase Emulator 測試）。
- `flutter test --no-pub --platform chrome test/web/web_media_store_browser_test.dart`：PASS，5 tests。
- `flutter build web --no-pub`：PASS，正式入口建置成功；Flutter 顯示 CupertinoIcons 字型未納入的 warning，不阻止 build。
- `flutter build web --target tool/web_media_import_smoke.dart --pwa-strategy offline-first --no-web-resources-cdn --no-pub`：PASS，Chrome 驗收入口建置成功，並將 SQLite WASM / CanvasKit 納入本地資源。
- `flutter build macos --no-pub`：PASS。Xcode 顯示 Pods deployment target 與多個 My Mac destination warnings，不阻止 build。
- `git diff --check`：PASS。
- 真實 Chrome 157 localhost T-WEB-03/04 smoke：PASS。最終輸出：`PASS | DB=sharedIndexedDb | media=opfs | failureRecovery=PASS | dedupe=PASS | reload=PASS | bookmark=PASS | resume=PASS | gesturePlay=PASS | sentenceLoop=PASS | offlineShell=PASS | offlineMediaPlayback=PASS`。使用隔離 profile；先注入 OPFS 寫入失敗，確認匯入失敗不建立教材/outbox，再完成教材與雙語 SRT 匯入及 SHA-256 去重。頁面 reload 後確認收藏與 80 ms 確認進度還原、MP3 解碼與 seek；使用 CDP 可信滑鼠事件播放，觀察 150 ms 單句循環回跳；切斷網路後 reload，Service Worker 控制頁面並從本機 Drift/OPFS 恢復，第二次可信點擊後播放位置前進。
- Stage 1 實際 Chrome 的 Drift worker、WASM `application/wasm`、雙分頁協調及資料庫持久性證據仍見 [WP-17 第一段交棒](wp-17-phase-1-report.md)。

## Gate 狀態

| 項目 | 狀態 | 證據與限制 |
|---|---|---|
| T-WEB-01 完整 Web 入口/build | PASS | 預設 `lib/main.dart` 成功建置；本段 Chrome app smoke 可載入。worker/WASM 狀態沿用第一段 Chrome 證據。 |
| T-WEB-02 Drift、scope、重新載入 | PASS（本段範圍） | 實際 Chrome 在 browser reload 後讀回教材與雙語字幕；`sharedIndexedDb`。兩分頁同步與 migration fixture 依第一段報告，未在本段重跑。 |
| T-WEB-03 私有媒體、匯入與去重 | PASS（Chrome 範圍） | 5 個 Chrome browser tests 驗證 OPFS、scope 防護、OPFS 寫入失敗後實際 IndexedDB fallback、IndexedDB 寫入重試及中斷來源 stream 重試。真實 app smoke 注入媒體寫入失敗，確認沒有教材或 outbox 殘留；空選取無副作用；後續匯入、字幕配對與 SHA-256 去重成功。故障透過注入錯誤模擬，未耗盡實體瀏覽器配額。 |
| T-WEB-04 播放及離線 | PASS（Chrome/合成 MP3 範圍） | 真實 Chrome trusted click 啟動 just_audio_web 播放，快照觀察到 150 ms 單句循環回跳；驗證 seek/decode、reload 後恢復 80 ms 確認進度與 bookmark。CDP 切離線後 reload，頁面由 Flutter Service Worker 控制並恢復 Drift、字幕、收藏、進度與 OPFS Blob；再次由使用者手勢播放且 position 前進。驗證的是瀏覽器播放 pipeline，未以耳機／喇叭人工聽音確認。 |
| T-WEB-05 Google OAuth／切帳號 | BLOCKED／後續段落 | 本段未接 OAuth，未改 Firebase 設定。 |
| T-WEB-06 同步與瀏覽器矩陣 | BLOCKED／後續段落 | 尚無 Web 雲端傳輸、Mac/Web 跨裝置驗收、Safari/Firefox 實測。 |

## 限制與下一段

- IndexedDB fallback 目前會將整個媒體檔案暫存於記憶體；大檔案可能造成記憶體壓力。已驗證 fallback 與重試，不代表已驗證真實配額耗盡或大檔案容量上限。
- 本段未驗證 Android、iOS build。macOS build 為原生接線回歸，非真機播放驗收。
- WP-17 OAuth 階段可開始：先實作 Google Web OAuth、UID scope 隔離與登入/登出測試，再按官方 Firebase 專案設定驗證。不得把目前的 smoke Firebase/OAuth 測試視為 OAuth 已接線。
- Safari/Firefox、真實 M4A 解碼、大檔案/實際 storage quota exhaustion，以及人工聽音仍未驗證；應保留為後續跨瀏覽器和媒體矩陣項目。

未建立 Firebase/Web 雲端資源，未變更計費、OAuth 網域或認證設定，未 push 或 merge。
