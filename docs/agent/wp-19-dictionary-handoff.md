# WP-19 Dictionary 增量功能

## 範圍
使用 BlackCatNews commit `578c2caed20b48fe262c67e43d5bfa50a7661720` 的 Word JSON 欄位和 VPS Dictionary API。播放器按滑鼠與觸控輸入查詞，浮窗可朗讀及收藏。查詞快取和單字庫都落在目前帳號的 Drift 資料庫。啟用 Firebase 同步後，單字庫可在同一帳號的裝置間同步。

## 查詢路徑
Flutter 先查本機 `dictionary_words`，未命中則呼叫 `GET https://dictionary.kuronekoli.uk/word/{word}`。後端以獨立的 Dictionary-API 專案維護。2026-11-26 用正式 `/word/refine` 核對到雙語例句會在同一個 `example_text` 欄位以換行分隔，例句來源與授權欄位沿用既有契約。

## 資料契約與 UI
保留 word、pronunciations.uk/us、entries、definitions、examples 欄位。pronunciations.phonetic 為可選欄位，表示 ECDICT 未區分英美腔調的音標；uk/us 及 examples 可為空，en_definition 也可能是空字串。字幕只允許單一英文詞（可含內部 apostrophe）。視窗支援載入、重試、詞性、釋義與可用音標/例句。瀏覽器查詢由 API 提供唯讀 GET CORS。

浮窗顯示收錄的詞義數，同一詞性中的多個詞義分別編號。繁體中文例句顯示在對應詞義下方，若有來源則可查看出處與授權。舊版快取及超過七天的詞條會在下次查詢時嘗試更新，離線時仍可使用已有資料。

## 2026-11-26 實作交接

- 電腦端滑鼠停留 350 毫秒或長按會查詞。Android、iOS 和其他觸控輸入以長按查詞，短點字幕照常播放該句。查詞只高亮被指到的那一次單字。可把滑鼠移進浮窗，移開後浮窗會關閉。長按開啟的浮窗可以按關閉鍵、點外部或捲動字幕收起。
- 字典浮窗和單字庫詳情共用 `DictionaryWordDetails`。單字可選英式 `en-GB` 或美式 `en-US`。英文例句用 `en-US`，含漢字的中文行用 `zh-TW`。`SpeechPlayback` 會透過 `AudioEngine` 暫停正在播放的教材，後一次朗讀取代前一次，收起詳情會停止該頁的朗讀。教材可用原播放按鈕繼續。
- `LocalDatabase` 由 v10 增至 v11，新增 `dictionary_saved_words`。收藏保留釋義、音標、雙語例句與來源快照，可以離線查看及移除。原生與 Web 教材庫的 AppBar 都有「我的單字庫」入口。
- Flutter 3.50.1、Dart 3.14.0 解析 `flutter_tts 4.2.5`。Apple 端沿用既有 Swift Package Manager 設定，Flutter 透過 CocoaPods 整合此套件。Android manifest 增加 `TTS_SERVICE` 查詢，無須新增系統權限。

## 帳號單字庫同步

字典功能保留在 `features/dictionary`。查詢快取、收藏資料庫和 Firestore 同步各自有資料層，TTS 由共用音訊模組管理，字幕只負責查詞手勢，既有同步排程負責觸發資料傳輸。這些邊界已可在同一 Flutter 專案獨立測試。

- SQLite v12 保留收藏快照、版本與待送狀態。v11 舊收藏在雲端沒有同名紀錄時補傳，現有雲端版本和刪除紀錄優先。
- Firestore 路徑為 `users/{uid}/wordBank/{word}`。同一個字用同一份文件。新增和移除先寫 SQLite，連線後使用條件寫入送出。移除以空快照保留版本。相同版本的裝置同時編輯時採用先被伺服器接受的變更。
- 依現有帳號同步同意設定執行。前景每 5 秒檢查待送變更，登入、回到前景及約每 2 分鐘更新遠端資料。手動同步可立即拉取。獲授權的唯讀登入可讀取單字庫。

## 驗收與續作

- 回歸範圍為字典資料契約與快取、游標進入浮窗、長按與短點互動、英式及雙語朗讀命令、收藏與移除、SQLite v10 升級和帳號資料庫隔離。
- `dart format --output=none --set-exit-if-changed .`、`flutter analyze --no-pub` 與 `git diff --check` 均通過。全套 `flutter test --no-pub` 通過 219 項，另有 3 項 Firebase Emulator 測試依環境設定略過。
- Android APK、iOS Simulator、macOS 和 Web JavaScript 的 Debug 建置均通過。測試用替身驗證朗讀命令和語系。實際裝置及瀏覽器的出聲驗收待做。
- `flutter_tts 4.2.5` 有 Android Kotlin Gradle Plugin 過渡警告及 Web App 的 WASM 編譯相容性警告。Web JavaScript Debug 建置可用。
- 平台驗收時以含 `refine` 的實際字幕查詞，按英式、美式和一組雙語例句的按鈕聽聲音，收藏後在離線狀態重開 App 驗證。語音依系統或瀏覽器提供的聲音而定。
- 單字庫同步版全套 Flutter 測試通過 220 項，4 項 Emulator 案例在標準測試入口略過，另用 `npm run test:firebase` 通過 Emulator 規則及整合測試。Web 正式版 JavaScript 建置通過。
- 交接請保留本機的 iOS 開發團隊簽章設定。正式發布走 Firebase Hosting 與 Firestore Rules，原生 App 由既有裝置或發行流程更新。
