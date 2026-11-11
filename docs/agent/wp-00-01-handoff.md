# WP-00／WP-01 交棒

- 觀測日期 2026-11-10 至 2026-11-11。本機 Apple Silicon，macOS 26.6。起始版本 `00886d5`，交付分支 `codex/wp-00-01-stage-1`。
- WP-00 先核對工具鏈與同組套件解析，並執行原始樣板建置。WP-01 交付離線教材庫 bootstrap、Dart 契約、fake 測試與 ADR。三平台交付版建置使用暫存副本及原本的原生專案設定。

## WP-00 工具鏈與建置

| 平台 | 觀測到的工具鏈 | 交付版結果 |
|---|---|---|
| 共用 | Flutter stable 3.32.2 (`8defaa71a7`)、Dart 3.8.1 | `flutter pub get` **PASS** |
| Android | SDK 36／Build Tools 36.0.0、Gradle 8.12、AGP 8.7.3、Kotlin 2.1.0 | `flutter build apk --debug` **PASS**，只為該次程序指定既有 Corretto 17.0.15 |
| iOS | Xcode 26.2 (17C52)、CocoaPods 1.16.2 | `flutter build ios --debug --no-codesign` **PASS**，產出 `build/ios/iphoneos/Runner.app` |
| macOS | Xcode 26.2 (17C52)、CocoaPods 1.16.2、arm64 | `flutter build macos --debug` **PASS**，產出 `build/macos/Build/Products/Debug/english_learning_player.app` |

