# WP-17 Web 實作交棒

先執行「第一段」並回報驗收結果，再以新任務接續其他段落。主規格、對外支援範圍與完整發布門檻見 [Web 平台規格](../14-web-platform.md)。

## 開始前

1. 在 `/Users/linli/AndroidStudioProjects/english_learning_player` 執行 `git status --short --branch` 和 `git log -3 --oneline`。保留工作區已有的 WP-17 規格、其他人的修改與 `devtools_options.yaml`。先讀 [AGENTS.md](../../AGENTS.md)、[文件入口](../README.md)、[工作包](../11-work-packages.md)、[Web 規格](../14-web-platform.md) 與本交棒，使用專案工程、Flutter 架構與對應 Dart／Flutter 測試 Skill。
2. 基準 Flutter 3.32.2／Dart 3.8.1，`pubspec.lock` 固定 Drift 2.31.0／sqlite3 2.9.4。目前 `flutter build web --no-pub` 只到 `Missing index.html.`。先看實際 Git 和本機套件版本，若已有 `web/` 入口則沿用。相依套件衝突先回報具體 solver 訊息，SDK／套件升級另行決定。
3. 全程保留 `AccountScope`、`AudioEngine`、`LocalDatabase` schema 與 Outbox 語義。原生 `dart:io`／`drift/native.dart` 與瀏覽器 `package:web` 放在各自 adapter，透過 `dart.library.io`、`dart.library.js_interop` 條件匯入接線。使用者資料、原生 OAuth 憑證與真實媒體均留在 Git 及 Web 產物之外。第一輪使用 localhost 和合成資料。[Dart 條件匯入](https://dart.dev/tools/pub/create-packages#conditionally-importing-and-exporting-library-files)

## 第一段：Web 入口與 Drift 最小驗證

**只執行本段時**，交付可重跑的本機 DB smoke。播放、選檔、OAuth 與同步留到各自段落。

1. 為既有專案加 Flutter Web scaffold。若缺少 `web/`，用同一 SDK 在暫存專案產生模板，再只複製 `web/`。已在暫存目錄確認下方 `flutter create` 能產生 `web/index.html`。核對 `git diff --name-only`，避免模板覆寫原生 host、README 或 `pubspec.yaml`。

   ```sh
   template_dir=$(mktemp -d "${TMPDIR:-/tmp}/elp-web-template.XXXXXX")
   flutter create --no-pub --platforms=web --project-name english_learning_player "$template_dir"
   test ! -e web && cp -R "$template_dir/web" web
   ```

2. 依 lockfile 取官方 assets。以目前版本為例，[Drift 2.31.0 release](https://github.com/simolus3/drift/releases/tag/drift-2.31.0) 的實際檔名是 `drift_worker.js`，依本專案命名放到 `web/drift_worker.dart.js`。[sqlite3 2.9.4 release](https://github.com/simolus3/sqlite3.dart/releases/tag/sqlite3-2.9.4) 提供 `sqlite3.wasm`。兩個 release 的檔名已查證，兩個檔案的實際載入與相容性由本段驗證。

   ```sh
   curl -fL https://github.com/simolus3/drift/releases/download/drift-2.31.0/drift_worker.js -o web/drift_worker.dart.js
   curl -fL https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-2.9.4/sqlite3.wasm -o web/sqlite3.wasm
   shasum -a 256 web/drift_worker.dart.js web/sqlite3.wasm
   ```

3. 先追 `lib/core/db/local_database.dart`、`account_database_service.dart`、`account_database_providers.dart`。`LocalDatabase` 的建構子已接收 executor。把 `LocalDatabase.open(File)` 的原生初始化放到原生 adapter，保留 `AccountDatabaseService.open(scope)` 的既有原生路徑、交易與關庫行為。Web adapter 用 `WasmDatabase.open(databaseName: ..., sqlite3Uri: ..., driftWorkerUri: ...)`，將 `result.resolvedExecutor` 交給 `LocalDatabase`。資料庫名稱穩定以 `AccountScope.storageKey` 分庫，重整或換分頁不可產生新名稱。資產 URI 須保留 Flutter Web 部署的 base path。[Drift Web](https://drift.simonbinder.eu/platforms/web/)
4. 開庫後讀 `chosenImplementation`。接受實測可安全持久化的模式。`inMemory` 或未具備分頁隔離的 `unsafeIndexedDb` 要關閉寫入並顯示限制，不能回報離線持久化 PASS。記錄模式和 `missingFeatures`。保持 Drift 的既有儲存取用行為，首次實作維持 `moveExistingIndexedDbToOpfs` 預設，避免另啟瀏覽器儲存搬移。
5. 建一個範圍有限的 smoke 入口，建議放 `tool/web_db_smoke.dart`。它只引入 DB、`AccountScope` 和現有 Repository，在 `local-default` 測試 origin 以 `SqliteProgressRepository.deviceId()` 寫讀一筆，再用第二個合成 scope 比較不同 ID。`deviceId()` 會持久寫入，因此只在可安全寫入的模式執行。專案的 `main.dart` 目前會呼叫原生 `AudioService.init`；smoke 不需要載入播放器、資料夾 gateway 或桌面 OAuth。

   ```sh
   flutter build web --no-pub --target tool/web_db_smoke.dart
   flutter run -d chrome --web-hostname localhost --web-port 7357 --target tool/web_db_smoke.dart
   flutter test --no-pub test/features/subtitles/subtitle_repository_test.dart test/features/progress/progress_sync_test.dart
   ```

6. Chrome DevTools 檢查 worker 和 WASM 請求為 200，WASM 為 `application/wasm`。使用同一 `http://localhost:7357` 重新整理、關頁重開、在兩分頁驗證資料一致性，記錄裝置瀏覽器版本、模式與實際結果。第一段的 PASS 涵蓋 smoke 入口與已跑的子案例。完整版 `flutter build web --no-pub`、正式匯入與資料庫 migration fixture 仍分別列出結果。`WasmDatabase` 使用 SQLite WASM，Flutter App 是否以 `--wasm` 編譯留作獨立相容性驗收。

## 第二段：Web 教材庫、媒體檔案與播放

1. 從 `lib/core/files/app_media_store.dart`、`lib/features/library/services/audio_import_service.dart`、`media_selection_import_service.dart` 和 `lib/features/player/services/material_playback_loader.dart` 追完匯入與載入。將共用層對 `File`／`Directory` 的依賴移到原生 adapter。保留 `AudioImportSource` 的 bytes 串流契約；讓共用匯入、播放及後續傳輸取得可讀取的媒體與其 scope、SHA-256、大小和 MIME。既有 DB 的 `relative_path` 繼續可讀，Web 值由 adapter 解釋為邏輯媒體鍵。
2. 在 Web adapter 將 `file_selector` 選取結果交給原有的媒體選取流程。瀏覽器私有媒體用 OPFS，缺席才走 IndexedDB Blob。本機驗收使用合成 M4A／MP3 和 SRT。先暫存、分段計算 SHA-256、驗證後才建立資料庫與 Outbox 記錄。同一已存在雜湊要重用有效副本。寫入中斷或 `QuotaExceededError` 清理本次暫存，並保留其他教材仍在引用的 blob。儲存模式變動要能辨識舊副本所在位置。
3. 播放從已保存的檔案取 Blob URL 或同等可定位來源，經既有 `AudioEngine` 和 `LearningSession`。URL 由播放資源持有者管理，替換、退出或切帳號時先卸載音訊再釋放。Web 啟動選用 `NoopAudioMediaSession`，原生 `AudioService.init` 留在原生接線。資料夾監看入口不呈現在 Web。讓預設入口載入可用的教材庫；未接入的登入與同步操作顯示目前能力。
4. 跑完整入口的 `flutter build web --no-pub`，另用 Chrome 驗證匯入、去重、SRT 配對、播放、seek、單句循環、重載與配額／中斷復原。離線測試要明列 App shell 和教材是否都能在斷網後重開。擴充 T-WEB-02..04，並重跑既有 `audio_import_test.dart`、`material_playback_service_test.dart` 和 `player_page_test.dart`。

## 第三段：Firebase Google Web OAuth

1. 先讀 `firebase_session_controller.dart`、`lib/features/auth/data/firebase_account_session.dart`、`lib/features/auth/social_sign_in.dart`、`lib/features/sync/firebase_sync_dependencies.dart` 和 [WP-14 登入補件](wp-14-social-sign-in.md)。目前 `NativeFirebaseUser` 是 Android／Apple 專用路徑。Web SDK 完成 Google 登入後已取得 Firebase User 與 Firebase ID token。透過平台 session adapter 對接既有 UID、`currentIdentity()` 和 owner-checked `tokenFor(uid)` 契約，保留原生憑證交換。不得用 email 推導 storage scope，也不要把 Firebase ID token 當 Google provider token 再交換一次。
2. 先用 Fake／Auth Emulator 驗登入完成、取消、popup blocker、登出與切換使用者。採官方 `GoogleAuthProvider` 和由使用者直接點擊的 `signInWithPopup`，在點擊前準備好 SDK。若引入 FlutterFire，先驗證 solver、最低 OS 和原生 build；若相衝突，回報並評估官方 Firebase Web SDK 的 Web-only adapter。需 redirect 時，另外驗證 authDomain 與瀏覽器第三方儲存行為。[Firebase Flutter 聯合登入](https://firebase.google.com/docs/auth/flutter/federated-auth)、[Firebase Redirect 最佳實務](https://firebase.google.com/docs/auth/web/redirect-best-practices)
3. 登入成立後依 `beforeAccountChangeProvider` 保存原進度、卸載原音訊及更新 owner scope。同步同意預設關閉；舊 scope 的資料、URL 和 Outbox 在失敗、登出或換帳號時繼續隔離。Web build 使用獨立的公開 Firebase Web config，禁止把含 macOS Desktop Secret 的 `.env.firebase-auth` 傳給 Web build。掃描 `build/web` 的敏感值只輸出匹配檔名或數量。
4. 真實 Google OAuth 使用同一 Firebase 專案、對應 Web App ID 及核准 origin。Firebase Web App、授權網域、正式 hosting 尚未確認時將真實登入列為 BLOCKED。Emulator 與單元測試結果各自記錄。真實測試須核對同 Google 帳號在原生 App 與 Web 拿到相同 Firebase UID，交棒以一致／不一致的結果回報即可。

## 第四段：Web 同步、瀏覽器矩陣與發布門檻

1. 追 `lib/core/sync/sync_contracts.dart`、`lib/features/sync/services/cloud_sync_coordinator.dart`、`cloud_material_download_service.dart` 與 Firebase transports。將 `CloudSyncTransport` 的 `File` 依賴收在原生傳輸，讓 Web 從既有媒體介面取得 bytes。Safari 等瀏覽器的上傳串流、CORS、Callable 與 HTTP 錯誤映射都要實測。保留原本的 consent、UID 關卡、SHA-256 校驗、重試 lease、候選衝突與下載快取的寫入界線。
2. Emulator 用合成教材驗同 UID 下載、錯 UID 拒讀寫、斷網重送與 canonical 續播，參考 `test/features/sync/firebase_emulator_transport_test.dart` 與 `test/features/progress/progress_sync_test.dart`。核准環境就緒後，測 Mac → Web 下載播放、Web → Mac 續播。Chrome、Firefox、macOS Safari 實測並記錄版本與儲存模式。驗證過 COOP／COEP、OAuth 與 worker 的組合才宣告相容。

## 每段的停手與報告條件

- 正常結束前執行 `dart format --output=none --set-exit-if-changed .`、`flutter analyze --no-pub`、`flutter test --no-pub`、`git diff --check`，另記錄實際 Chrome smoke。Flutter 3.32.2 把 `flutter test --platform chrome` 標為 deprecated，Web 自動化及瀏覽器矩陣依當前工具鏈另行驗證。交棒列明命令、測試數及 PASS／FAIL／BLOCKED、實際瀏覽器版本、下一段、未取得的證據。
- 遇到需要改 schema 或安全規則、同 UID 不能對齊、多分頁可能寫入競態、可靠儲存只在破壞 OAuth 的 headers 下可用、瀏覽器不支援預期碼流、大檔案無法在記憶體限制內傳輸、相依升級會影響原生時，保存最小重現與具體錯誤，交回架構審查。受阻時可繼續已授權的獨立本機測試。
- Web 發布僅在 [T-WEB-01..06](../14-web-platform.md) 齊備且原生 smoke 通過後宣告。合併、推送、建立正式雲端資源與變更計費各依實際授權處理。
