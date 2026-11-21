# WP-14 Firebase 登入補件

## 範圍

在「設定與來源管理 → 帳號與同步」加入 Google／Apple 登入與登出。開啟登入頁、取消登入或遇到登入失敗時，使用者維持原本的離線空間。登入成功後，App 用 Firebase 核發的 UID 開啟帳號教材庫，同步預設關閉。登出清除 App 的 Firebase session 和同步同意，返回離線空間。

Google 在三平台使用 `google_sign_in`。Apple 在 iOS／macOS 使用系統登入介面與 SHA-256 nonce。Google、iOS Apple、macOS Apple 的 ID token 由既有 Firebase REST session 交換成 Firebase 憑據。Android 的 Apple 登入使用 Firebase Android SDK 的 OAuth 流程，由現有同步層取得該 UID 的 Firebase ID token。

Firebase 回傳相同 UID 時會開啟同一個教材庫。不同 UID 則維持各自獨立。遇到 Firebase 回報已有其他登入方式時，畫面指引使用原登入方式。連結相同使用者的多個登入方式需另做明確授權流程。

## 啟用條件

1. 在核准的 Firebase 專案註冊要驗收的平台 App，開啟所需登入方式。建置使用 `ELP_FIREBASE_PROJECT` 和同一專案的 `ELP_FIREBASE_API_KEY`，並保留 Firebase 授權網域 `<project>.firebaseapp.com`。只驗收登入時可使用 Spark，省略 `ELP_FIREBASE_BUCKET`，帳號畫面會隱藏教材同步操作。需要教材同步時才提供 `ELP_FIREBASE_BUCKET`，需要進度交易時也提供 `ELP_FIREBASE_PROGRESS_REGION`。
2. Google 共用 `--dart-define=ELP_GOOGLE_SERVER_CLIENT_ID=<Web OAuth client ID>`。Android 需登記該 APK 實際簽章的 SHA 指紋。iOS／macOS 分別傳入 `ELP_GOOGLE_IOS_CLIENT_ID`／`ELP_GOOGLE_MACOS_CLIENT_ID`，並在 `ios/Flutter/SocialSignIn.local.xcconfig`／`macos/Runner/Configs/SocialSignIn.local.xcconfig` 設定 `ELP_GOOGLE_REVERSED_CLIENT_ID = <REVERSED_CLIENT_ID>`。macOS 登入建置需由開發團隊簽章，並為使用的 configuration 加上 Google SDK 所需的 Keychain Sharing 群組 `$(AppIdentifierPrefix)com.google.GIDSignIn`。
3. iOS／macOS 啟用 `--dart-define=ELP_ENABLE_APPLE_SIGN_IN=true` 前，在 Apple Developer 更新 App ID 與簽章設定，並在 Xcode 的 Runner target 加入 **Sign in with Apple** capability。iOS 系統登入需要 iOS 13 起，較舊版本的 App 仍可執行。Apple 帳號、簽章和 Apple Developer 設定須由專案擁有者提供。
4. Android 的 Apple 登入需在 Apple Developer 設定與原生 App 的主要 App ID 關聯的 Services ID，將 Firebase 指定的 HTTPS 回呼網址註冊給 Apple，並在 Firebase 啟用該網頁授權設定。建置時用 `ORG_GRADLE_PROJECT_elpAppleAuth=true flutter build apk`，附上 `--dart-define=ELP_ENABLE_APPLE_SIGN_IN=true` 與 `--dart-define=ELP_FIREBASE_ANDROID_APP_ID=<Firebase Android app ID>`。此建置最低 Android API 23。其餘 Android 建置沿用 API 21。
5. Emulator 保留原有「使用測試帳號」流程。一般正式建置顯示 OAuth 登入方式；需要測試專案的 Email／Password 時可明確加上 `ELP_ENABLE_TEST_EMAIL_SIGN_IN=true`。App 啟動預設使用離線教材庫，Firebase 帳號與同步同意尚未接跨重啟還原。

macOS 最低版本由 10.14 調至 10.15，以配合 Google 官方 Flutter 外掛。Dart 3.8.1／Flutter 3.32.2 解析 `google_sign_in 7.2.0`（BSD 3-Clause）和 `sign_in_with_apple 7.0.1`（MIT）。iOS App deployment target 保持 12.0。

## 登入建置

