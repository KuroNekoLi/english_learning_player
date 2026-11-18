# WP-14 Firebase 同步交棒

後續 Google／Apple 登入已另列 [WP-14 登入補件](wp-14-social-sign-in.md)。下文保留原始 Emulator 驗收紀錄。

App 的教材庫在建置啟用 Firebase 時顯示同步入口。可用已存在的 Email/Password 測試帳號登入，手動同意同步後按「立即同步」，再選擇下載。登入後切到該 UID 的本機資料庫，同步同意及憑據只存在程式記憶體。原先離線空間由登出入口返回。

## 同步內容

- 以既有 outbox 發佈音訊。Storage 讀回後比對大小、MIME 與 SHA-256，成功才發佈 Firestore 教材。下載端驗證私有物件鍵、大小與 SHA-256，再快取至帳號空間，保留 material ID 且不重排上傳。
- 原始匯入的裝置同步目前選取的英中字幕。Storage 以內容雜湊保存 SRT 原始 bytes，Firestore 只存 manifest。接收端按語言讀取選取軌與 offset，保留本機手動選擇。
- 進度由 `syncProgress` Callable Function 驗證 Firebase ID token，以 Firestore 交易原子檢查 hash、receipt、sequence、canonical revision 與衝突候選。客戶端只能讀 UID 自己的 canonical 文件。開啟教材時沿用本機已確認進度，既有播放中的位置不受遠端寫入影響。
- 目前手動同步每次有界地消費 outbox。收藏與遠端播放清單／資料夾 metadata 留在既有待辦。操作上傳後會讀回驗證，正式成本與用量上限仍需確認。
- 資料夾掃描結果與手動選檔在寫入前驗證原帳號範圍。切換帳號後，先前帳號延遲完成的掃描不能進入新帳號的教材庫或 outbox。

## 接線決策

沿用既有 Flutter SDK 與平台最低版本，App 經既有 Repository、Service 介面使用 Firebase Auth、Firestore、Storage REST 與 Callable 協定。驗收用 build define 鎖定 demo 專案和本機 Emulator。FlutterFire 平台升級、憑據保存、遠端計費及發佈仍由既有 ADR 追蹤。

## 本機重跑

```sh
npm ci
npm ci --prefix firebase-functions
npm run test:firebase
```

測試指令使用專用 `demo-english-learning-player` 專案 ID，Auth、Firestore、Storage 與 Functions 都由 Emulator 提供。Node 22、Java 21 及 Flutter/Dart 版本沿用本機工具鍊。

啟動 Emulator 後，建置 App 時傳入以下兩個值即可使用本機服務：

```sh
flutter build macos --release \
  --dart-define=ELP_FIREBASE_PROJECT=demo-english-learning-player \
  --dart-define=ELP_FIREBASE_EMULATOR_HOST=127.0.0.1
```

## 驗收（2026-11-17）

| 項目 | 結果 |
| --- | --- |
| Dart 格式、Flutter Analyze | PASS。93 個 Dart 檔案，格式未變更。Analyze 無問題。 |
| Flutter Test | PASS。常規套件 122 項，同一套件的 Emulator 案例由專用指令執行。 |
| `npm run test:firebase` | PASS。乾淨的 demo Emulator：6 項 Rules 測試與 1 項 Flutter 雙客戶端整合測試。涵蓋 Auth、音訊上傳與去重、字幕、SHA-256、進度衝突及拒絕跨 UID 存取。 |
| macOS Release + Emulator | PASS。新 UID 登入後教材庫為空，開啟同步同意後讀到合成教材並下載。播放器載入雙語 SRT，從遠端確認的 2,400 ms 開啟，實際播放到進度條 100%。登出回到原離線教材庫。 |
| 正式 Firebase、Mac → iPhone | BLOCKED。缺可確認的測試 Firebase 專案及部署條件。iPhone 簽章與真機驗收依使用者排程延後。 |
| Android | 依使用者要求本輪先略過。 |

首次 macOS 測試曾重現舊離線帳號掃描晚回的競態，留下兩筆合成教材於該次 Emulator UID 的本機空間。當時同意未開啟，教材未由該 UID 上傳。修正後以另一個全新 UID 重測，新增的回歸測試也確認舊 binding 無法寫教材或 outbox。

## 遠端驗收前置條件

遠端測試環境透過建置時的 `ELP_FIREBASE_PROJECT`、`ELP_FIREBASE_BUCKET`、`ELP_FIREBASE_API_KEY`、`ELP_FIREBASE_PROGRESS_REGION` 接入，App 會使用 Firebase HTTPS 服務。需確認測試專案 ID、bucket、用於 Email/Password 登入的測試帳號、Callable 區域，以及部署 Firestore／Storage 規則與 Function 的權限。`firebase projects:list` 未能返回專案清單。本次只使用 demo Emulator，未建立雲端資源、部署或調整計費。網路恢復自動重試、遠端清單 metadata 及跨裝置真機仍待 Gate C 驗收。

設計依據：[Firebase Auth REST](https://firebase.google.com/docs/reference/rest/auth)、[Firestore REST](https://firebase.google.com/docs/firestore/use-rest-api)、[Firebase Storage SDK HTTP 實作](https://github.com/firebase/firebase-js-sdk/blob/main/packages/storage/src/reference.ts)、[Firebase Callable 協定](https://firebase.google.com/docs/functions/callable-reference)。
