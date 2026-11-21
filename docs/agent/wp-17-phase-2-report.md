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
- `flutter test --no-pub --platform chrome test/web/web_media_store_browser_test.dart`：PASS，2 tests。
- `flutter build web --no-pub`：PASS。Flutter 顯示 CupertinoIcons 字型未納入的 warning；不阻止 build。
- `flutter build macos --no-pub`：PASS。Xcode 顯示既有 Pods deployment target warning；不阻止 build。
- `git diff --check`：PASS。
- 真實 Chrome localhost smoke：PASS。輸出：`WP17_WEB_MEDIA_SMOKE PASS | DB=sharedIndexedDb | media=opfs | audio=1 | subtitleTracks=2 | browserReload=PASS | dedupe=PASS | decode=PASS | seek=PASS`。Smoke 使用合成 MP3 和兩份 SRT，先匯入並關閉頁面，再由 `location.reload()` 重開資料庫、恢復字幕及媒體、重複匯入同一來源並確認去重，最後由 JustAudioAdapter 解碼並 seek。
- Stage 1 實際 Chrome 的 Drift worker、WASM `application/wasm`、雙分頁協調及資料庫持久性證據仍見 [WP-17 第一段交棒](wp-17-phase-1-report.md)。

## Gate 狀態

| 項目 | 狀態 | 證據與限制 |
|---|---|---|
| T-WEB-01 完整 Web 入口/build | PASS | 預設 `lib/main.dart` 成功建置；本段 Chrome app smoke 可載入。worker/WASM 狀態沿用第一段 Chrome 證據。 |
| T-WEB-02 Drift、scope、重新載入 | PASS（本段範圍） | 實際 Chrome 在 browser reload 後讀回教材與雙語字幕；`sharedIndexedDb`。兩分頁同步與 migration fixture 依第一段報告，未在本段重跑。 |
| T-WEB-03 私有媒體、匯入與去重 | BLOCKED（部分通過） | Chrome 驗證 OPFS 寫入、帳號路徑拒絕、SHA-256 相同來源去重及字幕自動配對。IndexedDB Blob fallback、配額不足、使用者取消、關頁中斷及 partial copy 清理沒有實際故障注入，不能標完整 PASS。 |
| T-WEB-04 播放及離線 | BLOCKED（部分通過） | Chrome 驗證真實頁面 reload 後可取得 Blob、MP3 解碼與 seek。尚未驗聲音輸出／使用者手勢播放、單句循環、收藏續播、斷網重開，以及 PWA/App shell 離線載入。 |
| T-WEB-05 Google OAuth／切帳號 | BLOCKED／後續段落 | 本段未接 OAuth，未改 Firebase 設定。 |
| T-WEB-06 同步與瀏覽器矩陣 | BLOCKED／後續段落 | 尚無 Web 雲端傳輸、Mac/Web 跨裝置驗收、Safari/Firefox 實測。 |

## 限制與下一段

- IndexedDB fallback 目前會將整個媒體檔案暫存於記憶體；大檔案可能造成記憶體壓力。需在 T-WEB-03 fallback 及配額測試後決定是否採 chunked fallback 或限制檔案大小。
- 本段未驗證 Android、iOS build。macOS build 為原生接線回歸，非真機播放驗收。
- 下一個工作包建議接 WP-17 第三段：Firebase Google Web OAuth 與 UID 切帳號；之後獨立執行第四段 Web 傳輸、同步 Emulator、瀏覽器矩陣與 Mac → Web/Web → Mac 驗收。繼續前應先補 T-WEB-03 fallback/失敗復原及 T-WEB-04 聲音播放／離線驗證。

未建立 Firebase/Web 雲端資源，未變更計費、OAuth 網域或認證設定，未 push 或 merge。
