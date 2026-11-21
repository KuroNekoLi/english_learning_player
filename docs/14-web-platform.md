# Web 平台規格與 WP-17 驗收

Web 是 Android、iOS、macOS 以外的第四個正式支援目標。WP-17 負責瀏覽器版本的第一條端到端交付。正式推出以本文件的發布門檻為準。

分段實作命令與交棒條件見 [WP-17 Web 實作交棒](agent/wp-17-implementation-handoff.md)。

## 範圍

- 手動選取 M4A／MP3 和 SRT，重用 SHA-256 去重、雙語配對、字幕校正、精聽、收藏及續播。瀏覽器能重新開啟同 origin 的教材庫，並離線播放已保存的媒體。
- 採用同一 Firebase 專案的 Google Web OAuth 登入。裝置間用 Firebase UID 取得同一份雲端教材與確認進度，沿用同步同意和 Outbox 契約。只設定 Authentication 的環境可驗收登入與本機學習；正式雲端同步另需既有的授權環境。
- 首輪以桌面 Chrome 驗通主線，Firefox 與 macOS Safari 驗收儲存降級、登入及播放。以實際通過的裝置、瀏覽器與版本公告支援矩陣。Edge 與手機瀏覽器須另有實測結果才列入矩陣。
- iCloud 來源資料夾長期授權、掃描及監看屬 macOS。Web 首版採使用者單次選檔，Apple Web 登入與系統背景媒體控制另外驗收。

## 資料與平台接線

| 邊界 | WP-17 方向 |
|---|---|
| Drift／SQLite | 用 `package:drift/wasm.dart` 的 `WasmDatabase.open()`，以相容於 lockfile 的 `sqlite3.wasm` 與 `drift_worker.dart.js` 啟動 Web executor，沿用 `LocalDatabase` schema、migration、Repository 與 Outbox。`AccountScope` 在同 origin 下切分 UID 與未登入空間。 |
| 資料庫可用性 | 檢查 `WasmDatabaseResult.chosenImplementation` 與 `missingFeatures`。由 Drift 選擇 OPFS 或可協調分頁的 IndexedDB。若落到 `inMemory` 或未證明分頁隔離的 `unsafeIndexedDb`，畫面須明示限制並停用持久寫入。Web 不依賴取消非同步或背景化分頁來維持交易正確性。 |
| 媒體檔案 | 支援 OPFS 時採 origin 私有檔案系統，否則以 IndexedDB Blob 儲存。兩者各自使用帶 `AccountScope` 的邏輯媒體鍵；SRT 原始資料沿用 SQLite 保存。使用者選檔取得一次性讀取權，匯入時以分段讀寫與 SHA-256 驗證保存私有副本。配額不足、關頁中斷與寫入失敗應可恢復，未保存完整的媒體不得標為可播放。 |
| 播放 | 沿用 `AudioEngine` 與 `LearningSession`，媒體 adapter 從瀏覽器私有儲存取回播放來源。若用 Blob URL，在停止引用後釋放；切帳號需先停舊音訊、保存進度與關閉舊庫。驗收使用者手勢、M4A/MP3 解碼、seek 和單句循環。 |
| 登入 | 用官方 Firebase Auth Web 流程封裝 `GoogleAuthProvider`，首選由使用者點擊觸發的 `signInWithPopup`。如需 `signInWithRedirect`，先驗證目標瀏覽器及 `authDomain` 的同站配置。帳號隔離仍取自 Firebase UID。Web 建置只使用 Firebase Web 公開設定與必要的 Web OAuth 設定。 |
| 雲端傳輸 | 將現有 `dart:io` 的 HTTP、File 與 OAuth 依賴留在原生 adapter。Web 透過瀏覽器相容 client 傳輸 bytes，查驗 CORS、Storage 物件驗證及 Callable。維持相同 owner 驗證、重試、冪等、衝突和同步同意規則。 |

