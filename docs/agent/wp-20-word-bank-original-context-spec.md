# WP-20 單字庫原句卡

這份文件可直接交給 GPT-6 Luna 等實作模型。UI／UX 已定案，基準為 English Learning Player 的 WP-19（`cc8314f`）。接手時先依 [AGENTS.md](../../AGENTS.md) 檢查 Git 工作樹，閱讀 [WP-19 交接](wp-19-dictionary-handoff.md) 和 [音訊規格](../03-audio-player.md)。實作範圍以本文為準，保留本機已有的修改。提交、推送和部署需由使用者另行指示。

## 交付目標

從播放器的英文字幕收藏單字時，連同當時的原句、翻譯、教材與音訊時間存入單字庫。開啟單字詳情就能看到原句，按一次回放指定區間。原音不可用時，保留原句卡，並提供英文 TTS。第一版每個單字保留一段原句，媒體沿用現有 M4A／MP3 教材。影片畫面、裁切檔案、以及同詞多段原句屬於後續範圍。

## 畫面與互動

單字庫清單沿用現有單字與摘要。進到單字詳情後，依序呈現單字及英美發音、原句卡、字典釋義與例句。舊單字如沒有原句，詳情照常呈現字典資料。

> **murky**　🔊 英式　🔊 美式
>
> **原句**  
> 教材名稱 · **0:45–0:48**  
> landscape that is, well, honestly, it's just incredibly **murky**.  
> 老實說，它只是令人難以置信的模糊。  
> **▶ 播放原音**

原句卡外層只在單字庫使用。抽出播放頁的時間與英中字幕內容為共用呈現元件，播放器保留它自己的逐句播放、收藏本句和重播操作。原句卡用純顯示的英中字幕，使用相同的字體階層和斷行規則，只有收藏詞要高亮。支援字幕實際使用的大小寫與直、彎撇號。只標示完整 token，例如收藏 `murky` 時可標示 `Murky`，`murkiness` 保持原樣。沒有中文字幕時，原句卡只顯示英文。

| 情境 | 主操作 | 回饋 |
| --- | --- | --- |
| 原音可用 | 播放原音 | 從儲存的起點播到終點，播完回到「播放原音」 |
| 準備播放 | 正在載入 | 短暫停用主按鈕，避免重複請求 |
| 原音播放中 | 停止 | 停止後可從這句開頭再播 |
| 確認教材已移除 | 朗讀原句 | 顯示「原教材已移除」 |
| 確認教材仍在雲端，此裝置缺檔 | 朗讀原句 | 顯示「此裝置尚未下載」 |
| 無法確定來源狀態，或原音載入失敗 | 朗讀原句 | 顯示「目前無法播放原音」，按鈕可直接念整句 |
| TTS 也無法啟動 | 朗讀原句 | 顯示「無法朗讀，請確認裝置的英文語音設定」 |

原音載入途中失敗時，當前卡片切換成 TTS 按鈕，讓下一次點擊啟動朗讀。這個動作使用原句英文全文與 `en-US`。進頁、滑鼠停留、同步完成、或來源重新變成可用時，畫面只更新狀態。顯示來源未知時用通用文案，尤其在離線或尚未讀到教材清單時。下載仍使用教材庫原有入口。

## 實作步驟

### 1. 儲存模型與同步

新增單字庫資料模型 `SavedDictionaryWord`，包含既有 `Word` 及可空的 `originalContext`。原句資料至少包含下列欄位。

| 欄位 | 契約 |
| --- | --- |
| `version` | 原句格式版本，第一版固定為 1 |
| `materialId` | 目前帳號的教材 ID，作為回放定位依據 |
| `materialTitle` | 收藏當時的教材名稱，離線或教材移除後仍可顯示 |
| `startMs`、`endMs` | 已換算成音訊位置的整數毫秒，區間為 `[startMs, endMs)` |
| `english` | 選到的完整英文字幕，去除首尾空白後需有內容 |
| `translations` | 當時對齊的中文字幕文字陣列，可為空，保留排列順序 |

