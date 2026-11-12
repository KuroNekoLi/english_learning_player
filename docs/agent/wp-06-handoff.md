# WP-06 Library / Player UI 交棒摘要

日期：2026-11-12  
分支：`codex/wp-06-player-ui`  
基底：WP-05 `e0fe4bc`  
狀態：本機驗收完成

## 交付介面

- `LibraryPage`：使用 `libraryViewModelProvider` 顯示帳號資料庫中的教材；點選教材導向 Player，使用既有匯入服務處理本機音訊。
- `MaterialPlaybackLoader` / `MaterialPlaybackService`：輸入 `LearningMaterial`，驗證 owner、查詢 audio asset、由 `AccountDatabaseService.resolveMediaFile` 安全解析 app 私有媒體副本，並載入字幕 tracks，輸出 `MaterialPlaybackBundle`。錯誤以 `MaterialPlaybackException` 或 `ArgumentError` 回報。
- `PlayerViewModel` / `playerViewModelProvider`：載入教材、管理 `AudioEngine` 及 `LearningSession`，暴露播放、暫停、seek、倍速、重播、下一句、句循環、字幕可見模式、精聽揭露與字幕 track/offset 更新命令。
- `PlayerPage`：使用 Riverpod 狀態呈現載入、錯誤、字幕缺席及目前 cue；mobile 固定底部 controls，寬度 900dp 起提供桌面摘要側欄。字幕設定 sheet 呼叫 ViewModel，不直接讀寫 repository。
- 播放設定遵循 ADR-024：一般字幕可見模式只存於目前 session；字幕 track 選取與 offset 使用 WP-03 Repository 持久化；切換顯示不 seek，套用字幕軌不重載音訊。

## 修改清單

- Library 及 private media lookup：`lib/app/library_page.dart`、`lib/core/db/account_database_service.dart`、`lib/features/library/material_repository.dart`、`lib/features/library/data/sqlite_material_repository.dart`。
- Player UI / ViewModel / playback service：`lib/features/player/player_page.dart`、`player_view_model.dart`、`player_dependencies.dart`、`services/material_playback_loader.dart`。
- LearningSession UI 接線：`lib/features/learning/domain/learning_session.dart` 新增一般字幕可見模式更新方法。
- 測試：`test/features/player/player_page_test.dart`、`material_playback_service_test.dart`；更新共用 fake 與既有 repository fake。
- 規格/決策：`docs/05-learning-and-ui.md`、`docs/12-decisions-and-risks.md`（ADR-024）。

## 驗收

- `dart format --output=none --set-exit-if-changed .`：PASS，45 files，0 changed。
- `flutter analyze`：PASS，No issues found。
- `flutter test`：PASS，60 tests。
- `git diff --check`：PASS。
- Android / iOS / macOS build：未執行；WP-06 僅修改 Flutter Dart UI / service 接線，未修改原生設定。此項為本 WP 不適用，不能視為新平台 build 通過。
- 真機觸控、鍵盤與輔助使用驗收：BLOCKED，需 Android/iOS/macOS 實機與輔助工具人工檢查。
- 沒有新增套件、資料庫 schema、雲端服務或計費資源。

## 尚未涵蓋與下一步

- 本 Player 顯示當前字幕 cue；完整可捲動 transcript、書籤、背景播放及進度保存均在後續工作包範圍。
- WP-07 已完成並記錄於 [WP-07 交棒](wp-07-handoff.md)。建議下一工作包 WP-08 雲端基礎；本地 tombstone 目前沒有 outbox 或雲端同步。
