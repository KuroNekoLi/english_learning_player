# 精聽模式與跨尺寸 UI

> 2026-11-27：視覺與元件規範以 [Editorial Reader v1.0](15-editorial-design-system.md) 為準；本文件保留學習行為與流程契約。實作、驗收證據與未完成項目見 [WP-22 交棒](agent/wp-22-editorial-handoff.md)。

## 1. 頁面
`LibraryScreen`：教材列表、下載/同步狀態、播放清單綁定入口、最近進度。
`PlayerScreen`：播放控制列、字幕區、模式切換、單句循環、倍速。
`BookmarksScreen`：依教材查看收藏句、點選重播。
`SubtitleSettingsSheet`：自動/手動字幕、語言軌、±offset。
`AccountSyncScreen`：登入、同步狀態、出錯重試、下載設定。
`FolderBindingScreen`（Mac）：授權 folder + 綁 playlist。

## 2. Responsive UI
播放器在手機與桌面皆使用一欄，桌面限制閱讀寬度，窄視窗的播放及字幕工具可換行。逐句字幕清單佔用剩餘高度。教材庫依可用寬度切換導覽。版面以視窗約束決定，並維持縮放字體可讀性與螢幕閱讀器語義。

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
- 點字幕卡只播放該句，抵達句尾即暫停。單句循環由獨立按鈕控制。字幕清單跟著目前播放句捲動。
- 工具列與設定面板共用一般字幕設定。精聽模式依目前揭露階段顯示當前句，其他句保留時間但遮蔽文字。
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

## 8. WP-06 Player / Library 實作契約
- `LibraryPage` 透過 `libraryViewModelProvider` 讀取帳號範圍內教材；使用既有匯入入口加入本機音訊，選取教材後進入 Player。寬度低於 900dp 使用單欄，否則顯示導覽側欄與受限寬度內容。
- 原生與 Web 教材庫共用「＋」選單。「匯入字幕」先選本機教材，再選 SRT，沿用播放器的自動辨識及手動選軌。雙語字幕兩軌在同一筆交易內儲存，本機來源教材的字幕也在該交易中依既有規則排入同步佇列。
- 「新增資料夾」建立目前帳號的 App 分類。首頁顯示頂層資料夾與未分類教材。資料夾與教材均可由三點選單重新命名、移動或刪除。每份教材仍可透過「加入教材」加入多個分類。分類的跨裝置規則見 [同步規格第 8 節](06-cloud-sync.md#8-教材分類名稱與刪除同步)。
- `PlayerPage` 只呼叫 Riverpod `PlayerViewModel`。ViewModel 經 `MaterialPlaybackLoader` 驗證教材 owner、查詢 app 私有音訊副本及字幕軌，再透過 `AudioEngine` 播放；Widget 不依賴 just_audio、檔案 API 或資料庫。
- Player 在手機與桌面使用同一欄布局。教材名稱只出現在頂部導覽列，播放區集中進度、播放/暫停、上一句、下一句、倍速、句循環與精聽操作。語言切換和字幕設定集中於逐句字幕工具列，字幕清單使用剩餘視窗高度。Space 播放/暫停、右方向鍵下一句。
- 一般字幕顯示模式只存在目前 Player session；變更時更新 LearningSession，不 Seek、不改播放位置。字幕軌選取及毫秒 offset 仍呼叫既有 `MaterialRepository.saveSubtitleTrack` 持久化；手動指定透過既有 `manual` 旗標，不覆寫 WP-03 的手動優先規則。套用軌道設定時重建 LearningSession，不重載或 Seek 音訊。
- 缺少字幕、翻譯或音檔時顯示明確狀態；字幕缺席時播放器可繼續使用 AudioEngine。WP-06 不包含書籤、背景播放、雲端同步、進度保存及 iCloud 監控。
- 驗收證據見 [WP-06 交棒](agent/wp-06-handoff.md)：Widget tests 驗證窄手機、桌面、大字體、點句只送一次播放命令及切換可見模式保留播放位置。

## 9. WP-07 Bookmark 實作契約
- 收藏目前英文 cue，anchor 保存 `trackId`、`trackRevision`、`languageTag`、`cueId`、原文及已套用 track offset 的音訊時間區間；anchor 是歷史快照，不因字幕匯入而被覆寫。
- 收藏以 owner/material 範圍落在 SQLite `bookmarks` 表。移除採本機 tombstone，重開 app 後仍保留有效收藏；Favorites 依最新已選字幕軌計算播放目標。
- 定位順序：相同 track/revision/cue identity；再用正規化文字匹配並以區間重疊、中心距離排序；文字改寫時以至少覆蓋較短區間 50% 的唯一時間重疊 cue 作 fallback。候選同分或沒有候選時標示 ambiguous/missing，收藏資料不刪除，也不自動 seek。
- Favorites 的有效項目開啟 Player 並從定位後 cue 播放；無法定位的項目可保留及移除，不能猜測相近序號。WP-07 不同步雲端；同步墓碑/outbox 屬 WP-08 之後。
- 詳細決策與測試證據見 ADR-025 及 [WP-07 交棒](agent/wp-07-handoff.md)。