在專案根目錄建立 Git 忽略的 `.env.firebase-auth`，以 `KEY=value` 記錄該環境的 Firebase Project ID、Firebase Web API key、Google Web OAuth client ID 及目標平台的 Google client ID。欄位名稱見上方。用 `flutter run -d macos --dart-define-from-file=.env.firebase-auth` 驗收 macOS，換成 `flutter devices` 列出的裝置 ID 可建置 Android 或 iOS。Apple 平台仍需完成上述 callback URL scheme 與簽章設定，啟用 Apple 登入時也須先備妥 App ID capability。

Android 的 Firebase 登錄識別為 `com.linli.englishlearningplayer`，iOS 與 macOS 的 Runner 目前以 `com.linli.englishlearningplayer` 建置。Google 的 Android SHA-1 須取自實際要測試或發佈的簽章。正式發佈使用 Play App Signing 時，登記 Play 提供的 app signing certificate。客戶端建置設定只使用 Firebase API key 與 OAuth client ID，Apple 私鑰和 OAuth client secret 直接填入對應後台。

## 正式 Google OAuth 設定進度（2026-11-21）

- 已建立 Spark 專案 `english-learning-player-auth`，顯示名稱為 English Learning Player Auth。Firebase Console 已確認 Google provider 啟用，支援信箱依使用者指定。此專案目前用於登入。
- App 的登入建置可以省略 Storage bucket。格式檢查、Flutter Analyze、146 項 Flutter 測試、6 項 Emulator 規則測試、2 項 Emulator 整合案例及 macOS Debug 建置通過。
- 待完成目標平台的 Firebase App 註冊、實際簽章或 callback URL 設定、寫入本機建置組態，以及以真實帳號完成登入登出。這次 macOS 沒有可用的程式碼簽章身分，Android 目前沒有連線中的裝置。Apple provider 待 Apple Developer Program 與對應 capability 就緒。
- macOS 追查記錄：目前執行的是本機 Debug App。其簽章為 ad hoc、沒有 TeamIdentifier，Google 回呼仍是 `elp-google-signin-disabled`，根目錄與 macOS 本機 OAuth 設定檔均缺席，簽章查詢回傳 0 個有效身分。恢復工作時先完成 Apple 平台的 Google OAuth client 註冊及建置設定，再用可用的 Apple 簽章重建並驗收實際登入登出。Codex 5 小時窗口剩餘 29%，依使用者設定暫停。

## 驗證方式

- 真實測試專案配置完成後，分別用 Google 與 Apple 登入、取消、登出及重新登入，核對每次教材庫隨 UID 切換、同步同意重新關閉。以同一 provider 在兩台裝置確認取得同一 UID，並測試 Apple 的「隱藏我的電子郵件」。
- 本機使用 Flutter widget 測試與 Firebase Auth Emulator 合成 provider token。真實 OAuth 需按上方條件設定後另外驗收。

## 驗收紀錄

| 項目 | 結果 |
| --- | --- |
| Dart 格式與 Flutter Analyze | PASS，格式無變更、Analyze 無問題。 |
| Flutter Test | PASS，136 通過，2 個需 Emulator 的案例略過。 |
| Firebase Emulator | PASS，6 個 Rules 測試與 2 個 Flutter 整合案例。初次整套執行的進度 Callable 冷啟動超過測試時限；用 localhost 預先觸發 Callable（預期未登入回 HTTP 401）並將測試時限設為 120 秒後通過。 |
| macOS Debug build | PASS。 |
| Android Debug build（開啟 Apple 登入） | PASS，Gradle `-PelpAppleAuth=true :app:assembleDebug`，JDK 17。Android 裝置登入尚未驗收。 |
| iOS 模擬器 | Flutter build FAIL（找不到 `TARGET_BUILD_DIR`）。Xcode 已編譯出含登入資產與 Framework 的新 Runner.app。直接 Xcode 重跑時磁碟剩餘低於 1 GiB，已停止重跑；尚無模擬器操作驗收。 |
| 真實 Google／Apple 登入 | BLOCKED，Firebase CLI 未能列出專案，尚無測試專案的 provider 設定。Apple 平台本機查無有效簽章身分。 |

官方依據：[Firebase Flutter 聯合登入](https://firebase.google.com/docs/auth/flutter/federated-auth)、[Firebase Auth REST](https://firebase.google.com/docs/reference/rest/auth)、[Apple 原生登入](https://firebase.google.com/docs/auth/ios/apple)、[Android Apple 登入](https://firebase.google.com/docs/auth/android/apple)、[Google Apple 平台設定](https://pub.dev/packages/google_sign_in_ios/versions/6.2.1)、[Google 登入按鈕資產](https://developers.google.com/identity/branding-guidelines)。
