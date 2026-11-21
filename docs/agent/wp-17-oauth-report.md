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
| Firebase 授權網域管理 API 讀取 | BLOCKED | 本機沒有可用的 gcloud OAuth access token，未能讀取完整 Authorized domains 清單；但本輪 localhost 實際 OAuth 成功，證明該來源可用 |
| Firebase 實際 Google 登入與重載恢復 | PASS | 2026-11-21 執行 `flutter run -d chrome --dart-define-from-file=.env.firebase-web`，在 `localhost` 完成 Google 授權並看到「已登入同步帳號」；重新載入後仍恢復登入。未記錄帳號或識別資料 |
| 真實帳號登出 | 未執行 | 保留使用者登入狀態；登出由 fake-port widget 測試覆蓋，尚未以真實帳號操作 |
| 跨分頁即時登入狀態更新 | 未實作 | 每個分頁初始化時會恢復 Firebase session；其他分頁登入／登出後，本分頁需重新整理。ID token 仍會以目前 UID 再檢查，scope 不匹配時拒絕 token |

## OAuth 驗收結果與後續網域確認

1. 本機 `localhost` 登入和重新載入恢復已實測通過。Google provider 啟用狀態沿用 WP-14 的 Firebase Console 確認紀錄；本階段沒有更改 Auth 設定。
2. 其他部署網域仍需專案擁有人在 Firebase Console 的 Authentication → Settings → Authorized domains 核對；正式部署前應以該網域再做一次實際 Google 登入。
3. 真實帳號登出未執行，避免清除目前有效 session；登出回復離線 scope 的契約由六個 widget 測試覆蓋。

## 已知限制與後續

- Firebase JS SDK 使用官方 `gstatic` CDN；離線或 CDN 不可達時，登入會在短 timeout 後停用，離線教材庫仍可使用。這是本階段依官方 Firebase CDN 載入文件採用的 Web-only 策略。
- Google OAuth popup 的正式使用者授權尚待人工走完；本交付不宣稱真實帳號登入 PASS。
- 下一步應先完成上方手動 OAuth 驗收並補上遮蔽個資的結果，再進入 Web Firebase 同步接線。不得因登入成功而默認使用者同意同步。
