# WP-04 AudioEngine 交棒摘要

日期：2026-11-12  
分支：`codex/wp-04-audio-engine`  
基底：WP-03 `f6d7c84`  
狀態：本機驗收完成

## 交付介面

- `AudioEngine`：Stage 1 公開契約，提供 `snapshot`、`snapshots`、`load`、`play`、`pause`、`stop`、`seekTo`、`setSpeed`、`setSentenceLoop`、`dispose`。
- `PlaybackSnapshot`：教材 ID、播放位置/總長/緩衝位置（整數毫秒）、playing、processingState、speed、currentLoop、error；串流訂閱會先收到目前狀態。
- `JustAudioAdapter implements AudioEngine`：命令序列化、seek clamp、source generation、loop 清理、錯誤與中斷映射。
- `AudioPlayerPort`：可注入的原生播放器 seam；`JustAudioPlayerPort` 將 `file/http/https` URI 映射至 just_audio，並接上 iOS/Android audio_session。
- `audioEngineProvider`：Riverpod provider；建立 engine，provider dispose 時釋放播放器。
- 測試假物件：`FakeAudioPlayerPort` 可人工推進位置、buffer、載入結果、錯誤與 interruption；既有 `FakeAudioEngine` 也可人工推進時間並產生錯誤/中斷狀態。

## 行為契約

- seek 以毫秒 clamp 到 `[0,duration]`；倍速 `[0.5,2.0]`，非法值拒絕。
- 接續的多筆 seek 會序列執行，最後一筆位置保留。快速換音源時較舊 load 回 `AudioFailure.superseded`，不覆蓋最新教材狀態。
- 句循環以 just_audio `setClip` + `LoopMode.one` 實作；取消、loop 外 seek、新音源載入會清除 clip，保留命令前原本播放/暫停狀態。
- iOS/Android 音訊 session 使用 speech 設定；interruption begin（含 duck）及 becoming noisy 暫停，end 不自動恢復。macOS interruption、背景播放及媒體鍵控制屬 WP-10。
- 專案 minSdk 仍為 21。`audio_session 0.2.4` 實際 Android manifest 要求 minSdk 24，故改鎖 `0.1.25`（其 Android Gradle 設定 minSdk 19）；`just_audio 0.10.6` 接受 `audio_session >=0.1.24 <0.3.0`。沒有修改 Android minSdk、NDK 或其他全域 Flutter 設定。

## 修改清單

- 音訊介面與實作：`lib/core/audio/audio_player_port.dart`、`just_audio_player_port.dart`、`just_audio_adapter.dart`、`audio_engine_provider.dart`。
- 測試：`test/fakes/fake_audio_player_port.dart`、`test/fakes/fake_audio_engine.dart`、`test/features/audio/just_audio_adapter_test.dart`。
- 依賴/平台接線：`pubspec.yaml`、`pubspec.lock`、`ios/Podfile.lock`、`macos/Podfile.lock`、`macos/Flutter/GeneratedPluginRegistrant.swift`。
- 規格/決策：`docs/03-audio-player.md`、`docs/12-decisions-and-risks.md`（ADR-022）、`docs/13-skills-and-sources.md`、此 handoff；WP-03 handoff 的下一工作包已更新。

## 驗收結果

- `dart format --output=none --set-exit-if-changed .`：PASS。
- `flutter analyze`：PASS，無 issues。
- `flutter test`：PASS，44 tests（包含 T-AUDIO-01..08）。
- Android `XDG_CONFIG_HOME=<isolated-temp-config> flutter build apk --debug`：PASS，產物 `build/app/outputs/flutter-apk/app-debug.apk`。使用隔離的暫存 Flutter 設定指定既有 JDK 17，沒有變更全域設定。仍有既有 NDK 26.3 與 plugin 建議 NDK 27 的警告，這次 build 成功且未更改 NDK 設定。
- iOS `flutter build ios --debug --no-codesign`：PASS，產物 `build/ios/iphoneos/Runner.app`。未簽章、未部署真機。
- macOS `flutter build macos --debug`：PASS，產物 `build/macos/Build/Products/Debug/english_learning_player.app`。Pods SQLite 有既有第三方 C 編譯警告；build 成功。
- 首次使用 `audio_session 0.2.4` 的 Android build：FAIL（專案 minSdk 21、plugin 宣告 minSdk 24）。已依官方套件 changelog 改用相容版 0.1.25 並重跑全驗收；最終 Android build PASS。
- 三平台真機播放、AAC/MP3 loop 邊界誤差 ≤150ms、中斷/耳機拔除實測：BLOCKED（本次只有 Mac build host，沒有連線 Android 或 iOS 實機；macOS 只完成 build）。不可據此宣稱原生播放精度已驗證。
- `git diff --check`：PASS。

## WP-05 可直接使用

`PlayerViewModel`/`LearningSession` 從 Riverpod 取得 `AudioEngine`，監聽 `snapshots`，用 `snapshot.positionMs` 呼叫 `SubtitleSynchronizer.at(...)`。cue loop 可呼叫 `setSentenceLoop(TimeRange(startMs, endMs))`。不得直接依賴 just_audio；本次沒有加入播放器 UI、學習 session、雲端或背景服務。

建議下一個工作包：WP-05 LearningSession，依賴 WP-03 subtitle engine 與本 AudioEngine 契約。
