# WP-17 OAuth 階段交付紀錄

日期：2026-11-21
分支：`codex/wp-17-web-smoke`
基準：`fd16257`（WP-17 Web 失敗復原與離線播放驗收）

## 範圍

加入 Flutter Web 的 Google/Firebase Authentication 登入與登出，登入狀態以 Firebase UID 隔離本機教材資料。登入不代表同意雲端同步；同步仍未開放。本次沒有實作 Apple Web 登入、OAuth 同步傳輸或雲端資料功能。

Firebase 官方文件提供 Web Google 登入的 `GoogleAuthProvider` 與 `signInWithPopup`，也說明 FlutterFire 的 federated auth。考量本專案原生最低 OS 版本和既有 FlutterFire 相容性契約，本階段採用 Web 專屬官方 Firebase JavaScript SDK CDN adapter；原生 Firebase 登入實作未被替換。參考：[Firebase Web Google Sign-In](https://firebase.google.com/docs/auth/web/google-signin)、[Firebase JavaScript SDK 的 CDN 載入](https://firebase.google.com/docs/web/alt-setup)、[Firebase Flutter federated auth](https://firebase.google.com/docs/auth/flutter/federated-auth)。

## 交付內容

- `WebFirebaseAuthAdapter` 封裝 JS SDK，採瀏覽器本機持久登入；支援 Google popup、登出與 Firebase ID token。
- JS Bridge 僅回傳 UID、錯誤代碼及受 UID 檢查的 ID token，不回傳 email 或 provider credential。
- Riverpod session 將登入者映射至 `AccountScope(uid)`；未登入保持 `local-default`。登入／登出切換前會先關閉播放器，避免舊帳號的播放工作跨越 scope。
- 教材庫加入帳號入口與 Google 登入／登出頁。登入狀態不自動啟用同步。
- Firebase Web App 註冊在既有 `english-learning-player-auth` 專案，沒有建立 Cloud Storage、Functions 等付費服務。實際 Web 設定留在 gitignored 的 `.env.firebase-web`；範本只提交空白設定欄位。
- 本機啟動：`flutter run -d chrome --dart-define-from-file=.env.firebase-web`。正式環境應以部署環境變數注入同一組 Firebase Web 公開設定，勿提交 `.env.firebase-web`。

## 驗收

| 項目 | 結果 | 證據 |
|---|---|---|
| `dart format --output=none --set-exit-if-changed .` | PASS | 170 個 Dart 檔案，0 個需格式化 |
| `flutter analyze --no-pub` | PASS | No issues found |
| `flutter test --no-pub --reporter expanded` | PASS | 162 通過；2 個 Firebase Emulator 測試略過 |
| Web OAuth widget tests in Chrome | PASS | `flutter test --no-pub --platform chrome test/features/auth/web_account_sign_in_test.dart`；6 通過 |
| Web build | PASS | `flutter build web --no-pub --dart-define-from-file=.env.firebase-web` |
| OAuth UI/session/account-scope widget tests | PASS | 6 個測試：取消、成功與 UID token guard、登出、切帳號、popup/domain 失敗、登入恢復、未設定狀態；VM 與 Chrome 均通過 |
| Firebase Google provider 設定 | PASS（既有證據） | [WP-14 登入紀錄](wp-14-social-sign-in.md) 記錄 Firebase Console 已確認 Google provider 啟用；本輪未變更 Auth 設定 |
| Firebase 授權網域即時讀取 | BLOCKED | 本機沒有可用的 gcloud OAuth access token；本輪未讀取 Authorized domains，部署網址仍需由專案擁有人核對 |
| Firebase 實際 Google 帳號登入、同意畫面及登出 | BLOCKED | 本輪未使用任何真實使用者憑據完成授權；Web build 與 fake-port 測試不等於正式 provider E2E |
| 跨分頁即時登入狀態更新 | 未實作 | 每個分頁初始化時會恢復 Firebase session；其他分頁登入／登出後，本分頁需重新整理。ID token 仍會以目前 UID 再檢查，scope 不匹配時拒絕 token |

## 人工完成真實 OAuth 驗收

1. 在 Firebase Console 核對 `english-learning-player-auth` 的 Authentication → Sign-in method（WP-14 紀錄已確認 Google 啟用），並確認這次實際測試的 `localhost` 與部署網域都在 Authorized domains 中。設定值本階段沒有透過程式自動變更。
2. 使用上述啟動命令開啟 `localhost` 網址；在未確認授權清單前，不要假設該來源可進行 OAuth。
3. 在「教材庫 → 帳號與同步」按 Google 登入，完成使用者自己的 Google 授權；確認顯示已登入，重新載入後 session 仍在，登出後返回本機離線教材庫。
4. 若部署網域不在授權清單，Firebase 會拒絕 popup；需由專案擁有人在 Console 加入該網域後重試。

## 已知限制與後續

- Firebase JS SDK 使用官方 `gstatic` CDN；離線或 CDN 不可達時，登入會在短 timeout 後停用，離線教材庫仍可使用。這是本階段依官方 Firebase CDN 載入文件採用的 Web-only 策略。
- Google OAuth popup 的正式使用者授權尚待人工走完；本交付不宣稱真實帳號登入 PASS。
- 下一步應先完成上方手動 OAuth 驗收並補上遮蔽個資的結果，再進入 Web Firebase 同步接線。不得因登入成功而默認使用者同意同步。