把 `original_context` 當作可選欄位放進既有 `dictionary_saved_words.payload_json` 的最外層，和 `word`、`pronunciations`、`entries` 同層。由單字庫自己的編解碼器處理欄位。既有 Dictionary API／DTO 和查詢快取維持原契約。下例只示範新增的欄位。

```json
{
  "original_context": {
    "version": 1,
    "materialId": "lesson-1",
    "materialTitle": "教材名稱",
    "startMs": 45000,
    "endMs": 48000,
    "english": "landscape that is, well, honestly, it's just incredibly murky.",
    "translations": ["老實說，它只是令人難以置信的模糊。"]
  }
}
```

- 舊收藏、直接從單字資料收藏的條目，以及無法解讀的原句附加欄位，均可當成無原句的正常收藏讀取。
- 沿用 v12 的 SQLite 表、Firestore `users/{uid}/wordBank/{word}`、500,000 UTF-8 位元組上限、同步同意、讀寫權限、版本條件寫入和移除紀錄。這個資料變更使用既有 JSON 欄位，無須新增資料表或 Firestore 欄位。有同步時，只同步原句快照和教材引用。回放解析當前帳號的現有媒體。
- 收藏與附加原句使用同一筆本機寫入，沿用既有待送狀態。舊單字「補加原句」須在交易內確認收藏仍存在、仍沒有原句。成功後保留原本的字典快照與收藏排序時間。遠端有更新時沿用現有衝突處理，舊的離線操作不得重建已刪除的收藏。
- 教材刪除、尚未下載、字幕改版或同步失敗時，已保存的英中快照仍可閱讀。相同單字多次收藏維持一筆資料，有原句時保留第一段。

主要檔案：

- [word_bank_repository.dart](../../lib/features/dictionary/data/word_bank_repository.dart) 處理單字庫讀取、寫入與待送資料。讓 UI 可取得含原句的收藏模型。
- [dictionary_dependencies.dart](../../lib/features/dictionary/dictionary_dependencies.dart) 提供收藏列表和操作。收藏狀態、單字詳情和遠端合併都使用同一份可更新的列表來源。
- [firebase_word_bank_sync.dart](../../lib/features/dictionary/data/firebase_word_bank_sync.dart) 已把 JSON 作為原始字串傳輸。保留目前的完整 payload、版本與帳號檢查。收到可讀的舊紀錄時照常合併。

### 2. 從字幕傳入原句

1. 從 [PlayerPage](../../lib/features/player/player_page.dart) 的當前教材，取得 `materialId`、`materialTitle`，沿 [SubtitleTranscript](../../lib/features/player/widgets/subtitle_transcript.dart) 傳入每張 [SubtitleCueCard](../../lib/features/player/widgets/subtitle_cue_card.dart)。
2. 用該卡的 `SubtitleLine.english`、`translations` 與實際英文 cue 建立原句快照。時間沿用卡片的 `subtitleToAudioMs` 和字幕偏移算法。若修正後 `endMs <= startMs`，仍可收藏單字，這次不附帶原句。保存已換算的毫秒，回放時只按媒體長度檢查或裁限。
3. 將可選的快照沿 [DictionaryWordText](../../lib/features/dictionary/widgets/dictionary_word_text.dart)、[DictionaryLookupPanel](../../lib/features/dictionary/widgets/dictionary_lookup_panel.dart) 傳給 [DictionarySaveButton](../../lib/features/dictionary/widgets/dictionary_save_button.dart)。點「加入單字庫」才落地。有原句輸入而已收藏的條目缺少原句時，顯示「補加這段原句」，保留現有移除操作。唯讀帳號沿用現有的不可編輯規則。
4. 原句卡放在 [WordBankPage](../../lib/features/dictionary/widgets/word_bank_page.dart) 詳情。使用一個可捲動畫面排列原句與字典內容。沿用播放器既有的 [時間顯示函式](../../lib/features/player/widgets/playback_time_label.dart)。共用字幕內容元件把樣式與操作分開，原句卡使用純顯示模式，播放器仍使用原有字幕查詞手勢。

