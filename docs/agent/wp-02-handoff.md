# WP-02 交棒摘要

日期：2026-11-11  
基線：Stage 1 commit `fdcbf6a`；分支 `codex/wp-02-local-import`。  
範圍：本機 DB、手動音訊匯入、內容完整性與帳號隔離；未開始 WP-03。

## 產出

- 以 Drift `GeneratedDatabase`、schema version 1、SQLite migration strategy 建立 `media_assets`、`materials`、`material_sources`。SQL schema 暫採手寫 DDL，未引入 `drift_dev` / build_runner。
- Repository 契約涵蓋 `listMaterials` 與交易式 `insertAudio`；Service 僅依賴 Repository 介面與可注入 `AudioImportSource` 串流。
- 使用系統檔案選擇器接受 MP3/M4A；複製到 app support 私有媒體目錄，串流計算 SHA-256，非空驗證後以內容定址檔名發布。
- `AccountScope` 將 ownerId 雜湊成路徑 namespace；每個 owner 有獨立 SQLite 檔與媒體目錄。SQLite owner 條件、複合 FK 與 transaction 保護資料關聯。
- 同 owner 的同內容共用 media asset；同來源鍵+hash 的重匯回傳原教材。不同來源即使內容相同仍保留獨立 materialId。決策見 ADR-020。
- macOS 僅新增系統選檔所需 user-selected read-only entitlement；沒有持久 iCloud folder bookmark 或監控，維持 WP-11 範圍。

## 主要介面

- `MaterialRepository`: `listMaterials()`, `insertAudio(...)`。
- `AudioFilePicker`: `pickAudio()`，取消回傳 null。
- `AudioImportSource`: 雜湊來源鍵、名稱、可讀 bytes 的 stream factory。
- `AudioImportService.importAudio(...)`: 回傳教材及 duplicate 標記。
- `AccountDatabaseService`: app support DB、owner-scoped media 位置。
- `AppMediaStore.copyAndHash(...)`: 驗證音檔型別、串流複製、SHA-256/長度及既有檔完整性。

## 驗收證據

- Flutter 3.32.2 / Dart 3.8.1。
- `dart format --output=none --set-exit-if-changed .`：PASS。
- `flutter analyze`：PASS，No issues found。
- `flutter test --reporter expanded`：PASS，16 tests。
- Android `flutter build apk --debug`：PASS，輸出 `build/app/outputs/flutter-apk/app-debug.apk`。Flutter 提示 NDK 26.3 與插件要求 27.0.12077973 不一致；本次未改 Android NDK 設定。
- iOS `flutter build ios --debug --no-codesign`：PASS，輸出 `build/ios/iphoneos/Runner.app`。未簽章，不能代表可安裝真機或發佈。
- macOS `flutter build macos --debug`：PASS，輸出 `build/macos/Build/Products/Debug/english_learning_player.app`。此為本機建置，尚未驗證簽章／sandbox 發佈能力。
- `git diff --check`：PASS。未呼叫 Firebase、未建立雲端資源、未啟動計費服務。

## 剩餘風險／未驗證

- 匯入檔案完成 rename 後若程序在 DB transaction commit 前中止，可能留下孤兒媒體；回收由 ADR-019 後續處理。
- 真實桌面檔案選擇器操作、真機播放、signed sandbox、iCloud bookmark／撤銷尚未測試；屬 WP-11／後續整合。
- schema version 1 目前僅建立匯入所需三表；字幕、播放進度、收藏、sync outbox 等 schema 隨其工作包落地。
- `sqlite3_flutter_libs` 鎖定 0.5.42 以滿足目前 Drift/SDK 組合；套件升級另行驗證，不在本 WP 擴大 SDK 或 Riverpod 版本。

## 下一步

建議 WP-03：以目前 `LearningMaterial` / repository 契約及 app-private asset 為輸入，實作 SRT parser、配對與對齊，依 T-SRT-01..09 驗收。不得將本機授權路徑帶入字幕或同步資料。
