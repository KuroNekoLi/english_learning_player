# 精聽模式與跨尺寸 UI

## 1. 頁面
`LibraryScreen`：教材列表、下載/同步狀態、播放清單綁定入口、最近進度。
`PlayerScreen`：播放控制列、字幕區、模式切換、單句循環、倍速。
`BookmarksScreen`：依教材查看收藏句、點選重播。
`SubtitleSettingsSheet`：自動/手動字幕、語言軌、±offset。
`AccountSyncScreen`：登入、同步狀態、出錯重試、下載設定。
`FolderBindingScreen`（Mac）：授權 folder + 綁 playlist。

## 2. Responsive UI
手機：一欄字幕＋固定底部控制列，字幕為視覺主體；Mac：左側教材/播放清單，右側寬字幕列表，底部播放控制。以 `LayoutBuilder` / Breakpoints 而非 `Platform.isMacOS` 決定版面；平台差異僅限檔案選擇/快捷鍵等能力。窄視窗不得 overflow；維持縮放字體可讀性與螢幕閱讀器語義。

## 3. 精聽狀態機
```text
normal
  └─ enterIntensive → blindListening
blindListening
  ├─ revealEnglish → englishShown
  ├─ replay → blindListening
  └─ nextCue → blindListening(newCue)
englishShown
  ├─ revealChinese → bilingualShown
  ├─ replay → englishShown
  └─ nextCue → blindListening(newCue)
bilingualShown
  ├─ replay → bilingualShown
  ├─ resetCue → blindListening
  └─ nextCue → blindListening(newCue)
```
精聽模式「顯示字幕」只更改 `LearningSession`，不重建播放器。離開模式恢復一般字幕設定；切換下一句時遮蔽狀態回到 blindListening。無中文可用時顯示「未提供翻譯」而不空轉。

## 4. 字幕顯示
`SubtitleVisibility`: `bilingual`, `englishOnly`, `chineseOnly`, `hidden`。
- 點一句英文：先結束或重新指定 loop，再 Seek 至 cue.start；若點相同句且正在循環則重新從起點播放。
- 點收藏：收藏以 cue anchor 記錄；將 track 更新後需要重定位，不可假設舊 cue index 不變。
- 下載中、缺翻譯、登入過期、衝突均有明確狀態，不單用 Toast 導致訊息消失。

## 5. 使用體驗與無障礙
- 觸控最小可點區、Semantics label、文字對比、Dynamic Type、鍵盤 Space play/pause、左右方向鍵移動上一句/下一句（需避免文字輸入時搶鍵）。
- 進度列拖曳要節流，pointer 放開後 Seek；未載入 duration 不顯示可操作進度條。
- Mac 支援滑鼠捲動、焦點順序、鍵盤控制；iOS/Android 適配安全區、系統字體大小。
- 任何設計優先能以 Flutter Widget Test 驗證；UI 不能直接寫 Firestore 或檔案監控。

## 6. Widget 驗收
- 320dp 等效窄視窗 / 桌面 1280×720 / 大字體 / 繁中介面。
- 點句子呼叫 ViewModel 命令一次；切換字幕模式保留原播放位置。
- 模擬字幕缺漏與同步錯誤可正常渲染。

## 7. WP-05 LearningSession 實作契約
- `LearningSession` 為純 Dart controller，綁定單一教材的英文軌及可選中文軌；只依賴 `AudioEngine` 和既有字幕 Domain，不依賴 Widget 或播放器 plugin。
- `LearningSessionState` 是不可變快照：mode、phase、有效字幕顯示模式、目前英文 cue、對齊的中文 cues。`states` 訂閱先收到當前值。
- 精聽揭露嚴格依 blindListening → englishShown → bilingualShown；提早揭露中文不改狀態。沒有翻譯時仍可揭露，View 可顯示「未提供翻譯」；播放在 cue 空檔時不顯示缺翻譯提示。
- `replay()` 從目前英文句重播，不改揭露狀態；有啟用句循環時沿用循環。`setCueLoopEnabled` 控制目前句循環。`playCue(cueId)` 切換到指定句並播放；`nextCue()` 依英文 cue 音訊時間順序前進。切到另一句時退出舊 loop 並在精聽模式重設遮蔽；重播同一句保留已揭露狀態。
- 英文 cue 同步仍交由 `SubtitleSynchronizer.at`。句播放區間依既有 positive `offsetMs` 顯示延遲規則換算為 `[startMs + offsetMs, endMs + offsetMs)`，並限制在媒體 duration 內。無效/空區間不操作播放器。
- Session 確認 AudioEngine snapshot 的 `materialId` 與字幕軌一致後才執行 cue 命令；會取消自己的 snapshot 訂閱，但不擁有或 dispose `AudioEngine`。`LearningSessionFactory` 透過 Riverpod 提供建立入口；使用者負責 dispose session。
- T-LEARN-01..05 對應測試見 `test/features/learning/learning_session_test.dart`；具體驗收與未測項見 [WP-05 交棒](agent/wp-05-handoff.md)。
