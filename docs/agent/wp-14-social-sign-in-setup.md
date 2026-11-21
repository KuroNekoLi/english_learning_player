# WP-14｜Google／Apple 正式登入設定

本文件補充 `wp-14-social-sign-in.md`。主要 OAuth 程式已存在；正式登入還需 Firebase、Apple Developer 與簽章設定。**不得提交私鑰、登入 Token 或簽章檔。**

## Firebase 與 App ID

- 2026-11-21 `firebase projects:list` 回覆 HTTP 401。請由專案擁有者在終端執行 `firebase login --reauth`，並確認能列出 `english-learning-player-auth`。
- Firebase Console → Authentication → Sign-in method：Google provider 先前已啟用；Apple provider 須待 Apple Developer 設定完成後啟用。
- Android 現有 applicationId：`com.linli.englishlearningplayer`。iOS/macOS Bundle ID：`com.linli.englishlearningplayer`。已採用使用者確認的正式候選 ID；尚未在 Firebase 或 Apple Developer 註冊。發佈前須確認此識別碼仍由專案擁有者控制。
- 登入測試只需 Firebase Authentication，暫不開 Storage 或計費方案。

## Google OAuth

1. 在同一 Firebase／Google Cloud 專案取得 **Web OAuth client ID**，設定 `ELP_GOOGLE_SERVER_CLIENT_ID`。
2. Android：為實際 applicationId 登記 SHA-1、SHA-256，指紋可用 `cd android && ./gradlew signingReport` 查詢。正式發佈使用 Play App Signing 指紋。
3. iOS：取得 iOS OAuth client ID，填 `ELP_GOOGLE_IOS_CLIENT_ID`；建立 `ios/Flutter/SocialSignIn.local.xcconfig`，寫入 `ELP_GOOGLE_REVERSED_CLIENT_ID = com.googleusercontent.apps.XXX`。
4. macOS：填 `ELP_GOOGLE_MACOS_CLIENT_ID`；建立 `macos/Runner/Configs/SocialSignIn.local.xcconfig` 設該平台 reversed client ID。macOS Google 登入必須有 Apple 核發的簽章與 Keychain Sharing。

## Apple 登入

1. Apple Developer → Certificates, Identifiers & Profiles：為實際 iOS/macOS App ID 開啟 **Sign in with Apple**。於 Xcode Runner 設定 Team、程式碼簽章和 capability。iOS 已備好 `ios/Runner/Runner.entitlements`，但尚未啟用 Runner 的 Apple entitlement，以避免缺少簽章時破壞建置。
2. macOS 已備妥簽章版 `macos/Runner/SocialSignIn.DebugProfile.entitlements` 及 `macos/Runner/SocialSignIn.Release.entitlements`，同時包含 Google Keychain Sharing 和 Apple Sign-In。因本機沒有有效 Apple 簽章，**目前尚未掛到 Runner**，以維持一般 Debug 建置。取得有效簽章後，於 Xcode Runner → Build Settings → Code Signing Entitlements，將 Debug/Profile 設為前者、Release 設為後者，並在 Apple Developer 啟用對應 capability。
3. Android Apple：在 Apple Developer 建立與主要 App ID 關聯的 **Services ID**，設定 Return URL：`https://english-learning-player-auth.firebaseapp.com/__/auth/handler`。Firebase Authentication → Apple provider 填入 Services ID、Team ID、Key ID 與 Apple private key。**Apple private key 只填入 Firebase Console，不放到 App 或 Git。**
4. Apple provider 設定完成後再開啟 `ELP_ENABLE_APPLE_SIGN_IN=true`。Android 還需 `ELP_FIREBASE_ANDROID_APP_ID` 以及 `ORG_GRADLE_PROJECT_elpAppleAuth=true`，此模式 minSdk 23；未開啟時 Android 保留 minSdk 21。

## 執行與驗收

`cp .env.example .env.firebase-auth`，填入 Firebase Web API key、各平台 OAuth client ID、Firebase Android App ID。本機檔案已由 `.gitignore` 排除。Apple 的憑證／私鑰不要填入 `.env.firebase-auth`。

```bash
flutter run -d macos --dart-define-from-file=.env.firebase-auth
flutter run -d <iPhone-device-id> --dart-define-from-file=.env.firebase-auth
flutter run -d <Android-device-id> --dart-define-from-file=.env.firebase-auth
ORG_GRADLE_PROJECT_elpAppleAuth=true flutter run -d <Android-device-id> --dart-define-from-file=.env.firebase-auth
```

驗收：Google／Apple 登入、取消、登入失敗、登出、同一使用者 UID 穩定、跨裝置相同 UID、不同 UID 的離線教材庫隔離、Apple「隱藏電子郵件」。同步同意預設關閉；目前登入 session 不跨 App 重啟持久化，也不會自動連結 Google／Apple 帳號。

## 2026-11-21 實際驗證及阻礙

