# WP-19 Dictionary 增量功能

## 範圍
使用 BlackCatNews commit 578c2caed20b48fe262c67e43d5bfa50a7661720 的 Word JSON 欄位和 VPS Dictionary API。播放器字幕單字點選時辨識完整 token、高亮並在附近開啟詞典視窗。每帳號以 Drift 保存 API 回應供離線重用；不同步、不增加生字本或 FSRS。

## 查詢路徑
Flutter 先查本機 dictionary_words；未命中呼叫 GET https://dictionary.kuronekoli.uk/word/{word}。VPS API 先查既有 words.db，再查本機 ECDICT 索引，最後才呼叫 Cambridge。ECDICT 原始資料與 MIT 授權檔保存在 VPS；目前匯入 770,611 詞條。未知詞的 Cambridge 備援仍可能回 403。

## 資料契約與 UI
保留 word、pronunciations.uk/us、entries、definitions、examples 欄位。pronunciations.phonetic 為可選欄位，表示 ECDICT 未區分英美腔調的音標；uk/us 及 examples 可為空，en_definition 也可能是空字串。字幕只允許單一英文詞（可含內部 apostrophe）。視窗支援載入、重試、詞性、釋義與可用音標/例句。瀏覽器查詢由 API 提供唯讀 GET CORS。

## 驗收
fixture 涵蓋 Cambridge 與 ECDICT 回應、DTO round trip、快取、同詞併發與錯誤狀態；widget 測試涵蓋完整 token、高亮及無英美音標時的呈現。已用真實 API 驗證 /word/hello 回傳 200，CORS OPTIONS 預檢回傳 200。裝置端尚未做真機驗收。
