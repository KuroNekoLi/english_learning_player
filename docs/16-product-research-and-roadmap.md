# English Learning Player — 產品功能盤點、競品研究與發展策略

- 日期：2026-11-27
- 研究基線：`codex/product-design-system`，`6a37ce548a76a828f2943625e0329604886dc8e4`（Editorial Reader Visual Baseline v1.0）。
- 性質：產品研究與候選 Roadmap，非已核准實作規格、非市場使用者調查、非發布 Gate 驗收。
- 使用者最新意向：先保存本研究；之後可能優先開發「每日智慧複習」，完成後再實現成熟競品的 AI 相關功能。實際開工仍需確認工作包、PRD、設計及資料契約。
- 本文件整理自 2026-11-27 對話中的產品研究，補上可持久追查的官方來源。競品能力可能因方案、語言、平台與版本不同；未逐一購買或實機驗證。

## 1. Executive summary

目前產品已具備相當完整的英文輸入（Language Input）能力：使用者可匯入自有音訊與雙語字幕、精聽、查字、收藏及重播真實語境，但尚未形成「今天學過，下星期仍能回憶」的閉環。

在現有主要客群已有教材的假設下，首選 Daily Review（每日智慧複習），整合 Active Recall（主動回憶）、Spaced Repetition（間隔複習）與 Contextual Learning（語境學習）。這能直接重用現有單字庫、原句卡、音訊引擎及字幕高亮，不必新增付費 AI API。

使用者若尚無教材，則自動語音辨識、雙語字幕生成及快速匯入的重要性會上升。故此排序是產品假設，不是已證實的市場結論。完成複習核心後，優先重新調查成熟競品的 AI 能力，依學習價值、教材取得摩擦、品質、隱私、成本與可行性安排實作。

## 2. 現有產品功能盤點

「已實作」指現有程式或工作包有對應能力，不表示四平台實機、正式 Firebase 環境及發布 Gate 已通過。

| 模組 | 現有功能 | 狀態 |
|---|---|---|
| 教材匯入 | M4A/MP3/SRT、手動匯入、檔案去重 | 已實作 |
| 教材管理 | 資料夾階層、搜尋、排序、列表/網格 | 已實作 |
| 自動匯入 | macOS iCloud 授權來源掃描、子資料夾映射 | 已實作；T-FOLDER-08 既有測試失敗 |
| 音訊播放 | 播放/暫停、Seek、0.5–2×、前後句、重播 | 已實作 |
| 播放模式 | 連續播放、逐句暫停、單句循環 | 已實作 |
| 字幕 | 英文、中文、雙語、隱藏、自動配對/手動附加、時間偏移 | 已實作 |
| 精聽 | 盲聽 → 英文 → 雙語揭露 | 已實作 |
| 單句翻譯 | 獨立顯示/隱藏中文，精聽隔離 | 已實作 |
| 字典 | 字幕單字查詢、詞義、音標、例句及單字/例句朗讀 | 已實作 |
| 單字庫 | 收藏、搜尋、離線字典資料、帳號同步 | 已實作；正式同步仍需驗收 |
| 收藏單字高亮 | 跨教材精確單字比對，不區分大小寫 | 已實作；尚無詞形還原及熟悉度狀態 |
| 原句卡 | 保存雙語語境與原始音訊範圍，原音播放及 TTS 備援 | 已實作 |
| 句子收藏 | 收藏、重播、字幕更新後重新定位 | 已實作 |
| 續播 | 本機 checkpoint、首頁迷你播放器、進度同步 | 已實作 |
| 雲端同步 | 教材、資料夾/清單、進度、單字庫等帳號資料 | 已有實作；完整跨裝置發布驗收待完成 |
| 帳號 | Google、Apple 接線、唯讀帳號機制 | 已實作；正式設定、平台條件及權限須驗證 |
| 離線 | 已下載教材、本機資料、待同步佇列 | 已實作 |
| 個人化 | 明暗主題、字幕字級、行高、間距、翻譯不透明度、閱讀寬度 | 已實作 |
| 跨平台 | Android、iOS、macOS、Web | 已有程式支援；發布 Gate 未全部通過 |

