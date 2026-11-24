# WP-18 帳號密碼唯讀登入交棒

日期：2026-11-24
狀態：本機實作與 Rules Emulator 通過；正式登入、部署與 Firebase Console 狀態未驗證。

## 決策（ADR-035）

- `kuroneko_li` 是獨立 Firebase Auth 使用者，內部 email alias 固定為 `kuroneko_li@english-learning-player-auth.firebaseapp.com`。其 Auth UID、本機 Drift 帳號 scope、媒體私有副本與 Google owner 帳號分離。
- 遠端 owner 由 Firebase Admin SDK 設定的 `elpReadOnlyOwnerUid` custom claim 指定。原生與 Web App 讀取使用本機登入 UID 取得 ID token，讀取 owner 的 Firestore/Storage 路徑；下載資料仍寫入 reader 的本機 scope。
- `provisionReadOnlyLogin` callable 僅接受 Google provider，且 owner UID 必須符合部署參數 `ELP_READONLY_OWNER_UID`。只有受信任 Admin SDK 設定 claim；不得用用戶端欄位或 username 判定雲端權限。
- Firestore／Storage Rules 允許 reader 讀 claim 指定的 owner 資料，但不允許 reader 寫入。`syncProgress` Callable 拒絕 reader。客戶端唯讀狀態及隱藏按鈕不是安全邊界。
- 使用者表示測試用 Email/Password 已啟用，並要求測試帳號沿用已指定憑證。程式和測試不保存實際密碼；App/Callable 支援至少 6 字元，實際 Firebase Console 若設更嚴密碼政策仍會拒絕較弱密碼。

## 本機實作

- 原生與 Web 登入表單將 username 映射為固定 alias，呼叫 Firebase Email/Password 登入；登入 session 解析伺服器 ID token 的 `elpReadOnlyOwnerUid` claim，分別暴露本機 `uid` 與雲端 `cloudUid`。
- Google owner 使用 App 呼叫 `provisionReadOnlyLogin` 建立／更新 reader 帳密，維持 owner session，不採用 link credential 或同 UID 模式。
- Reader 不建立媒體上傳、library 變更或進度同步 writer coordinator。下載的素材、字幕和遠端進度寫入 reader 本機 scope。
- Firestore/Storage Rules 和進度 Callable 採 custom claim 做唯讀授權；Firebase Auth Emulator 的 Rules 測試覆蓋 owner 寫入、reader 讀取、reader 寫入拒絕與跨 owner 拒絕。

## 正式部署前置條件

1. 使用 Google 登入目前存有教材的帳號，在 Firebase Console Authentication > Users 取得其 UID。不可猜測或用 email 代替 UID。
2. 確認 Firebase Console > Authentication > Sign-in method 的 Email/Password 已啟用。使用者回報已啟用，但本工作環境未連線即時驗證。
3. 設定 Functions 參數 `ELP_READONLY_OWNER_UID` 為步驟 1 的 UID。若固定 alias 已被預先註冊且未有預期 claim，先由專案管理者確認並移除該佔位帳號，再由 callable 建立；不可由用戶端提升既有帳號權限。
4. 先在 Emulator 驗證，再部署 callable、`firestore.rules`、`storage.rules`。
5. 更新 App 後使用 Google owner 建立 reader；登出並以 `kuroneko_li` 登入，驗證下載、跨裝置清單/字幕讀取、雲端寫入拒絕、本機 library/progress/outbox 隔離，再確認 Google writer 仍可正常寫入。

本地工作尚未部署雲端，也未新增 Firebase 資源或啟動計費服務。

## 本機驗收狀態

- `dart format --output=none --set-exit-if-changed .`：PASS，210 個 Dart 檔無變更。
- `flutter analyze`：PASS，No issues found。
- `flutter test --reporter compact`：PASS，200 passed、3 skipped（既有 Firebase Emulator-only 測試）。登入及 Web scope 目標測試另行通過。
- `npm run test:rules`：PASS，10/10。
- Functions/Auth bridge JavaScript 語法檢查：PASS（`node --check`）。
- Web release、macOS debug、Android debug APK、iOS Simulator debug build：PASS。真實 Auth Emulator sign-in/provision callable 未執行。
- Firebase Console 設定、正式 Rules/Functions 部署與實際兩帳號驗收：BLOCKED，待取得 Google owner UID 並安排部署。

## 下一步

完成本次全量測試後，取得 Google owner UID 並在 Functions 環境設定 `ELP_READONLY_OWNER_UID`。部署前重新審查 Functions/Roles；上線後依序驗證 reader download/read、deny-write 和本機隔離。
