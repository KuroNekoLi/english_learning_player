# WP-10 交棒摘要：系統媒體控制

## 範圍

WP-10 將現有 `AudioEngine` 狀態與命令連接至 Android/iOS/macOS 系統媒體 session。沒有新增完整播放器 UI、Firebase/iCloud 功能或下一工作包內容。

## 公開介面

- `AudioMediaSessionPort.publishMediaItem({id, title, durationMs})`：播放頁載入教材後發布系統 Now Playing metadata。`NoopAudioMediaSession` 供平台初始化失敗及測試使用。
- `EnglishAudioHandler`：實作 `audio_service` `AudioHandler` 與上述 port。play/pause/stop/seek/setSpeed 一律呼叫單一 `AudioEngine`；訂閱其 snapshot 並輸出系統 `PlaybackState`。`close()` 取消 snapshot 訂閱。
- `audioMediaSessionProvider`：提供 async media session；應用程式啟動先初始化 `AudioService`，再以同一個 handler 與 engine 覆寫 Riverpod providers，確保 OS service action 可進入同一引擎。
- `audioServiceConfig`：Android channel ID/name、暫停時保持前景 service (`androidStopForegroundOnPause: false`)、通知非 ongoing (`androidNotificationOngoing: false`)。

## 平台設定與行為

- Android Manifest 宣告 wake lock、foreground service/media playback 權限、`AudioService` 及 `MediaButtonReceiver`；`MainActivity` extends `AudioServiceActivity`。
- iOS `Info.plist` 設定 `UIBackgroundModes` 的 `audio`。
- macOS 不增加 sandbox entitlement 或 deployment target。`audio_service` 官方功能表列出 macOS Now Playing/Control Center 媒體控制，不列 Lock Screen 控制。沒有 Mac 真機媒體鍵測試，因此只記錄套件可用性，不宣稱執行驗證。
- 啟動 media service 失敗時降級為 no-op session，仍允許前景本機播放。
- Android pause 維持 foreground service 是 Android 12+ resume 取捨，可能讓系統通知持續顯示到使用者 Stop。

## 證據與驗收

- 依賴固定 `audio_service: 0.18.19`；本專案 `flutter pub get` 已解析成功。官方矩陣與選型理由見 [ADR-013](../12-decisions-and-risks.md)。
- `test/features/audio/english_audio_handler_test.dart` 覆蓋 metadata/snapshot 及系統命令路由至 engine；`test/features/player/player_page_test.dart` 覆蓋教材載入後發布 metadata。
- SDK：Flutter 3.32.2 / Dart 3.8.1。
- `dart format .` 與 `dart format --output=none --set-exit-if-changed .` PASS（73 files，0 changed）；`flutter analyze` PASS；`flutter test --reporter expanded` PASS（93 tests）；`git diff --check` PASS。
- `flutter build ios --simulator --debug` PASS；iOS 18.5 iPhone 16 Pro Simulator 安裝並 launch PASS（PID 18611）。此 smoke 只證明啟動與 service 初始化未阻擋 app，未觸發音訊播放或 OS media commands。
- `flutter build macos --debug` PASS（Xcode 輸出 sqlite3 上游 warnings）。`flutter build apk --debug` PASS，僅使用 `/tmp/wp10-flutter-config` 指向既有 JDK 17；該 temporary Flutter config 未更動使用者全域設定。
- Android build 顯示專案目前 NDK 26.3 與 plugin 建議 NDK 27.0.12077973 不同，但本次 APK build 成功，未改專案 NDK 設定或下載 SDK。Android AVD 不存在，`adb devices` 無 USB 裝置；Android 通知/鎖屏 smoke BLOCKED。沒有操作已連接的無線 iPhone。
- Simulator/desktop/apk build 不等於 Android/iOS 實機鎖屏、藍牙按鍵或播放期間背景 smoke。iOS Simulator 也未執行實際播放及外部 remote command。

## 後續

- 接上 Android 測試裝置後驗證通知、鎖屏與耳機 MediaButton；iOS 測試裝置驗證鎖屏與 Control Center。Android/iOS 實機測試及 macOS 真機媒體鍵測試屬未完成驗證，不作 PASS 宣稱。
- 後續工作包可依 `AudioMediaSessionPort` 與 `AudioEngine` 契約消費系統 metadata/state；不得另建播放器實例或讓 UI/platform plugin 繞過 AudioEngine。