工程依據：
- [產品規格](00-product-requirements.md)、[工作包 WP-01～22](11-work-packages.md)、[WP-19 Dictionary](agent/wp-19-dictionary-handoff.md)、[WP-20 原句卡](agent/wp-20-word-bank-original-context-spec.md)、[WP-22 交棒](agent/wp-22-editorial-handoff.md)。
- `lib/features/dictionary/domain/saved_dictionary_word.dart`：單字及原句語境。
- `lib/features/dictionary/data/word_bank_repository.dart`：保存、刪除、原句附加、同步與版本衝突。
- `lib/features/dictionary/widgets/word_bank_page.dart`：單字清單、搜尋、詳情。
- `lib/features/learning/domain/learning_session.dart`：精聽揭露狀態、逐句播放、循環與句尾停止。
- 本輪盤點未發現 SRS 排程、獨立記憶狀態、答題歷史、每日複習佇列、完整聽寫/跟讀訓練或自動字幕生成模組。此結論限於研究基線的可見程式與文件。

## 3. 競品研究

| 競品 | 官方公開能力摘要 | 可借鑑方向 |
|---|---|---|
| LingQ | 自訂教材/網頁/音訊匯入、音訊轉錄、互動閱讀、單字狀態、SRS | 跨教材詞彙學習、按到期日複習、降低教材準備摩擦 [1–3] |
| Migaku | 從真實影音/Podcast 建立含語境、原音、定義的記憶卡；SRS；AI 翻譯、語境解釋、句子拆解 | 重用真實語境與音訊；一鍵建立學習素材；AI 按需輔助 [4–6] |
| Language Reactor | 互動字幕、詞彙工具、PhrasePump 依待複習單字挑選聽力句子；部分場景語音辨識/機器翻譯 | 從單字延伸至真實句子，安排語境聽力複習 [7–8] |
| Miraa | AI 雙語字幕、轉錄與翻譯；先前研究另提 Echo Method 的聆聽、理解、模仿、比較流程 | 音訊匯入後快速學習；Echo Method 的具體流程與平台範圍需後續核驗 [9–10] |
| Lingopie | 影音雙語字幕、影片記憶卡、Flashcards/Pop Quiz/Word Master/Sentence Wizard、AI 文法及口說教練 | 主動回憶、語境測驗、文法及口說輔助 [11–13] |
| Anki | Daily limits、Again/Hard/Good/Easy、FSRS、desired retention、複習排程 | 排程品質、複習負擔控制、歷史紀錄 [14] |
| Readwise / Reader | Daily Review、閱讀高亮重現、Podcast 逐字稿；Ghostreader AI 解釋/翻譯等 | 每日複習入口、過往內容重現、內容內的 AI 輔助 [15–17] |

### 3.1 功能對照

✓ = 本專案有對應程式或官方資料明確支持競品能力；部分 = 能力範圍不同；— = 未確認，不能推定沒有。競品的「自訂教材」不等於皆支援本地 M4A+SRT；原音卡也不等於同樣的資料模型。

| 功能 | 我們 | LingQ | Migaku | Language Reactor | Miraa |
|---|:---:|:---:|:---:|:---:|:---:|
| 自訂教材/內容 | ✓ | ✓ | ✓ | ✓ | ✓ |
| 互動字幕/閱讀文字 | ✓ | ✓ | ✓ | ✓ | ✓ |
| 字典查詢 | ✓ | ✓ | ✓ | ✓ | — |
| 單字收藏/高亮 | ✓ | ✓ | ✓ | ✓ | — |
| 原音語境卡 | ✓ | — | ✓ | 部分 | — |
| 逐句精聽/聽力學習 | ✓ | — | ✓ | ✓ | ✓ |
| 自動語音轉錄 | — | ✓ | — | 部分 | ✓ |
| 單字熟悉度追蹤 | — | ✓ | 部分 | 部分 | — |
| SRS/到期複習 | — | ✓ | ✓ | ✓（PhrasePump） | — |
| 主動記憶測驗 | — | ✓ | ✓ | ✓ | — |

Lingopie、Anki、Readwise 分別作為影音測驗、記憶排程與每日知識回顧的補充比較。此表保留前次研究方向，將證據不足或語義不完全一致的格子保守標示；不能當作產品逐項實機 benchmark。

## 4. 核心缺口：Learning Loop

目前：匯入教材 → 聆聽/閱讀 → 查詢單字 → 收藏原句 → 等待使用者自行複習。

建議：聆聽 → 查字 → 收藏語境 → 今日複習 → 強化記憶 → 在新教材再次遇見 → 持續聆聽。

