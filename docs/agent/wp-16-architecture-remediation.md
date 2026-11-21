# WP-16 架構修正與驗收

基準為 `13946fd`。本輪處理播放器、字幕、教材庫、同步、SQLite 與 macOS 資料夾授權的審查項目。

## 修正

- 播放器頁面組合播放控制、字幕清單、字幕卡和字幕設定。`PlayerViewModel` 管理畫面狀態和命令，字幕匯入、書籤及工作階段資源各有負責元件。字幕對齊、已排序的展示資料與 cue ID 索引在字幕軌變動時重建。
- 工具列與字幕設定使用同一顯示狀態。精聽揭露只作用於當前句。正字幕偏移在對齊、尋找、單句播放與書籤中一致表示延後。
- 登入登出在切換可見 UID 前清理舊播放工作階段、保存舊帳號進度並卸載音訊來源。系統媒體控制也清除舊教材資料。
- 教材庫拆出新增選單、教材清單與來源管理頁面。同步操作集中於 ViewModel，Firebase 文件與 Storage 物件由各自的 API 存取元件處理。
- SQLite 字幕、資料夾來源、進度佇列與 JSON 編碼各有負責元件。既有 schema、owner 範圍和 Repository 交易契約繼續適用。macOS 資料夾 plug-in 將 bookmark、掃描與監看分開，仍透過同一原生 channel 和唯讀 grant 存取來源。
- Firebase 字幕 manifest 保存拆軌方式，下載內嵌雙語 SRT 時取對應語言並保留原始檔案。舊 manifest 採共用 SHA-256 回復規則。

## 驗收

| 項目 | 結果 | 證據 |
|---|---|---|
| 格式與靜態分析 | PASS | `dart format --output=none --set-exit-if-changed .`、`flutter analyze --no-pub` |
| Flutter 回歸 | PASS | `flutter test --no-pub`，139 通過，2 個 Emulator 案例因開關跳過 |
| Firebase Emulator | PASS | 6 個 Rules 測試及 2 個 Flutter 整合測試，涵蓋雙語檔往返與進度同步 |
| macOS | PASS | Debug build 完成 |
| Android | PASS | 預設 JDK 25 下 Gradle 啟動失敗。單次指定 JDK 17 執行 `:app:assembleDebug`，已產出 Debug APK |
| iOS | PASS | `flutter build ios --simulator --debug --no-pub` 已產出 Simulator App |
| 正式環境與真機 | BLOCKED | 發布新客戶端前需部署新版 Firestore Rules。實機登入、iCloud 授權生命週期與跨裝置續播仍待驗收 |

Gate C／D 仍缺正式 Firebase 與跨裝置真機證據。遠端播放清單和資料夾 metadata 依 ADR-028 保留為整合項。

## 後續架構整理

基準為 `bf17892`，以 [系統架構與資料流](../01-architecture.md) 為查閱入口。

- 帳號 DB providers、Firebase 端點及 HTTP client 歸入 `core`。Firebase Auth session 歸入 `features/auth/data`。教材庫的 DI 與畫面命令各有入口，其他模組直接引用所需 providers。
- `PlayerViewModel` 465 行，教材載入後的音訊準備、系統媒體及續播交給 `PlayerPlaybackStartup`，播放訂閱與 checkpoint 給 `PlayerSessionResources`。`SqliteProgressRepository` 409 行，`SqliteProgressPositions` 負責確認位置及候選衝突資料，Repository 負責跨表交易。`SentenceLoopPlayback` 負責 `just_audio` 平台 clip 的套用和復原，`JustAudioAdapter` 繼續管理命令與快照。
- 字幕發布使用現有 `sync_outbox`，並由 schema v7 為舊教材補排。測試驗證儲存與排隊原子性、音訊先完成、有效 lease 內的並行保護、同意撤回、重開後重試、以及下載快取隔離。見 [ADR-030](../12-decisions-and-risks.md)。

本輪前景同步沿用既有 UI。字幕工作在暫時失敗後保留，待下次前景同步消費；終端失敗記錄在 Outbox，尚無逐筆字幕重送介面。Gate C／D 的正式環境限制沿用上述驗收紀錄。

| 後續驗收 | 結果 | 證據 |
|---|---|---|
| 格式與靜態分析 | PASS | `dart format --output=none --set-exit-if-changed .`、`flutter analyze --no-pub` |
| Flutter 回歸 | PASS | `flutter test --no-pub`，143 項通過，2 項 Emulator 測試另行執行 |
| Firebase Emulator | PASS | 6 項 Rules 測試、2 項 Flutter 整合測試，雙語字幕由 Outbox 發布並在另一份 DB 讀回 |
| 三平台建置 | PASS | macOS Debug、iOS Simulator Debug、Android Gradle Debug（單次 JDK 17） |
| 正式 Firebase 與真機驗收 | BLOCKED | 待正式環境部署及實機登入、iCloud 授權、跨裝置續播驗收 |
