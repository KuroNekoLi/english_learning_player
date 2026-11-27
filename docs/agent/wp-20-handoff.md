# WP-20 實作交接

## 已完成

- 字幕長按／滑鼠查詞時，將教材 ID、名稱、英文原句、對齊中文字幕與套用一次偏移後的毫秒區間一併傳給收藏操作。
- 收藏 JSON 最外層新增選填 `original_context`。沿用 Drift v12 單字庫資料列和原 Firebase word-bank 文件；舊 DTO、舊收藏、API 快取及唯讀權限契約不變。
- 舊收藏可在字幕查詞時補加第一段原句。補加保留字典快照與 `saved_at_ms`；後續重複收藏不覆蓋既有原句。
- 唯讀帳號會看見鎖定狀態和說明，不再把收藏操作整個隱藏。詳情裡沒有原句快照時會提示如何從字幕補加，並說明唯讀帳號不能修改。
- 單字庫詳情在字頭／發音後、詞義前顯示原句卡；只高亮完整英文詞，無中文字幕時仍顯示英文。
- 原音回放使用共用 AudioEngine，只播儲存的 `[startMs,endMs)` 區間。回放期間暫停播放器進度記錄，停止或播完後回到原教材已儲存的位置並保持暫停。切帳號或音源被新播放取代時，舊回呼不應接管後續播放。
- 教材明確在雲端但本機未下載時顯示「此裝置尚未下載」。教材已封存不等同刪除；目前沒有可信的永久刪除標記，因此教材從清單消失時使用「目前無法播放原音」，不臆測為已刪除。音源不可用或回放失敗後，卡片留在頁面，下一次操作朗讀完整英文原句 `en-US`。

## 主要檔案

- [原句模型與單字庫編解碼](../../lib/features/dictionary/domain/original_word_context.dart)、[word_bank_repository.dart](../../lib/features/dictionary/data/word_bank_repository.dart)
- [字幕查詢傳遞](../../lib/features/player/widgets/subtitle_transcript.dart)、[dictionary_word_text.dart](../../lib/features/dictionary/widgets/dictionary_word_text.dart)
- [詳情卡](../../lib/features/dictionary/widgets/original_word_context_card.dart)、[單字庫詳情](../../lib/features/dictionary/widgets/word_bank_page.dart)
- [原音控制器](../../lib/features/dictionary/data/original_context_playback.dart)、[播放器暫停／恢復協調](../../lib/features/player/player_view_model.dart)
- [WP-20 規格](wp-20-word-bank-original-context-spec.md)

## 驗證

- `dart format --output=none --set-exit-if-changed .`：通過。
- `flutter analyze --no-pub`：通過，無問題。
- `flutter test --no-pub`：224 項通過，4 項 Firebase Emulator 案例依預設設定略過。
- `npm run test:firebase`：11 項 Firebase Rules 測試及 4 項整合案例通過；雙客戶端案例已驗證原句快照下載。
- `flutter build web --no-pub --debug`、`flutter build macos --no-pub --debug`、`flutter build apk --no-pub --debug`、`flutter build ios --simulator --no-codesign --no-pub --debug`：均成功。`flutter_tts` 仍會顯示 Web WASM 相容、Android Gradle 外掛及 Apple Swift Package Manager 警告；不是本次建置失敗。
- 假音訊引擎已驗證起點 seek、終點停止、手動停止、恢復回呼和雲端未下載狀態。真正的 M4A／MP3 邊界聽感、TTS 實際出聲與觸控裝置操作需在各平台實機驗收。

## 發布狀態

未 commit、push 或 deploy。保留工作樹既有的 iOS 開發團隊簽章修改。
