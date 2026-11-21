# 雙語 SRT 引擎規格

## 1. 完整處理鏈
本機 SRT 位元組 → 編碼判斷/錯誤提示 → `SrtParser` → `SubtitleTrack` + `SubtitleCue` → `FilenameMatcher` 自動認軌 → `SubtitleAligner` 依時間重疊建立中文關係 → `SubtitleSynchronizer` 隨播放時間找英文主 cue → PlayerViewModel 呈現與操作。

## 2. Parser
- 支援 UTF-8/UTF-8 BOM、CRLF/LF、無尾隨空行、多行 cue、索引不連續、時間格式 `HH:MM:SS,mmm --> HH:MM:SS,mmm`。
- 完整輸出原始 `startMs/endMs/text/sequence` 與 warnings；忽略空行與單純格式噪音，但不能默默顯示未識別的時間軸。
- 非 UTF-8：返回可修復錯誤，待選擇編碼/轉檔；不將亂碼硬存為有效字幕。
- 無效 cue（end <= start、負時間、超出支援範圍）標記/跳過並報告，不造成整檔崩潰。
- cue 可重疊、可有空檔；不依檔案序號隱含時間正確。
- Parse 實作為純 Dart，單元測試不需要 Flutter runtime。

## 3. 檔名自動匹配
- 音檔 `stem.m4a/mp3` 對應 `stem.en.srt`、`stem.en-US.srt`、`stem.zh.srt`、`stem.zh-TW.srt` 及 `stem_English.srt`、`stem_Chinese.srt`。
- 忽略大小寫、Unicode 正規化、可設定分隔符規則；避免 `AI_News` 錯匹配 `AI_News_2`。
- 優先順序：使用者手動指定 > 明確語言尾碼 > 檔名推測 > 內容語言偵測（若新增則需同意）。
- 同一音檔多候選同等優先，顯示選擇對話框；**不得用不確定配對覆寫已手動選擇的字幕**。
- SRT 比音訊晚出現時，下一輪掃描可以補軌；語言可缺省，缺中文時英文照常播放。
- 使用者手動匯入 SRT 時不詢問英文／中文；先嘗試雙語 cue 拆軌，再以明確語言檔名尾碼和文字字元辨識單語。混合文字無法安全拆軌或判定時，顯示可理解的錯誤，不猜測語言。
- 字幕設定以原始 SRT 來源分組；雙語來源呈現其英文與中文軌，單語來源只顯示實際存在的軌，不顯示另一語言的空清單。

## 4. 時間對齊
英文是學習主時間軸。每個英文 cue 找出有時間重疊的中文 cue 集合。
```text
overlap = max(0, min(english.end, zh.end) - max(english.start, zh.start))
english [10000,13000), [13000,17000)
zh      [10000,17000)
=> 兩段英文指向同一段中文，但 UI 要避免顯示重複中文造成錯覺
```
若同時有多段中文，以重疊長度排序，再用相對覆蓋率與容許時間窗口篩選；具體門檻由 WP-03 fixture test 訂立，不以固定索引當真值。沒有可信對應 → 無翻譯，不虛構文字。

## 5. 同步與偏移
- cue 區間是 `[startMs,endMs)`，position 完全位於空檔時 `activeCue=null`；遇重疊時採穩定排序與上次 cue 的持續性規則。
- `offsetMs` 應定義為「字幕相對音訊顯示延遲」：offset=+300 表示字幕在音訊時間 300ms 後才顯示。匹配時查 `positionMs-offsetMs`。
- 每軌可獨立 offset（英文與中文可能各不相同）；不修改原 SRT。
- 手動捲動時暫停自動跟隨，透過「回到目前句」恢復，避免界面抖動。
- 最頻繁 position event 只更新必要的字幕/進度 UI，不觸發全 App 重建。

## 6. 重要測試矩陣
| Fixture | 預期 |
|---|---|
| UTF-8 BOM + CRLF + multiline | 正確解析與保留換行 |
| 10:00.000–10:03.000 | 毫秒精度正確 |
| 索引 1、4、9 | 不假設連續 |
| end <= start | warning 或 error，可修復 |
| 重疊英文 cues / 空檔 | deterministic active cue |
| 英文 2 句/中文 1 句 | 兩句共用同一翻譯，不錯位 |
| 同名語系兩候選 | 保留使用者確認 |
| Manual 選軌後新檔案出現 | 不被自動覆蓋 |
| offset ± 500ms | 時間映射符合定義 |
| 1萬 cue 隨機 Seek | 索引/二分搜尋，避免逐次全表線性掃描 |

不可使用外部字幕 AI 生成當 MVP 的隱形需求。

## 7. WP-03 實作契約

- `SrtParser.parse(bytes)` 嚴格以 UTF-8 解碼；UTF-8 BOM 由解碼器移除，但原始 bytes 不變。CRLF/LF/CR 正規化為 cue 文字中的 `\n`，解析結果保留原始 sequence、毫秒時間和文字。無效 cue 逐筆略過並回傳 warning；非 UTF-8 以可修復 `invalidUtf8` 錯誤返回，不保存亂碼。
- `SubtitleFilenameMatcher` 僅比較 NFC 正規化、大小寫折疊後的完整 stem；支援 `.en[-locale]`、`.zh[-locale]`、`_English`、`_Chinese`。多個同語言候選回傳 ambiguous、selected 為 null；手動選擇優先於目前候選清單。
- `SubtitleAligner` 只依 `[startMs,endMs)` 時間重疊，不看字幕序號。offset 轉換為 `audioTime = subtitleTime + offsetMs`。候選重疊須至少覆蓋較短 cue 的 25%，以排除只擦過邊界的極小重疊；以重疊毫秒降冪，再以時間與 cue ID 穩定排序。此門檻可建構時覆寫，依據與風險見 ADR-021。
- `SubtitleSynchronizer` 對 cue 起點排序，預先建立 end-time prefix maximum；定位採二分搜尋並只檢查可能仍重疊的區間。offset 正值表示字幕較晚，查找使用 `positionMs - offsetMs`；區間右端不包含。重疊時優先保留上一 cue，其次選起點較晚者，再以較早 end 和 cue ID 決勝。
- Drift schema v2 新增 source track BLOB 與 cue rows；每個 material/language 最多一條 selected 軌。手動軌覆蓋自動軌；晚到的自動字幕可保存為未選取候選。升級保留 WP-02 material/asset/source 資料。

實際介面、T-SRT 驗收對應及 build/test 證據見 [WP-03 交棒摘要](agent/wp-03-handoff.md)。
