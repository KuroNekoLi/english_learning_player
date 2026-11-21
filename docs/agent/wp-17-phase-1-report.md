# WP-17 第一段交棒：Web 入口與 Drift smoke

日期：2026-11-21。分支：`codex/wp-17-web-smoke`。基準：`057ce4b`。本段僅建立 Web scaffold、鎖版 Drift/WASM 資產、Web DB adapter 與獨立 smoke target。未接入媒體選檔、播放、OAuth、同步或完整 Web App。未建立雲端資源。

## 實作契約

- `LocalDatabase` 只持有共用 Drift schema/executor。原生 `AccountDatabaseService` 保留檔案路徑及 scope 契約，並在原生 service 建立 `NativeDatabase`。
- `WebAccountDatabaseService.open(AccountScope)` 使用 `english_learning_player_<storageKey>` 作穩定資料庫名，URI 由 `Uri.base.resolve()` 解析，支援部署 base path。
- `WebAccountDatabase.storageIsSafeForWrites` 僅允許 `opfsShared`、`opfsLocks`、`sharedIndexedDb`。`unsafeIndexedDb` 和 `inMemory` 在 smoke 顯示限制，不執行會建立 device identity 的 Repository 寫入。
- smoke 透過現有 `SqliteProgressRepository.deviceId()` 寫讀，不另造 schema，也不改 `AccountScope`、schema v7 或 Repository。

## 實際驗收證據

- 工具鏈：Flutter 3.32.2、Dart 3.8.1；Drift lockfile 為 2.31.0、sqlite3 為 2.9.4。未修改 SDK 或 pubspec 版本。
- Chrome：Google Chrome 157.0.8103.80。localhost smoke 編譯及執行成功。
- Drift 回報 `sharedIndexedDb`，缺少 `dedicatedWorkersInSharedWorkers`、`sharedArrayBuffers`，但此模式由 shared worker 協調跨分頁存取。
- `drift_worker.dart.js` GET 200，`sqlite3.wasm` GET 200、MIME `application/wasm`。
- `local-default` 與 `web-smoke-secondary` 產生不同 database name 及不同 device ID，隔離檢查為 true。
- 首次載入、重新載入後仍讀到既有 `local-default` device ID。兩個同 origin 分頁同時開啟後讀到相同 `local-default` device ID，第二個 scope 仍為不同 ID。
- 格式檢查 PASS，Flutter Analyze 無問題，Flutter Test 152 passed、2 skipped。
- `flutter build web --no-pub --target tool/web_db_smoke.dart` PASS。
- 完整入口 `flutter build web --no-pub` FAIL：`main.dart → library_page.dart → library_view_model.dart → account_database_providers.dart → account_database_service.dart → drift/native.dart` 引入 `dart:ffi`，dart2js 無法編譯。此為下一段需處理的平台接線缺口。
- Chrome 驗收截圖：`/tmp/elp-web-smoke-tab1.png`。

## 狀態

- **PASS**：WP-17 smoke Web build、worker/WASM 載入、WASM MIME、瀏覽器 DB mode、scope 隔離、reload 持久性、雙分頁同時開啟、mode write guard 單元測試。
- **FAIL**：完整入口 `flutter build web --no-pub`，原因為原生資料庫 service 導入 `dart:ffi` 路徑。
- **BLOCKED／未完成**：T-WEB-01 完整 App build 需在第二段隔離原生 DB／AudioService／平台 plugin 接線後重驗。Smoke PASS 不代表完整 App Web build 可用。
- **未宣稱**：Safari／Firefox、正式 HTTPS、跨來源隔離 headers、媒體檔案持久化、音訊播放、Google OAuth、雲端同步。

## 下一段前置條件

第二段 WP-17 需先盤點媒體選取及播放路徑中 `dart:io`、`File`、`Directory` 的邊界，新增瀏覽器檔案選取與 OPFS／IndexedDB 媒體 adapter，再以合成音檔／SRT 驗證寫入中斷、配額失敗、去重、離線重開與 Blob URL 生命週期。啟用完整 Web app entry 時需把 AudioService 初始化改為條件化 adapter，維持原生啟動路徑不變。本段不預先修改這些功能。