Android 原始樣板以 Flutter 預設選到 Android Studio JDK 25.0.4，Gradle 以 `25.0.4` 錯誤退出（**FAIL**）。相同 wrapper 用既有 JDK 17 後 `./gradlew assembleDebug` 通過，交付版也以 Flutter 的 build 命令通過。Android toolchain 仍回報部分授權未接受。本次建置在既有授權下自動安裝 NDK 26.3.11579264。JDK 25 需要 Gradle 9.1 或更新版本。 [Gradle Java 相容表](https://docs.gradle.org/current/userguide/compatibility.html#java)

重跑 Android 時可在暫存副本使用下列命令。當本機有舊版 `~/.flutter_settings` 時，Flutter 優先讀該檔，可改用已生成 `android/local.properties` 的副本，以 `JAVA_HOME` 指定 JDK 並從 `android/` 執行 `./gradlew assembleDebug`。

```sh
elp_flutter_settings="$(mktemp -d)"
python3 -c 'import json, subprocess; print(json.dumps({"jdk-dir": subprocess.check_output(["/usr/libexec/java_home", "-v", "17"], text=True).strip()}))' > "$elp_flutter_settings/settings"
XDG_CONFIG_HOME="$elp_flutter_settings" flutter build apk --debug
```

## 套件與原生驗證範圍

同一個暫存副本的 `flutter pub get` 同時解析下表全部版本。僅 Riverpod 進入工作專案的 `pubspec.yaml` 和 lockfile。

| 套件 | 實際解析 | 證據及後續 |
|---|---|---|
| [flutter_riverpod](https://pub.dev/packages/flutter_riverpod/versions/3.3.2) | 3.3.2（MIT，Dart ^3.7） | 三平台 bootstrap 建置，Repository override Widget 測試 |
| [Drift](https://pub.dev/packages/drift/versions/2.31.0) | 2.31.0（MIT，Dart ≥3.5），sqlite3 2.9.4 | WP-02 需選定三平台 SQLite 載入與遷移，2.31.x 需核驗移動平台的 SQLite 原生提供方式。[Drift 平台文件](https://drift.simonbinder.eu/platforms/vm/) |
| [just_audio](https://pub.dev/packages/just_audio/versions/0.10.6) | 0.10.6（MIT，Flutter ≥3.27、Dart ^3.6），audio_session 0.2.4（MIT） | Android／iOS 真機解碼、MP3、Seek、背景中斷留 WP-04／10 |
| FlutterFire（BSD-3-Clause） | [Core 5.1.0](https://pub.dev/packages/firebase_core/versions/5.1.0)、[Auth 7.0.1](https://pub.dev/packages/firebase_auth/versions/7.0.1)、[Firestore 7.1.0](https://pub.dev/packages/cloud_firestore/versions/7.1.0)、[Storage 14.0.1](https://pub.dev/packages/firebase_storage/versions/14.0.1) | package metadata 的 Android minSdk 24 與 iOS 15，高於樣板的 21 與 12。macOS Spike 以 11.0 和獨立的 debug outbound network entitlement 建置。這組原生依賴未在 Android／iOS 裝置上驗證。 |

macOS Podfile.lock 解析到 Apple Core／Firestore 12.19.3，Auth／Storage 12.19.0。Firebase 官方支援表將 macOS Auth／Firestore／Storage 標為 beta，並列出 Keychain Sharing 要求。CocoaPods 已停止發佈新 Firebase Apple SDK，正式 Apple 套件管理、Keychain 登入存續及簽章需要另驗。 [FlutterFire 設定及支援表](https://firebase.google.com/docs/flutter/setup)、[CocoaPods 遷移說明](https://firebase.google.com/docs/ios/cocoapods-deprecation)

### macOS 原生 Spike 執行結果

| 項目 | 結果 | 觀測 |
|---|---|---|
| FlutterFire 與音訊原生插件編譯及連結 | **PASS** | `flutter build macos --debug`，Runner target 11.0，macOS 26.6 arm64 實際執行 |
| Drift／SQLite | **PASS** | `NativeDatabase.memory()` 執行 `SELECT 42`，確認回傳值 |
| just_audio | **PASS** | 從 app staging 載入自產的 AAC/M4A，回傳有效時長 |
| Firebase Core | **PASS** | demo Firebase options 初始化成功 |
| Firebase Auth | **FAIL** | 本機 Auth Emulator 匿名登入到 Keychain 保存時回報 `firebase_auth/keychain-error`，`SecItemAdd (-34018)` 缺少必要 entitlement。有效 Apple 簽章與 Keychain Sharing 重驗 **BLOCKED** |
| Cloud Firestore | **PASS** | Auth 失敗後，以只對本機測試路徑放行的 Rules 寫入合成資料並從 emulator server 讀回 |
| Cloud Storage | **PASS** | Auth 失敗後，以只對本機測試路徑放行的 Rules 上傳／下載合成內容並比較位元資料 |

上述資料服務 PASS 涵蓋 macOS 原生 SDK 和本機 Emulator 傳輸。已登入的端到端流程仍受 Keychain 阻擋。正式 Rules、跨 UID 拒絕存取、正式 bucket、iOS／Android 的 FlutterFire 原生執行留待各工作包驗證。兩次 emulator 試跑均自動關閉服務。完整步驟、Dart probe 與 loopback Rules 見 [macOS Spike 重跑](wp-00-macos-smoke.md)。

## WP-01 程式與接口

| 檔案 | 交付 |
|---|---|
| [main.dart](../../lib/main.dart)、[library_page.dart](../../lib/app/library_page.dart)、[library_view_model.dart](../../lib/features/library/library_view_model.dart) | Flutter 啟動 → Riverpod → 教材庫讀取。UI 有 loading、空清單和讀取失敗後手動重試。預設使用空的本機 Repository，測試注入合成教材並確認 UI 渲染。 |
| [material_repository.dart](../../lib/features/library/material_repository.dart) | `MaterialRepository.listMaterials()`、不可變的 `LearningMaterial`／`MaterialStatus`，Repository instance 限單一 profile。 |
| [audio_engine.dart](../../lib/core/audio/audio_engine.dart) | `AudioEngine`、`MediaSource`、`PlaybackSnapshot`、`TimeRange`、型別化錯誤。單一入口支援 load、play／pause／stop、seek、speed、loop、snapshot stream 和 dispose。 |
| [folder_access_gateway.dart](../../lib/core/platform/folder_access_gateway.dart) | `FolderAccessGateway` 的 pick、restore、scan、watch、stage、disconnect，包含取消、授權狀態及待下載。 |
| [progress_policy.dart](../../lib/core/sync/progress_policy.dart) | `ProgressCheckpoint` 和 `decideProgress`。輸入目前 canonical revision 及該 session 最高 sequence，輸出 accept、ignoreStale 或 keepConflict。 |
| [資料模型](../02-domain-models.md)／[同步規格](../06-cloud-sync.md)／[資料夾規格](../07-icloud-folder-sync.md)／[ADR](../12-decisions-and-risks.md) | 固定帳號範圍、教材／資產身分、進度 revision、outbox 與裝置授權邊界。保留 Auth provider、計費、Apple SwiftPM、OS 下限、快取保留期與清理政策的未決項目。 |
| [test/](../../test) | FakeAudioEngine、FakeFolderAccessGateway、Widget 測試內的 FakeMaterialRepository。 |

### 實際驗收

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --reporter expanded
git diff --check
```

上述命令均 **PASS**。9 個測試覆蓋 FR-01 的啟動骨架、Repository 注入與錯誤重試、FR-04 的音訊接口與 Seek 邊界、FR-11 的授權與 placeholder 邊界，以及 FR-10／12 的進度規則。完整 T-PLATFORM、T-AUDIO、T-FOLDER、T-SYNC 驗收保留給對應工作包。iOS 真機部署及簽章驗證 **BLOCKED**，須有測試用 Apple 開發者簽章。iCloud sandbox 真實授權 **BLOCKED**，須在 WP-11 建立原生 adapter、核准能力並由使用者選取測試目錄。正式 Firebase 專案／Blaze **BLOCKED**，等待專案、區域與費用決策。

## 交棒

建議 **WP-02** 將 `MaterialRepository` 接到本機 Drift v1 schema、app 私有媒體副本和手動匯入。依序驗證資料庫重開後讀回、匯入去重與帳號隔離。WP-08 在接 Firebase 前重跑 macOS Spike 並新增 Rules 正反向、部分失敗重送與跨帳號測試。WP-09 用真實交易驗證 canonical revision、receipt 與候選的原子性。

工作專案的 Android／iOS／macOS 原生設定、簽章與權限無差異。未建立雲端專案、遠端資源或計費設定。
