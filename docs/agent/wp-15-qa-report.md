# WP-15 Stage 4 QA 報告

日期：2026-11-17

基準：`9fbb8fa`（WP-14 Firebase 接線）

範圍：FR 回歸、可恢復錯誤及失敗注入。未更改產品行為或資料 schema。

## 執行摘要

| 檢查 | 結果 | 證據 |
|---|---|---|
| Dart format | PASS | `dart format --output=none --set-exit-if-changed .`，93 個檔案，0 變更 |
| Flutter Analyze | PASS | `flutter analyze --no-pub`，No issues found |
| Flutter Test | PASS | `flutter test --no-pub --reporter expanded`，122 通過；本機預設環境略過 1 個需 Firebase Emulator 的整合案例 |
| Firebase Rules 與雙客戶端 Emulator | PASS | `JAVA_HOME="$(/usr/libexec/java_home -v 21)" npm run test:firebase`，6 Rules 測試及 1 Flutter 雙客戶端整合測試通過 |
| Git whitespace | PASS | `git diff --check` |
| Stage 3 實機整合 Gate C | BLOCKED | iPhone 簽章及正式 Firebase 測試專案未具備；Android 依使用者指示略過 |

## FR 回歸矩陣

| 規格面向 | 結果 | 自動測試與涵蓋內容 |
|---|---|---|
| FR-01 平台啟動 | 部分 PASS | 最近 WP-14 的 macOS Release Emulator 實際登入、下載、播放及登出 PASS；Android 本輪略過，iPhone 簽章未設 |
| FR-02/03 字幕匯入、配對與呈現 | PASS | `subtitle_engine_test.dart`、`subtitle_repository_test.dart`、folder reconciler late subtitle 測試；BOM/CRLF、多行、歧義、offset、manual 優先、重開資料庫及字幕缺席後補入 |
| FR-04/05/06 播放、Seek、loop、中斷 | PASS | `just_audio_adapter_test.dart` T-AUDIO-01..08、`learning_session_test.dart` T-LEARN-01..05；失敗載入、亂序操作、來源切換、loop 邊界、系統中斷不自動續播 |
| FR-07 收藏與重定位 | PASS | `bookmark_repository_test.dart`；資料庫重開、帳號隔離、schema v2→v3、唯一及歧義字幕錨點重定位 |
| FR-08 本機持久化 | PASS | `audio_import_test.dart`、`subtitle_repository_test.dart`、bookmark/progress 測試；去重、部分檔清理、schema migration、重開資料庫 |
| FR-09/10/12 上傳、下載、重試與隔離 | PASS（本機+Emulator） | `cloud_sync_coordinator_test.dart`、`cloud_material_download_test.dart`、`firebase_emulator_transport_test.dart`；同 op 重試、暫態與永久錯誤、SHA 不符、拒權、同 UID 兩端接收、異 UID 拒絕 |
| FR-11 授權資料夾與掃描 | PASS（自動測試與先前 Mac 證據） | T-FOLDER-01..10、`folder_import_reconciler_test.dart`；picker 取消、撤權、部分下載、監看補掃、掃描錯誤不標記遺失、切帳號隔離、來源移除保留收藏 |
| FR-13 手動字幕與偏移 | PASS | 字幕 repository/engine 測試及 WP-14 Emulator track 測試；原始 bytes 保留、手動選擇不被自動覆寫、offset 持久化 |
| FR-14 平台音訊 | 部分 PASS | macOS Release 合成 M4A 解碼及字幕續播 PASS。iOS 真機、Android 真機及背景媒體 smoke 未在本輪執行 |

## Gate D 核對

- 回歸、SQLite schema migration 及 Emulator 權限規則均有自動測試且通過。
- 操作順序與失敗注入包括帳號切換發生於授權檢查、outbox claim、blob 傳輸、雲端提交後；拒權不重試；暫態錯誤保留原 op；資料 hash 錯誤不發佈快取；讀取舊 UID 的資料被拒。
- UI 測試涵蓋窄手機及大字體播放器版面、教材庫空狀態與資料顯示。完整無障礙語意審查、鍵盤操作與 VoiceOver/TalkBack 實機驗證尚缺證據。
- WP-14 人工 macOS 驗收已證明測試 UID 空間與原離線教材庫切換、合成教材雙語字幕及從遠端確認位置播放。其本機模擬器結果不證明正式 Firebase 專案已部署。
- Stage 3 Gate C 尚未通過，故 Stage 4 Gate D 僅可記錄本地自動測試通過及阻礙，不能據此宣稱產品可發佈。

## BLOCKED 與風險

1. **跨裝置真機鏈路**：缺 iPhone 可用簽章與實機 Firebase 測試專案。本輪未做 Android 測試。需依原 Gate C 在 Mac → Firebase → iPhone 驗收下載、canonical 續播及播放期間不被遠端 Seek，再測 Android smoke。
2. **正式 Firebase 設定及部署**：`firebase projects:list` 無法列出專案。本輪未建立專案、部署 Rules/Function 或觸發雲端費用。需確認專案、bucket、測試帳號、部署權限與費率方案後再測。
3. **遠端 playlist/folder metadata**：仍是 ADR-028 的後續整合項。現有 Firebase 接線發布教材、字幕及進度，不能宣稱跨裝置播放清單或來源 metadata 已同步。
4. **登入持續性與網路恢復觸發**：WP-14 的 Email/Password session 和同意只在 App 記憶體，須重新登入；目前前景手動同步。自動背景／網路恢復觸發及正式登入方式未完成。
5. **輔助使用與平台中斷**：缺 VoiceOver/TalkBack 實機核對、iOS/Android 音訊中斷/背景控制實機結果。

## WP-16 交棒

請先審查帳號生命週期與憑據保存、Firebase Rules/Callable 的所有權邊界、資料刪除/孤兒物件政策、遠端 playlist 缺口，以及 Gate C 與本報告標記的 BLOCKED 項。測試證據與平台推論應分開評估，Stage 4 不因 Emulator 通過而轉為可發佈。
