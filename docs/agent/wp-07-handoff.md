# WP-07 書籤交棒摘要

日期：2026-11-12  
分支：`codex/wp-07-bookmarks`  
基底：WP-06 `d765de2`  
狀態：本機驗收完成

## 交付介面

- `Bookmark` / `BookmarkCueAnchor`：每筆收藏保存 owner/material、track ID/revision、language tag、cue ID/text、建立時間及已套用字幕 offset 的音訊時間區間。
- `BookmarkRepository` / `SqliteBookmarkRepository`：帳號範圍內列出、查詢、建立與軟刪除收藏；active anchor 有唯一索引，刪除保留 `deleted_at_ms` tombstone。
- `BookmarkResolver.resolve(bookmark, tracks)`：回傳 resolved/missing/ambiguous；只有目前已選、語言 family 相符的軌道可作播放目標，不修改收藏中的原始 anchor。
- `bookmarkRepositoryProvider`、`bookmarkListViewModelProvider`：提供 Repository DI 及 Favorites 頁面狀態；`BookmarksPage` 顯示可定位與未定位收藏，點選有效項目以 `initialCueId` 開啟 Player 並播放。
- Player 提供收藏/取消收藏目前句按鈕；Library 提供「我的收藏」入口。播放仍只走既有 `AudioEngine` / `LearningSession`。

## 定位決策

- 先查相同 track ID + revision + cue ID；否則比對小寫且合併 whitespace 的文字，再以 audio interval overlap 與中心距離決定唯一最佳候選。
- 文字改寫時，僅接受重疊至少覆蓋較短區間 50% 的候選。同分或無候選標示 ambiguous/missing，不猜序號、不丟棄 bookmark，也不自動 seek。
- 完整規則與限制見 ADR-025；重定位後仍保留建立時 anchor，方便審核原收藏位置。

## 修改清單

- Schema v3：`lib/core/db/local_database.dart` 增加 `bookmarks`、active anchor 唯一索引與 material lookup 索引；支援 v2→v3 migration。
- Domain/Data/ViewModel/UI：`lib/features/bookmarks/`；`lib/features/player/player_page.dart`、`player_view_model.dart`；`lib/app/library_page.dart`。
- 測試：新增 `test/features/bookmarks/bookmark_repository_test.dart`、`test/fakes/fake_bookmark_repository.dart`；擴充 `test/features/player/player_page_test.dart`；調整 WP-03 v1 migration fixture 以模擬真實 v1 schema。
- 文件：`docs/02-domain-models.md`、`docs/05-learning-and-ui.md`、`docs/12-decisions-and-risks.md`（ADR-025）、WP-06/WP-07 handoff。

## 驗收結果

- `dart format --output=none --set-exit-if-changed .`：PASS，54 個檔案，0 changed。
- `flutter analyze`：PASS，No issues found。
- `flutter test`：PASS，66 tests。涵蓋 v2→v3 migration、重開 DB、字幕修訂後重定位新 cue ID、missing/ambiguous、帳號隔離、收藏建立/移除及 Favorites 開始播放定位 cue。
- `git diff --check`：PASS。
- Android/iOS/macOS build：未執行；本 WP 沒有 platform/native 或 plugin 設定變更。真機 Favorites 觸控流程尚未實測。
- 沒有新增套件、雲端服務或計費資源；本 WP 未寫 Firebase/outbox。

## 下一個工作包

建議 WP-08 雲端基礎。WP-07 的 tombstone 目前只保存在本機，尚未建立 outbox 或雲端同步行為。
