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