現在單字庫只是可搜尋的收藏清單；沒有每張卡片的記憶狀態與到期日。若收藏 1,000 個單字，系統仍無法判定今天應複習哪些、哪些容易忘記。補齊此機制能將現有功能串接起來，建立每天短時間學習的入口。

學習科學依據：Kim & Webb (2022) 的第二語言間隔練習統合分析支持分散式練習對學習/保留的價值 [18]。這不證明本 App 或 FSRS 實作必然提升學習成效，仍需以使用者測試及延遲回憶評估驗證。

## 5. 候選功能優先級

原研究權重：學習價值 35%、使用者留存 30%、差異化 20%、開發可行性 15%。各項以 1–5 分主觀評估，總分 = 20 × 加權平均，並非 RICE 實證數據或成本估算。

| 功能 | 學習 | 留存 | 差異化 | 可行性 | 加權分 |
|---|---:|---:|---:|---:|---:|
| 每日智慧複習 SRS | 5 | 5 | 4 | 4 | 93 |
| 聽寫 Dictation | 5 | 4 | 4 | 3 | 84 |
| 單字熟悉度與教材難度 | 4 | 4 | 4 | 3 | 77 |
| 自動生成雙語字幕 | 5 | 4 | 3 | 2 | 77 |
| 跟讀與錄音比較 | 4 | 4 | 4 | 2 | 74 |
| YouTube/Podcast 快速匯入 | 4 | 4 | 3 | 3 | 73 |
| 學習統計與每日目標 | 3 | 4 | 2 | 4 | 65 |
| AI 文法與句型解析 | 4 | 3 | 2 | 3 | 63 |
| Anki 匯出 | 3 | 3 | 2 | 5 | 62 |
| 影片播放 | 3 | 3 | 2 | 3 | 56 |

Roadmap 不必完全等同分數排名：依賴關係、教材取得門檻及使用者的新開發意向同樣重要。上述評分假設既有客群能自行準備教材；若目標改為完全沒有音檔與字幕的新使用者，應重新評估自動轉錄及匯入的優先級。

## 6. 第一優先候選：Daily Review / 每日智慧複習

### 6.1 產品體驗與 MVP

首頁在既有續播旁新增「今日複習」入口，顯示真實到期數量、預估時間及開始按鈕。數字和預估時間須依實際資料，不使用固定展示數值；無到期卡時提供清楚的空狀態。

第一版建議：
- 單字回憶：顯示英文、使用者先回憶意思、揭露中文詞義與保存的原句。
- 語境填空：使用保存的原句遮蔽目標詞，讓使用者回憶後揭露答案；無可靠原句/匹配時退回單字卡，不生成假原句。
- 評價：Again（忘記）、Hard（困難）、Good（記得）、Easy（簡單）。先揭露才可評價；Hard 不等於忘記，評價語義應與所選演算法一致。
- 自動排程、每日到期佇列、適當新卡與複習負擔限制、答題歷史、複習完成摘要、本機持久化。
- 舊收藏單字可建立複習卡，不破壞既有詞義、原句、排序或收藏同步。卡片身份穩定、可去重。
- 可在離線使用，不要求 AI 或新付費雲端服務；沿用 Editorial Reader v1.0 的明暗主題與無障礙規範。

後續增量：原音聽力辨識卡（只播放真實句段，揭露後顯示原文/翻譯）；中翻英/句子回憶卡；同步複習歷史；熟悉度篩選、教材詞彙覆蓋率。若缺原音須清楚標示 TTS 備援，不把合成音冒充原音。首版不引入大量新的字幕高亮顏色。

### 6.2 排程與工程契約（提案）

候選 FSRS（Free Spaced Repetition Scheduler）。實作前需確認演算法版本、Dart 套件或自有實作的授權、測試向量、可重現性與 desired retention 預設；不能在未驗證時聲稱已支援 FSRS 或將概念性遺忘曲線當真實量測。參考 Anki 官方手冊 [14]。

建議獨立 `lib/features/review/`：
- domain：ReviewCard、ReviewState、ReviewRating、ReviewLog、ReviewScheduler。
- data：ReviewRepository、Drift migration、必要的版本欄位。
- services：ReviewCardFactory、到期佇列、FSRS Adapter。
- widgets：DailyReviewPage、ReviewCard、ReviewResult、首頁入口。
- Riverpod 注入；使用既有 WordBankRepository、OriginalWordContext 與 AudioEngine，不改現有播放語義。

