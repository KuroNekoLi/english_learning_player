# WP-03 交棒摘要：雙語 SRT 字幕引擎

日期：2026-11-11  
基線：WP-02 commit `5b0bc51`；分支 `codex/wp-03-subtitle-engine`。  
狀態：WP-03 實作及本機驗收完成；未開始 WP-04。

## 輸入 → 處理 → 輸出

- **輸入**：UTF-8 SRT bytes、音訊檔名與候選字幕檔名、英中 cue 時間軸、WP-02 `MaterialRepository`/`AccountScope`。
- **處理**：嚴格 UTF-8 parse；完整 NFC stem + 語言尾碼配對；依偏移調整後的半開時間區間對齊；offset-aware 二分定位；以 Drift transaction 保存 source bytes、track selection 與 cue rows。
- **輸出**：`SubtitleTrack`（包含原始 SRT bytes、語言、revision、offset、手動/自動選擇狀態及 cues）、parse warnings、match ambiguity、cue alignment 和目前 active cue。
- **失敗行為**：非法 UTF-8 回傳 `SubtitleParseException(recoverable: true)`；錯誤 cue 不崩潰整份 parse，逐筆以 warning 記錄並跳過；多候選回報 ambiguous 且不自選；無時間重疊返回空 target；Repository 外鍵/DB 錯誤照常回傳呼叫端。

## WP-04 可直接使用的介面

```dart
final tracks = await materialRepository.listSubtitleTracks(materialId);
final english = tracks.firstWhere(
  (track) => track.isSelected && track.languageTag.toLowerCase().startsWith('en'),
);
final current = SubtitleSynchronizer(
  cues: english.cues,
  offsetMs: english.offsetMs,
).at(positionMs, previousCueId: previousCueId);
```

英中配對：

```dart
final alignment = const SubtitleAligner().align(
  sourceCues: english.cues,
  targetCues: chinese.cues,
  sourceOffsetMs: english.offsetMs,
  targetOffsetMs: chinese.offsetMs,
);
```

實際型別與責任：

- `SrtParser.parse(List<int>) -> SubtitleDocument`：純 Dart parser，回傳精確原 bytes、parsed cues 和 warnings。
- `SubtitleFilenameMatcher.match(...) -> Map<SubtitleLanguage, SubtitleLanguageMatch>`：完整 stem 比對、手動 override、ambiguous candidates。
- `SubtitleAligner.align(...) -> List<SubtitleAlignment>`：一對多/多對一、offset-aware overlap。
- `SubtitleSynchronizer(cues, offsetMs).at(positionMs, previousCueId)`：半開區間 active cue，O(log n + active-overlap count)。
- `SubtitleImportService.importBytes(...) -> SubtitleImportResult`：parse 並用 `MaterialRepository.saveSubtitleTrack` 持久化。
- `MaterialRepository.listSubtitleTracks(materialId)` / `saveSubtitleTrack(track, manual:)`：按目前 account scope 讀寫 Drift；每個 material 的 en/zh 語系最多一個 selected track。

正值 `offsetMs` 表示字幕延後顯示；同步時查 `positionMs - offsetMs`。自動軌不得取代所選手動軌。自動候選檔名歧義時由 matcher 回傳空的 selected 值，呼叫端應等待人工選擇。

## 對應要求與測試

- BOM/CRLF、多行、非連續序號、無尾隨空行、非法 UTF-8、異常區間：`test/features/subtitles/subtitle_engine_test.dart`。
- `.en`、`.en-US`、`.zh`、`.zh-TW`、`_English`、`_Chinese`、NFC、類似 stem、候選歧義及手動覆蓋：同上。
- 英文兩句→中文一句、英文一句→多中文、重疊 target、無翻譯及英中 offset：同上；不以 SRT sequence 配對。
- 正值 offset、半開邊界、cue overlap 前一 cue 持續性、10,000 cues × 10,000 random seeks：同上；性能測試上限 3 秒。
- SRT 原 bytes/BOM/CRLF、cues、offset、手動選擇重開 DB 後還原；自動新增不得蓋手動軌；晚到語言可以再匯入：`test/features/subtitles/subtitle_repository_test.dart`。
- Drift migration 從 WP-02 schema v1 升至 v2，並驗證既有 material 仍可讀取：同上。

## 決策與文件

- Drift schema v2：新增 `subtitle_tracks`（保留原始 bytes BLOB）及 `subtitle_cues`（sequence、ordinal、毫秒時間、原文字），owner/material 複合 FK；已建立 v1→v2 Migration。
- 對齊門檻為較短 cue 時長的 25%，可由 `SubtitleAligner` 建構參數調整；理由與證據見 ADR-021。
- Unicode filename NFC 由 `unorm_dart 0.3.3` 執行，純 Dart、無 platform plugin；版本資訊見 `pubspec.lock` 和 [pub.dev](https://pub.dev/packages/unorm_dart)。
- 詳細語意更新見 [字幕規格 §7](../04-subtitle-engine.md#7-wp-03-實作契約)、[資料模型](../02-domain-models.md) 及 [ADR-021](../12-decisions-and-risks.md)。

## 驗收結果

- Flutter 3.32.2 / Dart 3.8.1；`dart format --output=none --set-exit-if-changed .`：PASS。
- `flutter analyze`：PASS，No issues found。
- `flutter test --reporter expanded`：PASS，35 tests。
- Android `flutter build apk --debug`：PASS，輸出 `build/app/outputs/flutter-apk/app-debug.apk`。有 NDK 26.3 vs 插件建議 27.0.12077973 警告，本 WP 未更改 Android NDK 設定。
- iOS `flutter build ios --debug --no-codesign`：PASS，輸出 `build/ios/iphoneos/Runner.app`；簽章、真機安裝未驗證。
- macOS `flutter build macos --debug`：PASS，輸出 `build/macos/Build/Products/Debug/english_learning_player.app`；正式 sandbox 簽章/發佈未驗證。
- `git diff --check`：PASS。沒有 Firebase/雲端寫入或新增雲端資源。

## 未驗證與下一步

- 尚無真實字幕教材 fixture；25% 門檻需在後續代表性字幕集上檢視誤配率，若調整須保留本測試矩陣。
- 本 WP 沒有加入字幕選擇 UI、原生 SRT file picker 或 folder watcher。matcher、bytes import 與持久化已有可測介面；人工操作屬之後 UI/資料夾工作包。
- WP-05 LearningSession 已交付，建議下一個工作包為 WP-06 UI。字幕同步仍由 `SubtitleSynchronizer.at` 消費 `AudioEngine.snapshots`；LearningSession 不得自行呼叫播放器 plugin 或改變字幕 offset 語意。介面與驗收結果見 [WP-04 交棒](wp-04-handoff.md) 及 [WP-05 交棒](wp-05-handoff.md)。