資料庫與媒體持久化分別驗收。儲存受瀏覽器的 origin、profile、使用者清除網站資料與磁碟配額約束。記錄是否獲得持久儲存，畫面要能解釋離線資料何時可用。DB 交易與媒體檔案寫入之間以暫存、驗證、提交與失敗清理銜接。依據：[Drift Web](https://drift.simonbinder.eu/platforms/web/)、[File System Standard](https://fs.spec.whatwg.org/)、[Storage Standard](https://storage.spec.whatwg.org/)。

以能完成 OAuth popup 的部署設定起步。若要讓 Drift 使用需要 cross-origin isolation 的 OPFS 模式，另驗證 COOP／COEP、OAuth 彈窗、第三方資源載入與 worker 行為。Web 發布須以指定 HTTPS origin 驗收 Firebase Authorized Domains。交付時掃描 Web 產物，確認原生 OAuth 密鑰、服務帳號與測試憑證未被帶入。依據：[Drift Web 配置](https://drift.simonbinder.eu/platforms/web/)、[Firebase Flutter 聯合登入](https://firebase.google.com/docs/auth/flutter/federated-auth)、[Firebase Redirect 最佳實務](https://firebase.google.com/docs/auth/web/redirect-best-practices)。

## WP-17 執行順序與驗收

| 測試 ID | 實作順序 | 通過條件 |
|---|---|---|
| T-WEB-01 | 建立 Web entry 與平台接線 | `flutter build web --no-pub` 可完成，localhost 能載入 App、worker 和 `application/wasm`；記錄 worker／WASM 版本。Web entry 不執行原生 AudioService、iCloud 或桌面 OAuth。 |
| T-WEB-02 | Drift 共用 schema 與多分頁 | DB 重開保留教材、字幕、收藏、進度與 Outbox；migration fixture 通過；兩個分頁同時存取有一致結果，或明確阻止不安全的寫入。 |
| T-WEB-03 | 私有媒體儲存及失敗復原 | M4A／MP3 重複匯入正確去重，雙語 SRT 可自動配對。覆蓋 OPFS／IndexedDB、配額不足、取消、寫入中斷與 partial copy 清理。 |
| T-WEB-04 | 播放與離線 | 網頁重新載入後可播放、seek、逐句及續播。外網中斷後，在同 origin 重開已保存的教材可播放與收藏；記錄 App shell 離線載入策略。 |
| T-WEB-05 | Google OAuth 與切帳號 | 同一 Google 帳號在 Web 和原生 App 得到同一 Firebase UID。驗證取消、popup 被擋、未授權網域、登出與再登入。換帳號時舊 DB、Blob URL、音訊與待送工作維持原 UID 邊界。 |
| T-WEB-06 | 同步與回歸 | Emulator 先驗同 UID 下載及已確認進度、離線排隊、拒絕其他 UID、重試與衝突。正式發布前，在已核准 HTTPS origin 與雲端環境完成 Mac → Web 下載播放及 Web → Mac 續播。Flutter Analyze、Flutter Test、原生三平台 smoke 和已公告瀏覽器矩陣均有證據。 |

## 實作起點與發布門檻

- 基準 `057ce4b` 使用 Flutter 3.32.2／Dart 3.8.1、Drift 2.31.0、sqlite3 2.9.4。本機套件源碼確認 `WasmDatabase.open()` 已存在。`flutter build web --no-pub` 回覆 `Missing index.html.`，目前沒有 `web/` 入口。`LocalDatabase.open(File)`、`AppMediaStore`、Firebase HTTP 傳輸與 macOS Desktop OAuth 目前使用 `dart:io` 或原生 executor，須依平台隔離。這些是程式盤點結果，瀏覽器實際相容性由 T-WEB 系列驗證。
- 開發先用 localhost、合成教材和 Firebase Emulator。正式發布前需核准 Web App 註冊、Authorized Domains、HTTPS 託管與已核准的媒體同步資源。沿用現行費用及資料授權邊界，瀏覽器與套件最低版本以實測後的支援矩陣確定。
