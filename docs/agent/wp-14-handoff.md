# WP-14 與 Stage 3 Gate C 交棒

基準為 `ad90054`；以原始規劃 `00886d5` 和 [Gate C](../08-testing-and-quality.md) 驗收。

後續 App 接線與驗收結果見 [WP-14 Firebase 同步交棒](wp-14-firebase-handoff.md)。以下保留當時的驗收紀錄。

## 可執行路徑

- Mac Release 啟動時和資料夾事件後，使用已授權資料夾掃描，將 M4A／MP3 與雙語 SRT 匯入帳號私有儲存，教材和上傳 outbox 一起落地。
- `CloudMaterialDownloadService` 接受 transport 提供的教材資料，派送前檢查帳號、同意與私有物件鍵，串流限制大小，驗證 SHA-256 後才發佈快取。SQLite 保留遠端教材 ID，避免接收端建立新的上傳 outbox。原本的播放器可讀取已快取媒體並使用該教材 ID 的 canonical progress。
- 目前可驗證「macOS 實際匯入」與「模擬遠端接收」兩段。現有 Flutter UI 尚未接上可供實機使用的 Firebase Auth、Storage/Firestore transport、遠端教材列表、字幕與進度下載。遠端播放清單／資料夾 metadata 維持 ADR-028 的待整合狀態。

## macOS 播放真機驗收

首次播放重現兩個問題：just_audio 在尚無音源時拒絕清除 clip，另有 Riverpod loader 在一次性讀取等待依賴時先被釋放。修正後重開 macOS Release，選取 `Stage3-Demo` 並啟動音訊，時間軸推進到 100%。移到約 2 秒時畫面同時顯示英中字幕，SQLite 查到 2,488 ms 的進度操作已排入 outbox。合成目錄位於本機，iCloud 待下載狀態則以另一個已授權資料夾驗證。

## 本次命令

- PASS：`dart format --output=none --set-exit-if-changed .`（85 個 Dart 檔案）、`flutter analyze`、`flutter test --reporter expanded`（121 項）、`git diff --check`。
- PASS：`npm run test:rules`（5 項，Corretto 21，demo Firebase Emulator）。
- PASS：最終程式的 macOS Release、iOS Simulator Debug、Android Debug APK。Android 使用既有臨時 JDK 17 設定，仍有 NDK 版本警告。iPhone device build 曾以 `--no-codesign` 產出，真機安裝仍缺簽章。

## Gate C 核對

| 驗收 | 結果與證據 |
|---|---|
| WP-11 Sandbox 授權生命週期 | PASS：選取測試目錄後退出再開可還原，顯示 178 個待下載項目；解除授權後重開維持未連線。外部撤權／搬移及實際把 placeholder 下載成可讀檔仍待驗。 |
| WP-12 Mac 掃描到本機 outbox | PASS：使用者授權合成測試資料夾後出現教材。SQLite 查驗 `Stage3-Demo` 有兩軌 SRT 與一筆教材 outbox；在程式執行中另加入 `Stage3-Monitor`，免手動重掃即出現一軌 SRT 與一筆 outbox。遠端播放清單／資料夾 metadata 為 BLOCKED。 |
| WP-13 進度交易、拒權與斷線 | PASS：本機 Flutter 測試涵蓋權限、切換帳號、重試及衝突；demo Firestore 參考交易經兩個 client 併發驗證。通往受信任寫入者的實機 Auth 與斷網復原為 BLOCKED。 |
| WP-14 同帳號下載與續播 | PASS：Firebase Emulator 驗證同一 UID 可下載並比對檔案、異 UID 拒絕；Flutter 兩份 SQLite 驗證教材 ID、私有媒體載入與 canonical 位置。BLOCKED：iPhone 已配對，`security find-identity -v -p codesigning` 顯示 0 個有效身分。ADB 無 Android 裝置。App 尚缺正式同步接線與可用測試環境。 |

## 完成真機驗收時的重跑步驟

1. 使用專用 iCloud Drive 測試目錄，置入合法合成 M4A 與同名英中 SRT。啟動 Mac Release，由使用者授權後驗證自動匯入，再重啟、解除、搬移，以及從待下載轉為可讀。
2. 使用已核准的 Firebase 測試環境與同一測試 UID。記錄教材 ID、SHA-256 與已確認進度 revision。等待教材可下載，核對教材檔案、字幕與遠端清單，並確認雲端資料不含本機路徑或 bookmark。
3. iPhone 下載並打開教材，核對內容與 Mac 確認位置。播放期間在 Mac 更新進度，核對 iPhone 不會被遠端更新跳轉。用 Android 真機做下載和播放 smoke。
4. 斷網後在兩裝置各更新進度，再交錯復線。確認較舊 baseRevision 保留候選、重送不重複，登出換 UID 後不顯示原帳號資料。記錄裝置 OS、App commit 及每項 PASS／FAIL／BLOCKED。

執行本機規則及 transaction 測試可使用 `npm ci` 後以 Java 21 執行 `npm run test:rules`。這個命令指定 demo project 及本機 Auth、Firestore、Storage Emulator。
