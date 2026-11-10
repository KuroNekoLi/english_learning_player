# 測試策略與品質門檻

## 1. 測試金字塔與執行環境
| 層級 | 目標 | 執行方式 |
|---|---|---|
| 純 Dart Unit | SRT Parser、Aligner、Repeat、ConflictResolver、FilenameMatcher | `flutter test test/unit` |
| Repository/Service | SQLite migration、SyncOutbox、Fake Storage、Fake Auth、錯誤重試 | `flutter test test/repository` |
| Widget | Library / Player / Favorites RWD 與互動 | `flutter test test/widget` |
| Integration | 匯入 → 播放 → 收藏 → 恢復、Firebase Emulator | `flutter test integration_test`（依平台適當 `-d`） |
| Native/Device | Android+iPhone+Mac 音訊背景、iCloud 授權、實際解碼 | 實機、受控 sandbox environment |

Flutter 官方 `integration_test` 依目前 SDK 文件設置；不使用舊式 `enableFlutterDriverExtension()` 當作一般整合測試前置條件。若官方其他 Skill 與此衝突，依本文件為準。

## 2. 必須具備的 fixtures
`test/fixtures/subtitles/`：BOM、CRLF、多行、非法時間、不連續序號、空檔、重疊、one-to-many、ambiguous filename、late-arriving subtitle、offset。
`test/fixtures/media/`：合法短 M4A/MP3、異常檔案、duration 不可得（使用可公開或自產最小音檔；勿提交受版權限制教材）。
`test/fakes/`：FakeAudioEngine、FakeSyncTransport、FakeFolderGateway、FakeClock、FakeAuth。

## 3. 規格主張與測試對應
| 規格 | 測試 ID | 失敗定義 |
|---|---|---|
| FR-02/03/13 | T-SRT-01..09 | 字幕遺失、錯誤配對、手動設定被覆蓋 |
| FR-04/05/06 | T-AUDIO-01..08 | Seek/loop 錯位、切媒體競態 |
| FR-07 | T-LEARN-01..05 | 揭露順序不符、換句未重設 |
| FR-08 | T-DATA-01..04 | 重啟遺失進度/收藏 |
| FR-09/10/12 | T-SYNC-01..10 | 雲端假 ready、寫入重覆、離線錯誤覆蓋 |
| FR-11 | T-FOLDER-01..08 | 遺失資料夾授權、漏掃、刪掉學習資料 |
| FR-01/14 | T-PLATFORM-01..08 | 平台不能啟動、音訊中斷未恢復 |

## 4. 每次提交的最低檢查
```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
git diff --check
git status --short
```
`flutter pub get`、`flutter build macos`、`flutter build apk --debug`、`flutter build ios --no-codesign` 在可用環境執行。iOS 真機部署需有效 Apple 開發者設定。**不允許把 Android build 成功等同 iOS/macOS 成功。**

## 5. 明確的 Gate
- **Gate A / Stage 1**：API/Schema/ADR 策略已審、fake 注入可行、三平台依賴 smoke check 完成或記錄 blocker。
- **Gate B / Stage 2**：各工作包單測+Widget 通過、`flutter analyze` 無新問題；每一 FR 有對應測試 ID。
- **Gate C / Stage 3**：至少 Mac → 雲端 → iPhone 的真機 E2E 和權限撤銷/斷網測試通過；Android 下載/播放 smoke test。
- **Gate D / Stage 4**：回歸測試、security rules emulator、schema migration、資料遺失與操作順序審查完成；所有阻礙列清單。

## 6. 報告格式
每個 Agent 回報：實際 commit/檔案、執行命令、PASS/FAIL/BLOCKED、測試設備及 OS、未測事項、資料遺失風險、下一工作包。測試環境失效不可標成通過，需提供可重跑命令與 blocker。
