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