資料模型要區分「收藏單字」與「卡片記憶」。同一單字的回憶卡、語境卡、聽力卡可能有不同難度/穩定程度。不要直接將所有記憶狀態寫入單字庫 payload。
- 待 PRD 決定卡片 stable ID、建立/停用/刪除策略、學習日邊界/時區、歷史與調度器版本、重試/撤銷政策。
- 本機先落地，每次評價寫入紀錄與衍生排程應保持一致；重啟、重複點擊、跨日與舊 DB migration 要有測試。
- 後續同步以獨立 ReviewLog/ReviewState 設計，考慮兩裝置離線作答、事件去重、時鐘偏差、衝突及帳號隔離；不可僅以最後一筆覆寫整個收藏 JSON。遠端 schema/Rules/Emulator 與真實部署另行確認。
- 保留唯讀帳號限制，不讓新增複習功能繞過現有資料寫入權限。

### 6.3 成效與驗收

產品指標（先建立封閉測試基線，再設定數值目標）：首次收藏後複習啟動率、每日複習完成率、D7/D30 留存、七日後回憶成功率、收藏單字進入複習比例，以及後續的原音聽力辨識成功率。需區分自評與客觀答對，不能直接將卡片評價當語言程度或宣稱留存提升。涉及遙測時另行核准資料收集與隱私契約。

工程驗收建議：到期/新卡/忘記/跨日/重啟/離線、舊單字庫 migration、原句缺失、重複作答、帳號切換、唯讀權限、明暗主題、大字體及四平台回歸。同步與原音列入相應後續工作包，不提前宣稱首版支援。具體 PRD、Figma 設計、schema 與測試案例尚待核准。

## 7. 每日複習之後：成熟競品 AI 功能

本節將使用者最新方向加入前次研究。先完成每日複習核心後，再進行 AI 競品深化調查及規格化；以下是候選能力，不是已決定的供應商、技術或費用。

| AI 能力候選 | 競品參考 | 產品價值與待驗證事項 |
|---|---|---|
| 音訊語音辨識/自動英文字幕 | LingQ、Miraa、Readwise Reader、Language Reactor | 直接匯入 M4A/MP3，產生具時間戳的字幕；比較本機/雲端辨識、長音檔成本、專名/口音、進度、重試與人工校訂 |
| 雙語字幕翻譯 | Miraa、Migaku、Language Reactor | 繁體中文語境翻譯、與英文 cue 對齊；評估品質、專名、斷句、輸出格式與使用者可編輯性 |
| 語境字典/句型與文法解釋 | Migaku、Lingopie、Readwise Ghostreader | 針對選取單字或當前句解釋詞義、搭配詞、句型；須區分字典事實與 AI 解釋，保留原文並避免杜撰 |
| AI 複習素材輔助 | Migaku 的語境卡與 AI 說明 | 以已收藏真實語境優先；必要時補充例句或解析並明標生成內容，不覆蓋原句或排程資料 |
| 跟讀/語音辨識與發音回饋 | Lingopie AI speaking/pronunciation coach；Miraa 模仿流程待核驗 | 先規格化錄音/重播/比較，再評估 ASR 或發音評分可靠性；不可把轉錄相似度直接當發音正確率 |
| 按需 AI 問答 | Readwise Ghostreader、Migaku 語境解釋 | 可探索教材句子/段落問答、翻譯與難句理解；以內容為依據，不強制聊天或對每句自動呼叫 |

建議 AI 階段先研究「自動英文字幕＋繁中翻譯」的完整教材取得流程，再比較語境解析及口說/聽寫輔助。此排序是候選方向，不排除先做其他 AI 功能。AI 必須服務學習而非純裝飾；保留手動匯入與離線模式；未經同意不得傳送私人教材、錄音、帳號資料，不自動開通付費服務。需明確 API 金鑰保護、資料處理/保存政策、成本上限、失敗降級及模型輸出品質評估。原始媒體/SRT 不得被自動覆寫，AI 產物應可追溯、校訂與匯出。第三方內容匯入需遵循來源權限、授權與平台條款。

## 8. 候選 Roadmap（非正式 WP 契約）

