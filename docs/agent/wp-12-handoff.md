# WP-12 交棒摘要：資料夾掃描重整

## 完成範圍

- 新增 `FolderImportReconciler`，透過 `FolderAccessGateway` 取得完整 inventory、交由 WP-02 `AudioImportService` 匯入 app-private media / material / material outbox，並呼叫 WP-03 `SubtitleFilenameMatcher`、`SubtitleImportService` 處理已到或晚到字幕。
- 新增 `FolderReconciliationRepository` 契約及 SQLite 實作。Drift schema v6 新增 `playlists`、`playlist_entries`、`folder_source_entries`；owner 複合鍵/外鍵限制每個 account namespace。v5→v6 migration 只新增表，不修改既有 material / bookmark / progress。
- Library 的 Mac folder panel 新增「匯入並更新清單」操作與結果摘要。
- 從 Library 使用「匯入資料夾」時，選取的來源資料夾會成為教材庫分類根資料夾，inventory 中的相對目錄會建立為巢狀分類，音訊教材加入對應分類。使用 binding + 相對目錄計算穩定分類 ID，重掃重用分類；單檔複製進度顯示在 Library 既有匯入卡片中。空的巢狀來源目錄不會建立，因原生 inventory 僅回傳檔案。
- 本機來源相對路徑留在 account DB，不進 material outbox 或 remote payload。來源唯讀；掃描缺席不刪 material、playlist entry、bookmark 或 progress。

## 對外介面

- `FolderImportReconciler.reconcile()` → `FolderReconciliationResult`，回報音訊新增／rename 沿用／重複、字幕新增、待下載、歧義、失敗與來源缺席數。
- `FolderReconciliationRepository.listFolderSources(bindingId)` → 本機來源記錄。
- `FolderReconciliationRepository.saveFolderSource(...)` → 寫入/更新 account-scoped source mapping。
- `FolderReconciliationRepository.finishFolderScan(bindingId, inventoryPaths)` → 完整掃描完成後，只將本次 inventory 不含的舊來源標記缺席。
- `FolderReconciliationRepository.addToFolderPlaylist(...)` → 冪等加入固定來源 playlist；不因來源缺席移除 entry。

## 決策與限制

- scan 失敗時不呼叫完成掃描狀態更新；未完整 inventory 不得推導刪除。`pendingDownload` 保留來源存在狀態。
- rename 只在同一 binding 中找到唯一的舊缺席路徑及相同 SHA-256 時沿用 `materialId`；多候選視為歧義並依來源建立獨立 material，符合 ADR-020。`FolderEntry` 沒提供穩定 file resource ID，故無法證明同內容新檔究竟是 rename 或新來源；見 ADR-028，此為已記錄限制。
- late SRT 在下一次 reconcile 匯入。字幕候選歧義跳過；已選 manual track 的 basename 優先，自動配對不可覆蓋手動選取；相同 basename + 原始 bytes 不重複建 track。
- **遠端 playlist/folder metadata 尚未實作。** 現有 `SqliteSyncOutbox.claimNext` / `CloudSyncCoordinator` 僅派送 material；此 WP 沒有新增無消費者的 outbox 操作，亦未連 Firebase、建立雲端資源或產生費用。需要核准 playlist schema / Rules / transport 後再補。
- 只使用 Fake Gateway 與合成 bytes，未選取真實 iCloud 資料夾；WP-11 的 native folder permission / iCloud placeholder OS smoke 狀態不因本地測試改變。

## 測試與建置

- `dart format --output=none --set-exit-if-changed .`：PASS（82 files，0 changed）。
- `flutter analyze`：PASS（No issues found）。
- `flutter test`：PASS（109 tests）。新增 WP-12 6 項：late SRT/reopen + playlist/material outbox assertions、unique rename + favorite retention、ambiguous rename、scan failure、pending download、v5→v6 migration。
- `flutter build macos --release`：PASS，產物 `build/macos/Build/Products/Release/english_learning_player.app`。
- `flutter build ios --simulator --debug`：PASS，產物 `build/ios/iphonesimulator/Runner.app`。
- `flutter build apk --debug`：預設 Android Studio JDK 25 首次 FAIL（Gradle 回報 `25.0.4`）；使用既存 `/tmp/wp11-flutter-config`（`XDG_CONFIG_HOME`，JDK 17）重跑 PASS，產物 `build/app/outputs/flutter-apk/app-debug.apk`。本次未寫入全域 Flutter 設定。建置保留 NDK 26.3 vs plugins 建議 27.0 warning，沒有改動 Android NDK 設定。
- `git diff --check`：PASS。
- 未執行真實 iCloud 授權/placeholder、真機播放或遠端 playlist metadata；後者目前缺少已核准 transport/schema，標 BLOCKED。

## 修改檔案

- `lib/core/db/local_database.dart`
- `lib/features/library/material_repository.dart`
- `lib/features/library/data/sqlite_material_repository.dart`
- `lib/features/library/services/folder_import_reconciler.dart`
- `lib/features/library/folder_source_view_model.dart`
- `lib/features/library/folder_source_panel.dart`
- `test/features/library/folder_import_reconciler_test.dart`
- `docs/02-domain-models.md`
- `docs/07-icloud-folder-sync.md`
- `docs/11-work-packages.md`
- `docs/12-decisions-and-risks.md`
- `docs/README.md`

## Stage 3 重驗

- 啟動還原授權、重新掃描、FSEvents 防抖通知及 App 執行期間每五分鐘的補掃，均以完整 inventory 執行本機 reconcile。同一畫面的請求依序執行，解除授權會取消排隊的掃描並等待當輪結束。非預設帳號使用各自的授權鍵。
- 字幕限定與音訊位於同一子目錄。暫存副本用畢會回收。相同教材在同一輪最多被一個新路徑當作改名來源。
- 正常 Riverpod 入口的測試使用 SQLite、帳號私有媒體與 fake folder gateway。已驗證還原授權後自動匯入、監看後補字幕、同名子目錄隔離、兩筆教材各有一筆 outbox、暫存回收。
- BLOCKED：現有 app 未接 Firebase transport，遠端 playlist／folder metadata 仍待 ADR-028 的資料契約及發佈路徑。缺少下載完成的合成 iCloud 教材供原生掃描到實際播放的驗收。
- 重驗 PASS：Dart 格式、Flutter Analyze、Flutter Test 全量 115 項，其中 Library 專項 20 項均通過。
