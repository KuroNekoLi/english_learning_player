# 音訊播放引擎規格

## 1. 責任鏈
`PlayerView`（操作）→ `PlayerViewModel`（命令/畫面狀態）→ `AudioEngine`（單一播放器契約）→ `JustAudioAdapter`（just_audio）→ Android/iOS/macOS 原生解碼器；位置更新反向返回 ViewModel，字幕同步讀取同一個 position source。

## 2. AudioEngine 介面（語義契約，具體簽名由 Stage 1 訂定）
- `load(MediaSource)`：本機檔案優先，遠端位址僅能是授權短效網址；輸出 ready/error。
- `play(), pause(), stop(), seekTo(Duration), setSpeed(double)`。
- `setSentenceLoop(TimeRange?)`：非 null 設 [startMs,endMs) 循環，null 還原完整音源。
- `Stream<PlaybackSnapshot>`：position、duration?、buffered?、playing、processingState、speed、currentLoop?、error?。
- 任何對 App-visible 播放狀態的改變都需要明確命令，不應在 widget `build` 中產生 side effect。
- 狀態輸出要 immutable；所有 stream 訂閱由 owner 取消。

## 3. 狀態與轉換
`idle → loading → ready → playing ↔ paused → completed`；`loading/ready/playing` 可轉 `error`；切換音源先取消前次 load、採 generation token 防止過期完成覆蓋新狀態。

| 操作 | 正常結果 | 邊界案例 |
|---|---|---|
| Play | 從 position 播放 | duration 未知先待 ready |
| Pause | 暫停且儲存進度 | 多次 pause 冪等 |
| Seek | 定位至合法毫秒 | <0、>duration clamp；seek 進行中再次 seek 以最後一次為準 |
| Previous/Next Cue | 精確 seek 到英文 cue start | 無 cue / 已到首尾：停留並明確通知 |
| Speed | 倍速生效 | 0.5–2.0，非法值拒絕 |
| Loop | 僅在指定 cue 播放 | 切換 cue、拖曳時間軸與取消 loop 要正確還原 |
| Source switch | 舊 source 停止，新 source 載入 | 取消過期 async callback |

## 4. 單句循環策略
以英文主軌 cue 的 `[startMs,endMs)` 作區間。優先研究 `just_audio.setClip(start:..., end:...)` 搭配 loop 設定；如特定平台不支援、音訊解碼不精確，adapter 需明確回報限制和降級方案。絕不將 UI timer 每 16ms seek 當首選；檢查 playlist 與 clip 清理、下一句行為、連續點擊。

驗收精度：在 3 個不同來源媒體、不同手機及 Mac 上測量邊界行為。暫定重播起點誤差 ≤ 150ms（若 AAC/MP3 平台限制超出需記錄觀測、向使用者確認容許值）。不宣稱 sample-accurate loop。

## 5. 背景音訊
- `audio_session` 處理 interruption/noisy event；Android MediaSession、iOS audio background capability；macOS 控制/媒體按鍵支持需 Spike。
- `just_audio_background` 與 `audio_service` 選型需檢查當前 plugin platform support；允許 macOS 先用普通播放+生命周期策略，不把手機 API 支持推論成桌面支持。
- 鎖屏/藍牙/來電後須依平台事件保存進度，明確避免自動錯誤恢復。

## 6. 測試
`FakeAudioEngine` 可手動推進時間、模擬 buffered/error/interruption；測試 load race、seek racing、loop 清理、速度、狀態轉移、重啟恢復。真機測 Android/iOS/macOS 及 M4A/MP3；未執行的真機測試要標 BLOCKED。

## 7. WP-04 已交付的 adapter 行為
- `AudioEngine` 是播放器唯一上層入口；`JustAudioAdapter` 依賴可注入的 `AudioPlayerPort`，原生套件只存在於 `JustAudioPlayerPort`。Riverpod `audioEngineProvider` 負責建立及釋放 adapter。
- `load` 只接受 `file:`, `http:` 及 `https:` URI。每次載入增加世代；過期呼叫以 `AudioFailure.superseded` 結束，載入中 snapshot 先切到新教材。載入失敗映射為 `sourceUnavailable` 或 `unsupportedFormat`（`FormatException`），其餘原生錯誤為 `platform`。
- `seekTo` 以毫秒 clamp 到 `[0,duration]`。命令序列化，所以一組連續 seek 完成後最後一個位置生效。倍速接受 `[0.5,2.0]`，非有限或區間外數值拋 `ArgumentError`。
- 句循環透過 `setClip` + `LoopMode.one`，不使用高頻 UI timer。啟用與取消時暫停後重設 clip/位置，再恢復原播放狀態。seek 到循環範圍以外會清 clip；換音源前先停播、停用 loop 並清 clip。
- iOS/Android 將 `audio_session` 設為 speech 設定。中斷開始、包括 duck 事件及耳機拔除都暫停；中斷結束不自動恢復。macOS 暫無 `audio_session` 中斷訂閱；background/media-key 功能留 WP-10。
- `just_audio` 0.10.6、`audio_session` 0.1.25 已鎖入 `pubspec.yaml` / lockfile。使用 audio_session 0.1.25 是為保留 Android minSdk 21；其 Android Gradle 設定為 minSdk 19，且 just_audio 0.10.6 宣告相依範圍 `>=0.1.24 <0.3.0`。本地 unit tests 不代替真機播放測試。來源：[just_audio 0.10.6](https://pub.dev/packages/just_audio/versions/0.10.6)、[audio_session changelog](https://pub.dev/packages/audio_session/changelog)。
- 限制：`stop` 後由 adapter 額外 seek 到 0；平台播放器 loop 邊界精度、AAC/MP3 實際解碼延遲及中斷行為仍須 Android/iOS/macOS 實機 smoke，目標誤差 ≤150ms 未由本次假播放器驗證。