- Firebase CLI：原本 401，已在本機重新登入並驗證可以列出專案。
- `security find-identity -v -p codesigning`：**0 有效身分**，無法在實機驗收 Apple 平台登入。
- Android `.env.firebase-auth` 已取得並設好 Firebase API key、Web OAuth client ID；iOS/macOS 的 `SocialSignIn.local.xcconfig` 仍未設，真實 OAuth 仍需裝置驗收。
- Android 移除空白 `android:taskAffinity`，避免 Firebase Apple OAuth 的 Chrome Custom Tab 在應用程式切換後遺失。
- 原本 macOS entitlements 不動；簽章版本 opt-in。`flutter build macos --debug --no-pub` 已在無有效簽章環境下成功。

官方參考：[FlutterFire](https://firebase.google.com/docs/auth/flutter/federated-auth)、[Firebase Android Apple](https://firebase.google.com/docs/auth/android/apple)、[Google iOS/macOS](https://pub.dev/packages/google_sign_in_ios)、[Apple capability](https://developer.apple.com/documentation/xcode/configuring-sign-in-with-apple)。

本次本機驗證：`dart format --output=none --set-exit-if-changed .` 0 變更，`flutter analyze --no-pub` PASS，`flutter test --no-pub` 為 146 passed、2 skipped；macOS Debug Build PASS；Android Apple `:app:assembleDebug` 用 JDK 17 建置 PASS。

**Java 注意事項**：目前 Flutter 偵測 Android Studio JBR 25.0.4，直接 `flutter build apk` 因 Java 版本失敗；在專案 `android/` 下用 JDK 17 執行 Gradle 可成功。若要直接 `flutter run/build`，請先由開發者確認後以 `flutter config --jdk-dir=/Library/Java/JavaVirtualMachines/amazon-corretto-17.jdk/Contents/Home` 設定 Flutter 使用的 JDK（此為全機 Flutter 設定，並非本次自動修改）。

## 2026-11-21 正式候選識別碼遷移結果

- 使用者確認三平台識別碼改為 `com.linli.englishlearningplayer`。Android `namespace`、`applicationId`、原生 Kotlin package 路徑和音訊 Notification Channel 已同步；iOS/macOS 的 Runner、RunnerTests bundle ID 已同步。
- Apple Developer 尚未加入，故 iOS/macOS Apple Sign-In entitlements 保留為待啟用設定，無法完成 Apple OAuth 真機驗收。`.env.example` 預設 `ELP_ENABLE_APPLE_SIGN_IN=false`。
- Firebase CLI 重新登入後可以查詢 `english-learning-player-auth`，並已依使用者要求建立 **1 個 Firebase Android App**，不修改計費設定。
- 本次遷移驗證：Dart format 0 變更、Flutter Analyze PASS、Flutter Test 146 PASS／2 SKIP、Android 一般 Debug 與 Apple 原生變體使用 JDK 17 建置 PASS，產物 APK 的 package 已驗為 `com.linli.englishlearningplayer`；macOS Debug PASS，產物 Bundle ID 已驗為相同 ID。
- iOS Runner Xcode Debug build setting 已確認是新 Bundle ID；本次 iOS 模擬器建置結果因工具中斷未取得可驗證的完成狀態，因此標記 **未驗收**。

## 2026-11-21 Android Google OAuth 註冊實證

- Firebase Android App：`1:577523898008:android:5bfd5a24b19eecada2a2ed`，package `com.linli.englishlearningplayer`。
- 此 Mac Debug 憑證的 SHA-1 和 SHA-256 已由 Firebase CLI 登記，重新查詢回傳 **2 個 SHA**；Android APK 的實際 apksigner 指紋亦與這兩筆相符。
- 從新 Android App 的 SDK config 取得 Web OAuth client（client_type 3），寫入 gitignored `.env.firebase-auth`，包含 Firebase API key、Project ID、App ID；`ELP_ENABLE_APPLE_SIGN_IN=false`。
- 已以 JDK 17 + 真實 Dart defines 建置 Android Debug APK，Gradle BUILD SUCCESSFUL。**Google OAuth 真實登入/登出/UID 是否成功，須有可用的 Google Play services Android 裝置或模擬器，未驗證前不可標記 PASS。**

### Android Google 真實登入實測（本次）

- 已由官方 Android SDK Manager 安裝 `system-images;android-35;google_apis_playstore;arm64-v8a`，建立 AVD `ELP_Google_Login_API35`，並於 Mac 啟動 Pixel 6 API 35 Emulator。
- 已安裝使用 `ELP_GOOGLE_SERVER_CLIENT_ID` 及正式 Firebase API key 的 Android Debug APK。檢查 package 為 `com.linli.englishlearningplayer`，模擬器存在 `com.google.android.gms` 和 Play Store。
- 已實際打開 App「設定與來源管理 → 帳號與同步」，Google 登入選項顯示，Apple 登入未設定；點選 Google 按鈕後，Android 開啟官方 Google Accounts `Sign in` 畫面。
- **未通過完整 OAuth 驗收**：此 AVD 尚未登入 Google 帳號，需使用者本人於 Emulator 輸入 Google 帳號並完成 2FA。後續才能依序驗證 Google token 交換 Firebase UID、登出及同帳號重新登入 UID 一致；不得誤標 PASS。
- 本次沒有開通 Apple Developer、未啟用 Apple provider、未變更 Firebase 計費、未自動提交或推送 Git。

## macOS Google Desktop OAuth（不依賴 Apple Developer）

- Google Cloud Auth Platform 已建立 `English Learning Player macOS Desktop` 用戶端；Client ID：`577523898008-fkatgop14g31rpn3vf3qg3varsv6ugh5.apps.googleusercontent.com`。
- macOS 優先使用 `GoogleDesktopOAuth`：系統瀏覽器、`127.0.0.1` 臨時監聽埠、PKCE S256、加密亂數 state；取得 Google ID Token 再交給現有 Firebase REST `signInWithIdp`。不需要 Apple Developer 或 Google macOS native Keychain Sharing。
- 在 `.env.firebase-auth` 設定 `ELP_GOOGLE_DESKTOP_CLIENT_ID` 與 `ELP_GOOGLE_DESKTOP_CLIENT_SECRET`，不可提交憑證到 Git。Google Desktop OAuth 用戶端屬於 public client，密鑰不能視為用戶端可保密的長期憑證；PKCE 才是重要的防攔截措施。
- 實際測試 Google token endpoint 不帶 `client_secret` 回覆 `invalid_request: client_secret is missing`；因此此專案在 macOS 開啟登入按鈕前，**必須兩個欄位均已設定**。其他平台不受影響。
- 2026-11-21 已用真實 config 建置 macOS Debug PASS；Flutter analyze 0 issues；Flutter test 151 PASS、2 SKIP。Google 瀏覽器成功導向 loopback callback；**缺少 Desktop Client Secret 時 Token 交換失敗，Firebase UID、登出及再次登入尚未驗收**。
- Google Cloud 原始 Desktop Client Secret 建立後未保存，另已新增一組新密鑰；待新密鑰成功驗收後，應停用／刪除不再使用的舊密鑰。新密鑰須由帳號擁有者在 Google Cloud Console 以安全方式貼入本機 `.env.firebase-auth`，不要分享到聊天。
- 本機可使用 `/tmp/elp_google_desktop_secret_setup.py` 的隱藏輸入提示（若仍存在）完成 Secret 設定；完成後重新執行 `flutter build macos --debug --no-pub --dart-define-from-file=.env.firebase-auth`，再啟動最新 App，驗證 Google 登入、登出及 UID 穩定。

### 2026-11-21 macOS Desktop OAuth 憑證完成驗證

- 使用者以 Terminal 隱藏輸入方式補上新 Desktop Client Secret，本機 `.env.firebase-auth` 權限 `0600` 並受 Git ignore 保護。
- 在 Google `/token` 端點使用刻意無效的授權碼測試：未帶 Desktop Client Secret → `invalid_request: client_secret is missing`；帶新 Client ID + Secret → `invalid_grant: Malformed auth code`，確認新憑證被 Google 辨識（不等於已完成使用者授權）。
- 使用最新 `.env.firebase-auth` 執行 macOS Debug 建置 PASS，Bundle ID `com.linli.englishlearningplayer`，已啟動。Flutter test 無／有真實環境設定時，macOS Google Provider 配置測試均 PASS。
- Firebase Authentication users 檢查時為 0 位使用者，因此實際登入、登出與 UID 一致性**尚未完成驗收**。需要在最新 macOS App 的「設定與來源管理 → 帳號與同步」實際點擊 Google 登入、在系統瀏覽器授權；之後核對 Firebase UID，再登出與再次登入。

### 2026-11-21 macOS 首次真實 Google 登入驗證

- 實際瀏覽器授權已完成，Firebase Authentication user count 由 0 → 1，唯一使用者的 provider 為 `google.com`。Firebase UID 已在當次驗證確認（避免在 repo 文件記錄個人帳號識別，不在這裡寫 UID）。
- macOS Debug / Release 均以完整 Desktop OAuth 設定建置 PASS；Release 為本機 ad-hoc 簽章，含 `com.apple.security.network.client`、`com.apple.security.network.server` 及 Sandbox 權限。
- Google Cloud 先前未儲存的舊 Desktop Client Secret 已停用；新密鑰為唯一啟用的一組。仍須人工驗證 App 端登出後重新登入，並核對 `lastSignedInAt` 更新且 UID 不變。
- `flutter analyze` PASS，`flutter test --no-pub` 152 PASS、2 SKIP。此流程不需 Apple Developer；正式對外發行 macOS 則另需考量 Developer ID 簽章與公證。
