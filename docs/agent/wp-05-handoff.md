# WP-05 LearningSession 交棒摘要

日期：2026-11-12  
分支：`codex/wp-05-learning-session`  
基底：WP-04 `1ffe44f`  
狀態：驗收完成

## 交付介面

- `LearningSession`：綁定單一教材的英文字幕軌、可選中文軌及 `AudioEngine`；純 Dart，不持有播放器 plugin。
- `LearningSessionState`：不可變狀態，提供 normal/intensive mode、精聽 phase、有效 `SubtitleVisibility`、目前英文 cue、對齊中文 cues 和缺翻譯提示。
- 命令：`enterIntensive`、`exitIntensive`、`revealEnglish`、`revealChinese`、`resetCue`、`replay`、`setCueLoopEnabled`、`playCue`、`nextCue`。
- `states`：訂閱會先收到目前狀態，之後跟隨 `AudioEngine.snapshots` 更新 active cue；dispose 只取消自身 subscription，不 dispose AudioEngine。
- `LearningSessionFactory` / `learningSessionFactoryProvider`：由 Riverpod 提供工廠，呼叫端持有 session 並負責 dispose。

## 行為契約與決策

- 精聽揭露順序為 blindListening → englishShown → bilingualShown；跳過英文揭露的中文命令無效果。沒有翻譯時仍能揭露並顯示「未提供翻譯」；播放在 cue gap 時不提示缺翻譯。
- replay 從目前 cue 起點播放且不改揭露狀態；若 cue loop 已開啟會沿用。不同 cue 被選取時清理不相符 loop，播放新句；精聽模式將遮蔽重設。`nextCue` 依英文 cue 音訊時間順序前進。
- cue active lookup 使用 WP-03 `SubtitleSynchronizer`。cue 播放區間依字幕正 offset 延遲規則換算為 `startMs + offsetMs` 至 `endMs + offsetMs`，並 clamp 至媒體長度。
- session 驗證英文/中文軌 owner/material 一致及音軌語言；snapshot 教材 ID 改變後會清除目前 cue，並拒絕對其他教材送出 replay/loop/next/playCue 命令。
- 決策細節：ADR-023；規格見 [Learning/UI §7](../05-learning-and-ui.md#7-wp-05-learningsession-實作契約)。

## 修改清單

- 新增 `lib/features/learning/domain/learning_session.dart`、`lib/features/learning/learning_session_provider.dart`。
- 新增 `test/features/learning/learning_session_test.dart`（使用 WP-04 `FakeAudioEngine`）。
- 更新 `docs/05-learning-and-ui.md`、`docs/12-decisions-and-risks.md`（ADR-023）、WP-03/WP-04 handoff 的下一工作包狀態。

## 驗收結果

- `dart format --output=none --set-exit-if-changed .`：PASS，39 files，無需格式修改。
- `flutter analyze`：PASS，No issues found。
- `flutter test test/features/learning/learning_session_test.dart`：PASS，9 tests；T-LEARN-01..05 加上 offset、換句、跨教材隔離及 cue gap 邊界。
- `flutter test`：PASS，53 tests。
- `git diff --check`：PASS。
- 本 WP 僅修改 Dart Domain/Riverpod 接線與文件，未變更 platform/native/build 設定；未執行平台 build 或真機測試。AudioEngine 原生行為沿用 WP-04 的 build/真機驗收狀態。
- 沒有新增套件、SQLite schema、雲端資源或進度持久化；播放進度持久化屬 WP-09 範圍。

## 下一個工作包

建議 WP-06。Player UI/ViewModel 可用 Riverpod 建立 session，讀取 `LearningSession.states`，依 `subtitleVisibility` 決定顯示文字，將使用者點句/揭露/loop 操作轉給 session。不得在 Widget 直接呼叫 just_audio 或持久化學習進度。
