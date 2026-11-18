# WP-14 Firebase 登入補件

## 範圍

在「設定與來源管理 → 帳號與同步」加入 Google／Apple 登入與登出。開啟登入頁、取消登入或遇到登入失敗時，使用者維持原本的離線空間。登入成功後，App 用 Firebase 核發的 UID 開啟帳號教材庫，同步預設關閉。登出清除 App 的 Firebase session 和同步同意，返回離線空間。

Google 在三平台使用 `google_sign_in`。Apple 在 iOS／macOS 使用系統登入介面與 SHA-256 nonce。Google、iOS Apple、macOS Apple 的 ID token 由既有 Firebase REST session 交換成 Firebase 憑據。Android 的 Apple 登入使用 Firebase Android SDK 的 OAuth 流程，由現有同步層取得該 UID 的 Firebase ID token。

Firebase 回傳相同 UID 時會開啟同一個教材庫。不同 UID 則維持各自獨立。遇到 Firebase 回報已有其他登入方式時，畫面指引使用原登入方式。連結相同使用者的多個登入方式需另做明確授權流程。

## 啟用條件

1. 在核准的 Firebase 測試專案註冊要驗收的平台 App，開啟 Google 與 Apple 登入方式。建置使用 `ELP_FIREBASE_PROJECT`、`ELP_FIREBASE_BUCKET`、`ELP_FIREBASE_API_KEY`，以及需要進度同步時的 `ELP_FIREBASE_PROGRESS_REGION`。使用同一個 Firebase 專案的設定，並保留 Firebase 授權網域 `<project>.firebaseapp.com`。
2. Google 共用 `--dart-define=ELP_GOOGLE_SERVER_CLIENT_ID=<Web OAuth client ID>`。Android 需登記該 APK 實際簽章的 SHA 指紋。iOS／macOS 分別傳入 `ELP_GOOGLE_IOS_CLIENT_ID`／`ELP_GOOGLE_MACOS_CLIENT_ID`，並在 `ios/Flutter/SocialSignIn.local.xcconfig`／`macos/Runner/Configs/SocialSignIn.local.xcconfig` 設定 `ELP_GOOGLE_REVERSED_CLIENT_ID = <REVERSED_CLIENT_ID>`。macOS 登入建置需由開發團隊簽章，並為使用的 configuration 加上 Google SDK 所需的 Keychain Sharing 群組 `$(AppIdentifierPrefix)com.google.GIDSignIn`。
3. iOS／macOS 啟用 `--dart-define=ELP_ENABLE_APPLE_SIGN_IN=true` 前，在 Apple Developer 更新 App ID 與簽章設定，並在 Xcode 的 Runner target 加入 **Sign in with Apple** capability。iOS 系統登入需要 iOS 13 起，較舊版本的 App 仍可執行。Apple 帳號、簽章和 Apple Developer 設定須由專案擁有者提供。
4. Android 的 Apple 登入需在 Apple Developer 設定與原生 App 的主要 App ID 關聯的 Services ID，將 Firebase 指定的 HTTPS 回呼網址註冊給 Apple，並在 Firebase 啟用該網頁授權設定。建置時用 `ORG_GRADLE_PROJECT_elpAppleAuth=true flutter build apk`，附上 `--dart-define=ELP_ENABLE_APPLE_SIGN_IN=true` 與 `--dart-define=ELP_FIREBASE_ANDROID_APP_ID=<Firebase Android app ID>`。此建置最低 Android API 23。其餘 Android 建置沿用 API 21。
5. Emulator 保留原有「使用測試帳號」流程。一般正式建置顯示 OAuth 登入方式；需要測試專案的 Email／Password 時可明確加上 `ELP_ENABLE_TEST_EMAIL_SIGN_IN=true`。App 啟動預設使用離線教材庫，Firebase 帳號與同步同意尚未接跨重啟還原。

macOS 最低版本由 10.14 調至 10.15，以配合 Google 官方 Flutter 外掛。Dart 3.8.1／Flutter 3.32.2 解析 `google_sign_in 7.2.0`（BSD 3-Clause）和 `sign_in_with_apple 7.0.1`（MIT）。iOS App deployment target 保持 12.0。

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