| 候選編號 | 主題 | 預期範圍與順序 |
|---|---|---|
| WP-23 | Vocabulary Review & Spaced Repetition | 第一優先候選；先完成 PRD、Figma、資料模型、MVP 離線複習 |
| WP-24 | 原音聽力複習與跨裝置同步 | 延伸複習核心；獨立確認排程同步、安全及原音復用 |
| WP-25 | 自動雙語字幕與快速匯入 | AI 階段優先研究候選；轉錄、翻譯與匯入工作流 |
| WP-26 | 單字熟悉度與教材難度 | 使用 ReviewLog 建立能力模型、覆蓋率及學習統計 |
| WP-27 | 聽寫與跟讀訓練 | 主動輸出、錄音、比較，必要時 AI 回饋 |
| 待編號 | AI 語境解析、問答與記憶卡輔助 | 完成每日複習後重做競品及技術評估，再確認與其他工作包的合併/拆分 |

使用者意向是每日智慧複習優先，完成後進入成熟競品 AI 功能；WP-24～27 是原研究暫定編號，實際 AI 階段順序與範圍尚待確認，並非要求先做完所有非 AI 工作包。正式工作包仍以 [11-work-packages.md](11-work-packages.md) 為準，暫不在該契約中註冊未核准項目。

既有 release QA、T-FOLDER-08、原生平台建置、跨裝置真實 Firebase、無障礙及 Figma Phase 4 同步，按 WP-22 交棒持續追蹤，不能因新增功能而視為已解決。研究只盤點既有證據，沒有重跑測試或逐一驗證競品全部平台。

## 9. 產品定位

Listen. Understand. Remember.

不只聽懂英文，而是真正記住所學的英文。讓使用者將自己喜歡的新聞、Podcast 和自有音訊轉成能持續累積的個人學習系統。參考 LingQ 沉浸式閱讀、Migaku 真實語境卡與 Anki 長期記憶，但以音訊優先、繁體中文體驗、自有教材、跨裝置、Editorial Reader 為主要差異化方向，不宣稱競品完全沒有這些能力。

## 10. 可追查的公開來源

來源為官方網站/文件或原始研究 DOI；2026-11-27 整理與補核。功能、方案及服務可用性可能變化，進入各 PRD 時須重驗，不將產品宣傳等同學習成效證據。

1. LingQ iOS 官方功能：https://www.lingq.com/en/ios-app/
2. LingQ 官方支援（句子翻譯、SRS、匯入）：https://www.lingq.com/en/ios-app-support/
3. LingQ 官方匯入指南（含音訊轉錄）：https://www.lingq.com/blog/complete-guide-importing-lingq/
4. Migaku 官方功能 FAQ：https://migaku.com/faq/features
5. Migaku 官方卡片建立工具：https://migaku.com/blog/youtube/the-card-creator-migaku-browser-extension
6. Migaku 官方更新紀錄（Podcast、AI customization）：https://migaku.com/blog/changelog
7. Language Reactor 官網（PhrasePump）：https://www.languagereactor.com/
8. Language Reactor Pro（部分語音辨識與機器翻譯）：https://dev.languagereactor.com/pro-mode
9. Miraa 官網（AI 雙語字幕與翻譯）：https://miraa.app/
10. Miraa 隱私政策（AI 字幕辨識資料流程）：https://miraa.app/terms/privacy-policy
11. Lingopie 官網（影音記憶卡、AI grammar）：https://lingopie.com/
12. Lingopie 官方 Learning Games：https://help.lingopie.com/support/solutions/articles/150000174380-lingopie-learning-games-flashcards-pop-quiz-word-master-sentence-wizard
13. Lingopie 官方口說教練介紹：https://try.lingopie.com/
14. Anki 官方 Deck Options（FSRS、desired retention、每日限制）：https://docs.ankiweb.net/deck-options.html
15. Readwise 官方 Reviewing Your Highlights：https://docs.readwise.io/highlights/docs/faqs/reviewing-highlights
16. Readwise 官方 changelog（Podcast transcript / audio review）：https://docs.readwise.io/changelog
17. Readwise AI Policy（Ghostreader、翻譯等）：https://web-render-3.readwise.io/ai-policy
18. Kim, S. K., & Webb, S. (2022). The Effects of Spaced Practice on Second Language Learning: A Meta-Analysis. Language Learning. https://doi.org/10.1111/lang.12479
