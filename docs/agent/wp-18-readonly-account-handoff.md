# WP-18 帳號密碼唯讀登入交棒

日期：2026-11-24
狀態：本機程式與 Emulator Rules 實作完成；Firebase Console、正式 Rules/Functions 部署與真實登入未執行。

## 決策

- `kuroneko_li` 是既有 Google Firebase UID 上的 Email/Password 登入憑證，不是第二個 Auth UID；其 internal alias 固定為 `kuroneko_li@english-learning-player-auth.firebaseapp.com`。
- 唯讀權限依 `email` alias 與 Firebase token `firebase.sign_in_provider=password` 雙條件判定。Google 登入仍為 writer；既有一般 Email/Password 測試帳號不受影響。
- password reader 以 `${uid}:password-reader` 作本機 Drift/媒體 profile，`cloudUid` 指回原 UID。reader 可下載雲端教材、字幕與進度，但 outbox、播放進度與本機操作留在分離的本機 profile。
- 規則在 Firestore/Storage 和 `syncProgress` Callable 拒絕 alias password 登入的雲端寫入。Flutter UI／停用同步按鈕不是安全邊界。
- 不引入 `firebase_ui_auth`。官方 FirebaseUI 的預建 Email UI 以 email 為欄位；目前原生登入使用 REST、Web 使用現有 Firebase JS SDK。本次新增專用 username UI 並沿用既有 Auth Adapter。

## 本機實作

- 原生 Auth REST `accounts:update` 將 username alias/password 連結到目前 Google Auth 使用者；成功後登出，要求重新 Google 登入。username 登入映射為 Firebase email alias。
- Web Auth JS bridge 使用 Firebase `EmailAuthProvider`、`linkWithCredential`、`signInWithEmailAndPassword`，Firebase token 持久化沿用瀏覽器 SDK。
- reader profile 的自動同步只有雲端讀取與下載；不建立 `CloudSyncCoordinator` / `ProgressSyncCoordinator`。遠端進度轉為 reader 本機 scope，不回寫雲端。
- Firestore／Storage Rules 和 Callable 已加密碼 alias 的寫入拒絕。Rules Emulator 對 owner/write 與 reader/read + deny write 有正反測試。
- 設定畫面預填固定 `kuroneko_li`。密碼要求至少 12 字元；對話中已輸入的弱密碼未寫入程式、設定或測試，且不應再使用。

## 正式環境啟用前置步驟

1. Firebase Console `english-learning-player-auth` → Authentication → Sign-in method：啟用 Email/Password。這是正式 Firebase 外部設定，尚未更改。
2. 更新 App 到包含本功能的版本，以 Google 登入含現有雲端教材的原帳號。
3. 「帳號與同步」→「設定帳號密碼唯讀登入」；username 固定為 `kuroneko_li`，使用者在 App 內直接輸入全新、唯一、至少 12 字元的密碼。不要重用已在聊天中暴露的舊密碼。新增憑證後 App 會登出，重新以 Google 登入一次。
4. 先於 Emulator 驗證，再部署最新版 `firestore.rules`、`storage.rules` 和 `syncProgress` Function 至既有 Firebase 專案。此次 Agent 工作未部署雲端。
5. 登出後以 `kuroneko_li` 登入，確認同 UID、可讀清單及下載，並確認 Firestore/Storage 寫入和進度 Callable 均被拒絕；再以 Google 登入確認 writer 功能正常。檢查 reader 與 writer 的本機 library、progress、outbox 互相隔離。

## 驗收狀態

- `dart format --output=none --set-exit-if-changed .`：PASS，210 個 Dart 檔無變更。
- `flutter analyze`：PASS，No issues found。
- `flutter test --reporter compact`：PASS，200 passed、3 skipped（既有 Emulator-only tests）。
- `npm run test:rules`：PASS，10/10，包括 Firestore/Storage password alias 讀取成功、寫入拒絕及 Callable guard 分類。
- JS syntax check（Auth bridge、Functions）：PASS。
- Web release、Android debug APK、iOS Simulator、macOS debug build：PASS。
- Firebase Auth Emulator 實際 credential linking / password login：尚未執行。
- 真實 Firebase Console provider 設定、正式 Rules/Function deploy、Google/password 雙登入驗收：BLOCKED，需人工操作及部署。
- Android/iOS/macOS 真機 build/install/sign-in：未測。

## 下一步

本機全測及四平台 build 已完成。下一步是在 Firebase Auth Emulator 補上並執行實際 credential linking / password sign-in 測試；接著由專案管理者在 Firebase Console 啟用 Email/Password，使用原 Google UID 設定全新強密碼，再部署 Rules、Storage Rules 與 Function。正式雙登入及兩種 credential 的雲端寫入邊界驗收完成後，更新本交棒狀態。