### 3. 播放原音和 TTS

將來源解析和播放狀態放在可注入的控制器／服務，Widget 只顯示狀態與轉送按鈕事件。

1. 對照當前帳號的 [MaterialRepository](../../lib/features/library/material_repository.dart) 查找教材和音訊資產，沿 [MaterialPlaybackLoader](../../lib/features/player/services/material_playback_loader.dart) 與 `MediaStore` 的既有權限和本機檔案流程取得音源。回放只以目前帳號解析 `materialId`。來源缺檔、讀取失敗、或已確認移除時切到 TTS。對有釋放回呼的媒體引用（例如 Web Blob URL），棄置的引用由取得的一方釋放，已交給引擎的引用由引擎釋放。
2. 使用共用 [AudioEngine](../../lib/core/audio/audio_engine.dart)。參考 [LearningSession.playCue](../../lib/features/learning/domain/learning_session.dart) 的單次播句流程。開始前結束正在播放的教材音訊及其進度追蹤，清除舊循環，載入來源，定位到 `startMs`，只播一次。如果重用單次播放邏輯，讓它接受已換算的 range。原句回放本身不建立教材進度。測試以 `positionMs >= endMs` 或來源完成為停止條件，使用實機確認終點沒有可聽見的下一句。循環播句是另一種操作。
3. 新命令、停止、關頁或切帳號都要使尚未完成的舊載入失效。只清理自己仍持有的播放，避免遲到的停止或卸載打斷後續教材。同步更新既有帳號切換流程的清理點。按下停止或播完後都可再次從同一段開頭播放。
4. TTS 沿用 [speechPlaybackProvider](../../lib/core/audio/speech_playback.dart)。朗讀按鈕念完整 `english`，關頁／切帳號時停止自己的朗讀。切換原音與朗讀時先停止前一項。原音不可用時卡片仍可閱讀、仍可使用字頭的英式／美式發音。

## 驗收案例

| 案例 | 通過條件 |
| --- | --- |
| 收藏與顯示 | 從含 `murky` 的字幕收藏後，重開單字詳情仍有教材名、英中原句、單字高亮與時間。舊收藏正常顯示釋義 |
| 補加與去重 | 舊單字可補加一段；再次收藏同詞不增加第二筆、不覆蓋已存原句。唯讀登入只可查看 |
| 起訖與偏移 | 字幕偏移只套用一次。假音訊引擎收到 `45000` seek，播放位置到 `48000` 即停。停止、重播與關頁都正確，不改寫教材續播進度 |
| 缺檔與異常 | 移除教材、此裝置未下載、播放失敗時仍顯示原句。TTS 假物件收到整句英文，且沒有在進頁時自動發聲 |
| 競態與帳號 | 等待載入時離開詳情或切帳號，先前片段不會開始。後來開啟的教材不會被舊卡片的清理中斷 |
| 新舊資料與同步 | 相同帳號的另一裝置透過既有同步收到原句快照。從舊版本升級仍可讀收藏；移除後，離線舊編輯不會讓它重新出現 |
| 版面與語音 | 窄手機可閱讀全文、捲動及操作；桌面沿用原字幕樣式。各平台建置結果與實際出聲結果分開回報 |

## 接手時的執行順序

1. 先完成收藏模型、JSON 相容性、離線寫入和同步測試。
2. 接上字幕來源、收藏／補加，以及詳情卡和缺檔顯示。
3. 實作回放控制器、TTS 備援和生命週期清理，再做各平台驗收。
4. 依專案規範執行格式檢查、`flutter analyze --no-pub`、`flutter test --no-pub`。以 `npm run test:firebase` 增加同帳號跨兩個客戶端的原句快照案例。回報測試是否實跑、能否確實回放和停止，以及實機尚待驗證的項目。
