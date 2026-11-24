# ADR 決策與風險紀錄

狀態定義：`ACCEPTED` 已由產品需求/已知條件確認；`PROPOSED` 建議但尚需 Stage 1 審核；`OPEN` 需使用者或平台實測決定；`BLOCKED` 需要外部資源。禁止把 PROPOSED 視為功能已完成。

## 決策表
| ID | 狀態 | 決策/選項 | 為什麼 / 後續行動 |
|---|---|---|---|
| ADR-001 | ACCEPTED | Flutter 支援目標為 Android、iOS、macOS、Web | 使用者要求。Web 依 ADR-031 和 WP-17 驗收。 |
| ADR-002 | ACCEPTED | M4A/MP3 優先，雙語 SRT 逐句精聽 | 使用者要求 |
| ADR-003 | ACCEPTED | 同 App 帳號跨平台同步教材、字幕與進度 | 使用者要求 |
| ADR-004 | ACCEPTED | Mac iCloud 使用者自選資料夾，播放清單綁定 | 使用者要求 |
| ADR-005 | PROPOSED | Firebase Auth / Firestore / Storage 保留為候選 | macOS Core 與本機 Firestore／Storage 傳輸通過，Auth 卡在 Keychain entitlement。正式環境受 ADR-010／011／018 阻擋 |
| ADR-006 | ACCEPTED | 使用 Riverpod、Drift 與 just_audio 作既有架構基線；套件版本由 ADR-034 更新 | 目前解析為 Riverpod 3.5.0、Drift 2.35.4、just_audio 0.10.6；依賴版本與平台 build 證據見 ADR-034；單頁暫緩 go_router |
| ADR-007 | ACCEPTED | macOS 自選來源採唯讀授權 | grant 留在裝置，原始檔不經 app 寫入；sandbox 實測留 WP-11 |
| ADR-008 | ACCEPTED | Mac 是 MVP 自動 iCloud 入口，iOS 直接 folder scan 延後 | 產品範圍 §4 與 folder 規格 §3 |
| ADR-009 | ACCEPTED | SQLite 原子寫入與 durable outbox；先驗證 blob 再發佈 metadata | 依同步規格與 Firestore 交易限制；重試與部分失敗規則見下方 |
| ADR-010 | ACCEPTED（登入方式）／OPEN（正式環境驗收） | Google 與 Apple 透過 Firebase Auth 登入；Email／Password 保留供測試 | 依 WP-14 [登入補件](agent/wp-14-social-sign-in.md) 驗收平台設定、Firebase UID 及實機登入 |
| ADR-011 | OPEN | Firebase 所有權、費率預算、最大單檔限制 | 不能擅自建立付費資源 |
| ADR-012 | ACCEPTED | 以 canonical revision 和 session sequence 判斷進度寫入；落後版本保留候選 | 純 Dart 時序已測；伺服器交易及規則由 WP-08／09／13 驗證 |
| ADR-013 | ACCEPTED | WP-10 使用 `audio_service` 0.18.19 將 AudioEngine 狀態與系統媒體控制橋接；macOS 支援範圍限官方列出的 Now Playing/Control Center，不宣稱鎖定畫面控制 | Android/iOS 使用原生背景媒體服務配置；Android 暫停時維持 foreground service 以符合 Android 12+ 背景限制；平台 build 已核驗，真機控制列 smoke 尚待具備裝置 |
| ADR-014 | OPEN | 登出時保留／移除快取的產品選項 | 強制 UID 隔離與暫停舊 UID outbox；實際保留期限與磁碟政策待定 |
| ADR-015 | OPEN | 音訊外再支援 MP4 的里程碑 | 使用者主要使用音訊，影片之後擴充 |
| ADR-016 | OPEN | SRT encoding fallback 與語言偵測套件 | UTF-8 優先；需平台與授權評估 |
| ADR-017 | ACCEPTED（本機工具鏈及最低平台版本）／OPEN（發佈簽章與商店驗收） | Flutter/Dart 與四平台最低版本 | 使用者接受 iOS 15、macOS 12、Android API 24；Flutter 3.50.1 / Dart 3.14.0、Gradle 9.5.0 / AGP 9.3.1 / Kotlin 2.4.20 已完成本機四平台 build。發佈簽章、商店與真機登入仍需各自驗收，詳見 ADR-034 |

| ADR-018 | ACCEPTED（本機原生相依）／OPEN（商店發布） | FlutterFire Apple 發佈的套件管理方式採 Flutter Swift Package Manager；iOS/macOS 不再整合 CocoaPods | Flutter 3.50.1 對目前 Apple plugins 產生 `FlutterGeneratedPluginSwiftPackage`；iOS Simulator、iOS device（未簽章）及 macOS build 均通過。已移除舊 Pods build phases、Podfile、lockfile 與 xcconfig 引用。商店簽章與發布另行驗收。依據：[Flutter Swift Package Manager for app developers](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers) |
| ADR-019 | OPEN | 媒體孤兒回收、跨裝置刪除保留期限 | 媒體回收與同步 tombstone retention 仍待 WP-08；書籤 cue 重定位已由 ADR-025 定義 |
| ADR-020 | ACCEPTED | WP-02 以 owner namespace 隔離本機 DB/媒體；媒體按 SHA-256 去重，教材只對相同來源鍵與內容雜湊冪等 | 保留不同來源的獨立 materialId；來源鍵不得含原始路徑。孤兒媒體回收沿用 ADR-019，待後續工作包處理 |
| ADR-021 | ACCEPTED | WP-03 SRT 配對以半開區間重疊判斷；有效重疊至少覆蓋較短 cue 的 25% | 依 T-SRT fixture 驗證多對一、一對多及邊界擦碰；保留門檻參數以便後續 fixture/產品決策調整 |
| ADR-022 | ACCEPTED | WP-04 透過 `AudioPlayerPort` 隔離 just_audio；audio_session 0.2.4 與 Android API 24 基線；iOS/Android 中斷暫停且不自動續播 | 使用者接受 Android API 24；Flutter 3.50.1 Android Debug APK 實際 build 通過。speech session 與事件依套件文件；loop 用原生 clip + LoopMode.one。真機精度仍待驗 |
| ADR-023 | ACCEPTED | WP-05 LearningSession 綁定一個教材；replay 保留揭露，換 cue 重設遮蔽；句循環由獨立命令控制 | 對應精聽狀態機；無翻譯仍允許揭露並提示；跨教材 snapshot 不得誤操作播放器。T-LEARN-01..05 自動測試 |
| ADR-024 | ACCEPTED | WP-06 一般字幕模式為 session 呈現狀態；字幕軌/offset 透過 repository 持久化 | 視窗測試證明切換不 Seek，播放進度保持；詳見 WP-06 handoff |
| ADR-025 | ACCEPTED | WP-07 本機書籤保存不可變 cue anchor snapshot；字幕變更依文字與時間重定位，無唯一匹配時保留未定位 | WP-07 SQLite v2→v3 migration、重開 DB、subtitle revision relocation、ambiguous 與 account isolation tests |
| ADR-026 | PROPOSED | WP-08 以 profile-scoped SQLite outbox + 注入式 Auth/Cloud transport；demo Firebase Emulator 驗證 Rules | 本機 transaction、fake transport 與三組 Emulator Rules 測試通過；FlutterFire 正式接線受 ADR-010/011/017/018 阻擋，SHA-256 read-back 成本未核定 |
| ADR-027 | ACCEPTED | WP-09 本機 canonical/checkpoint/conflict 與進度 outbox 落 SQLite；雲端交易僅經 ProgressSyncTransport；播放器只在開啟時恢復已確認位置 | SQLite v4→v5 migration、fake receipt/revision/sequence/衝突測試、Player Widget 測試；真實 Firestore transaction 與 Emulator 進度規則仍待 FlutterFire/雲端前置條件 |
| ADR-028 | ACCEPTED（本機及 App 分類同步設計） | WP-12 完整 scan + account-scoped playlist/source catalog；唯一缺席舊路徑與相同 SHA-256 才視為 rename；缺席不刪教材或收藏 | Drift v5→v6 migration、晚到 SRT、唯一/歧義 rename、掃描錯誤、來源移除與收藏保留測試；分類樹與教材管理使用 SQLite v9 及 UID 專屬 Firestore metadata，正式驗收待發布 |
| ADR-029 | ACCEPTED（本機驗收）／OPEN（遠端發佈） | WP-14 透過 Firebase REST 與 Callable 接入既有同步契約，採測試帳號及手動同步 | 兩個 Emulator 客戶端與 macOS Release 證據見 [WP-14 Firebase 交棒](agent/wp-14-firebase-handoff.md)。正式 Auth、用量及發佈仍依 ADR-010／011／014／017／018 追蹤 |
| ADR-031 | ACCEPTED（平台與方向）／OPEN（相容性、發布） | Web 為第四個正式支援平台，採 Drift WasmDatabase、瀏覽器私有儲存與 Google Web OAuth | 設立 WP-17。瀏覽器矩陣、部署選項與實際登入／同步由 T-WEB-01..06 驗收。 |
| ADR-032 | ACCEPTED（bucket 與 UID 隔離）／OPEN（刪除參照清理、費用上限） | 專案 `english-learning-player-auth` 使用 `english-learning-player-auth.firebasestorage.app`（`us-east1`）；owner 可管理自身 assets/subtitles | Blaze 已由使用者連結。bucket 區域建立後不能變更。內容地址物件更新需保持 bytes checksum 與應用身分 metadata；owner delete 可能留下 Firestore metadata 指向的失效物件，App 刪除/GC 尚未實作。費用上限仍待設定。 |
| ADR-033 | ACCEPTED（裝置同意與執行時同步） | Firebase 教材同步由每裝置、專案與 UID 分別同意，選擇寫入 SQLite v8 | 首次登入詢問，成功同意後消費本機音檔與字幕佇列。程式暫停或關閉後於下次開啟繼續。接收端自動更新雲端清單與晚到字幕。 |
| ADR-034 | ACCEPTED（本機升級與建置基線） | Flutter、Dart、相依套件及原生工具鏈升級 | 依使用者同意的 iOS 15 / macOS 12 / Android API 24，升級至 Flutter 3.50.1 / Dart 3.14.0；主要依賴解析為 Riverpod 3.5.0、Drift 2.35.4、just_audio 0.10.6、audio_session 0.2.4、sqlite3 3.9.2。移除已 EOL 的 `sqlite3_flutter_libs`，改用 sqlite3 3.x 原生 assets。Android 對齊 Flutter 3.50 官方 Gradle 9.5.0 / AGP 9.3.1 / Kotlin 2.4.20 模板。`pub outdated` 顯示所有直接 runtime 依賴為最新可解析版本；測試套件及四個受相依約束的 transitives 尚有更新版本但目前不可解析。Analyze、194 tests（3 項 Emulator tests skipped）及 Android/iOS/macOS/Web build 通過。實機 `flutter run` 已自動簽章、安裝且 Runner process 存活，但 Flutter debugger attach 因 `Error executing osascript: -2` 未完成；Google 登入未測。未變更 Firebase 雲端資源。依據：[Flutter 3.50 release notes](https://docs.flutter.dev/release/release-notes/release-notes-3.50.0)、[Flutter supported platforms](https://docs.flutter.dev/reference/supported-platforms)、[Flutter built-in Kotlin migration](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers)、[sqlite3 3.0 upgrade notes](https://pub.dev/packages/sqlite3/changelog)、[sqlite3_flutter_libs package status](https://pub.dev/documentation/sqlite3_flutter_libs/latest/sqlite3_flutter_libs/)。 |
| ADR-035 | ACCEPTED（實作契約）／OPEN（Firebase Console 與正式部署） | `kuroneko_li` 唯讀登入沿用既有 Google Firebase UID；密碼 Provider 依 token email/provider 在 Firestore、Storage 與進度 Callable 強制唯讀 | Firebase 不提供 username 欄位，內部 alias 為 `kuroneko_li@english-learning-player-auth.firebaseapp.com`。以 Google 登入原帳號後連結 Email/Password 憑證，兩種方式取得同一 UID；只有 alias + `sign_in_provider=password` 被視為唯讀。此裝置使用獨立 Drift profile namespace，避免唯讀端 outbox 混入 Google writer profile。Rules、Callable 與 Firebase Console 未部署／設定，正式權限仍未生效。交棒與步驟見 [WP-18 交棒](agent/wp-18-readonly-account-handoff.md)。 |

## Stage 1 決策細節（2026-11-10）

### ADR-005／006／010／011／017／018 — 版本與雲端閘門

- Riverpod 以 exact pin 與 lockfile 隨 bootstrap 交付。Drift、just_audio、FlutterFire 只在獨立 Spike 解析；個別模組在接線時再加入依賴。單頁先用 MaterialApp。版本、授權、實測與重跑步驟見 [WP-00／01 交棒](agent/wp-00-01-handoff.md)。
- Firebase Auth／Firestore／Storage 的 macOS 支援表列為 beta。正式 Storage 要 Blaze；即使有免費配額也須先核准專案、預算、單檔上限及區域。驗證先用本機 Emulator 與合成資料。本機 Auth Emulator 匿名登入在目前 debug app 的 Keychain 保存失敗（`SecItemAdd -34018`）。登入方式、具 Keychain Sharing 的有效簽章與帳號切換仍待驗。依據：[FlutterFire 平台表](https://firebase.google.com/docs/flutter/setup)、[Storage 計費要求](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024)。
- CocoaPods Spike 的 FlutterFire core 5.1.0 固定 Apple SDK 12.19.3。官方已在 2026 年 10 月停止以 CocoaPods 發佈新 Firebase 版本。正式方案需驗證 Flutter 3.32.2 的 SwiftPM 整合及三平台最低 OS；若須升級，另審 SDK、原生目標與回歸範圍。[Apple SDK 套件管理遷移](https://firebase.google.com/docs/ios/cocoapods-deprecation)。
- 後續依使用者核准升至 Flutter 3.50.1，生成的 iOS/macOS Swift package manifests 列出本機 Apple plugin dependencies；兩平台都以 SwiftPM build 通過。因此只移除 CocoaPods project integration，不改套件或最低部署版本。iOS custom AppDelegate 改用 `FlutterImplicitEngineDelegate` 並在 `Info.plist` 宣告 `FlutterSceneDelegate`，符合 Flutter 3.41+ UIScene 啟動流程；Simulator/device build 均通過。依據：[Flutter UIScene adoption](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate)、[SwiftPM 移除 CocoaPods 步驟](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers)。

### ADR-010 — Google／Apple 登入補件

- 依使用者指示採用 Google 與 Apple 作為 Firebase Auth 登入方式。Firebase UID 維持本機與雲端帳號邊界。App 依 Firebase 回傳的 UID 開啟教材庫；以 Email 合併本機資料或新增帳號連結入口需另行決策。
- Google 與 Apple 原生 Apple 平台維持 REST 憑據交換，Apple 使用隨機 nonce。Android Apple 採 Firebase SDK OAuth，由建置選項開啟，該建置最低 API 23。Google 外掛將 macOS 最低版本調至 10.15。平台配置與實機驗收見 [登入補件](agent/wp-14-social-sign-in.md)。

### ADR-007／008 — Mac 資料夾權限

- 透過使用者選擇的目錄建立 app-scoped、唯讀 bookmark。bookmark bytes、絕對來源路徑及 scan cursor 限於授權裝置與本機使用者範圍。同步資料只含 binding/playlist ID、來源類型與標籤。每次成功的 scope access 成對釋放，watch 取消、disconnect 或登出時結束 session。stale 嘗試安全更新，更新失敗要求重選。
- 原生端協調讀取並檢查解析後 URL 仍位於已授權根目錄，拒絕絕對路徑、穿越與越界 symlink。只將可讀且完整的檔案複製到 app staging，再由匯入層接手。待下載列為存在。掃描失敗不得推導來源缺失，完整掃描發現缺檔只標記來源狀態。watch 事件只觸發重掃。
- WP-11 驗證 sandboxed build 的 user-selected read-only 與 app-scope bookmark 能力、重啟還原、撤銷、移動及 placeholder。直接讀取 iCloud 私有系統路徑會越過使用者選擇的範圍。依據：[Apple App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)、[Security-scoped URL 存取](https://developer.apple.com/documentation/foundation/url/startaccessingsecurityscopedresource())、[資料夾規格](07-icloud-folder-sync.md)。
- WP-11 原生 adapter 以 MethodChannel + EventChannel 實作；bookmark bytes 留在 UserDefaults app container，FSEvents 只發 invalidation，完整 inventory 由 NSFileCoordinator metadata-only scan 產生。stageFile 會拒絕路徑穿越/symlink，且只複製已下載的檔案到 app staging。官方 API 要求對 security-scoped URL 成對 start/stop access；metadata 掃描使用 immediately-available metadata-only 選項；bookmark stale 時嘗試安全 renew。[Apple URL/security scope](https://developer.apple.com/documentation/foundation/nsurl/)、[Bookmark resolving](https://developer.apple.com/documentation/foundation/url/init%28resolvingbookmarkdata%3Aoptions%3Arelativeto%3Abookmarkdataisstale%3A%29-3ic6f)、[NSFileCoordinator metadata option](https://developer.apple.com/documentation/foundation/nsfilecoordinator/readingoptions)、[FSEvents lifecycle](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html)。
- 證據：`flutter analyze` 與全量 103 tests PASS；iOS Simulator、Android APK、macOS Release builds PASS。`codesign -d --entitlements :-` 顯示 `com.apple.security.app-sandbox=true` 與 `com.apple.security.files.user-selected.read-only=true`。Flutter T-FOLDER-01..10 覆蓋取消、錯誤映射、部分下載、掃描 invalidation、解除及 panel UI。sandboxed Release app 的 Open Panel 已實際開啟並取消，未授權資料夾；首次 launch 狀態在修正後已實際確認顯示未連線。真實 bookmark 重啟恢復、撤銷/搬移、iCloud placeholder 與分發簽章仍 BLOCKED，需專用授權測試資料夾與 Developer ID 簽章前置條件。

### ADR-009／014／019 — 重送、媒體與帳號隔離

- 本機業務資料與 outbox 同一交易。每筆送出前以本機交易取得 lease；持久化 immutable `opId`、payload/hash、attempts、retry deadline 與可辨識錯誤類型。重啟可回收過期 lease。一次一個 owner/entity 的 in-flight 寫入，僅合併還未取得 lease 且從未送出的連續 checkpoint。伺服器已提交但本地未收到回覆時以原 opId 重送並讀取原結果。任何不同 payload 重用 opId 應回傳完整性錯誤。
- 初版重試策略以實際暫時失敗次數 n 計算延遲，從 `[cap/2, cap]` 取 jitter，`cap = min(60 s, 2^(n−1) s)`。限流指示可延後下次嘗試。離線暫停派送，等待復線再評估 deadline。暫時錯誤達 8 次進入待處理，使用者重試保留 opId 並重置重試計數。認證失效停至同 UID 恢復。拒絕存取、無效 payload、永久完整性問題進入待處理，需修復原因後重試。60 秒上限與 8 次門檻是 Stage 1 初始值，WP-08 以可注入 clock/RNG 驗證。暫時性錯誤、冪等性與退避依據 [Cloud Storage retry strategy](https://docs.cloud.google.com/storage/docs/retry-strategy)。
- 資產在同 UID 內按內容雜湊去重，遠端以穩定 assetId/object key 辨識；先確認遠端資產大小、類型與 SHA-256，再以交易發佈 ready metadata。物件已上傳而 metadata 失敗時重送同一操作並重新核對，下載驗證 hash 後才以原子移動發布本機檔。WP-08 驗證可落地的完整性檢查與 rules，不能只信任客戶端宣告的 hash。可下載狀態以服務端確認為準。
- App 以本機 profile/UID namespace 隔離 DB、媒體、provider scope、watcher 與 outbox。登出立即停用其讀取和傳輸，清除記憶體狀態，傳輸回覆須校驗當前帳號世代。離線 profile 以獨立 namespace 運作；匯入另一帳號須明確選擇。既有資料留在原 namespace，清理策略仍待定。理由是 [同步規格](06-cloud-sync.md) 的離線需求與 [Firestore 交易](https://firebase.google.com/docs/firestore/manage-data/transactions) 無法離線執行。

### ADR-020 — WP-02 本機匯入冪等與資產去重

- 每個 `AccountScope` 以 SHA-256(ownerId UTF-8) 產生路徑 namespace；資料庫仍保存原 ownerId 並以 owner 條件查詢。SQLite 資料表以 owner 複合主鍵／外鍵防止跨 owner 關聯；目前每個 owner 使用獨立 DB 檔和 app support 媒體目錄。
- 匯入來源鍵為選取來源路徑的 SHA-256，不保存原始來源路徑。相同 owner、來源鍵與檔案 SHA-256 再匯入時回傳既有教材；同 owner 相同 SHA-256 的二進位內容共用一筆 `media_assets` 與一個內容定址檔案。不同來源即使內容相同仍建立獨立 `materialId`，符合 [materialId 不等於檔案 hash 的契約](02-domain-models.md)，避免自動合併使用者的學習身分。
- 檔案先複製到 app support 暫存檔、串流計算 SHA-256，檢查非空及既有內容完整性後以 rename 發佈，再以 SQLite transaction 建立 asset/material/source 關聯。程序在檔案發佈後、資料庫提交前中止可能留下未引用檔案；回收延後至 ADR-019 所列清理工作，不在 WP-02 刪除未知引用狀態的檔案。
- macOS 手動選檔採 file selector 使用者明確選取的單次讀取；唯讀 entitlement 不代表持久 iCloud 資料夾授權或監看能力。bookmark、長期授權和資料夾掃描維持 ADR-007／WP-11 邊界。
- 驗證證據：`test/features/library/audio_import_test.dart` 覆蓋重開 DB、同來源重匯、跨來源同內容、跨帳號隔離、空／不支援檔案與來源串流中斷；三平台建置結果以本 WP 驗收摘要為準。

### ADR-021 — WP-03 字幕重疊匹配門檻

- 對齊使用音訊時間軸上的半開區間。不同 track 的 `offsetMs` 先套用，cue 序號不參與對應。只有重疊長度佔較短 cue 時長至少 25% 才建立關係；匹配結果按重疊毫秒降冪並穩定排序。相同中文 cue 可以連到多個英文 cue，單一英文 cue 也可以連到多個中文 cue。
- 選 25% 是 WP-03 的明確預設值：可剔除短暫邊界擦碰，同時讓跨句／合併字幕由較短一側完整覆蓋時成立。門檻在 `SubtitleAligner` 可設定；若真實教材 fixtures 顯示誤配，應在回歸測試中校正而非按序號 fallback。
- Unicode 檔名比較用 NFC；依賴 `unorm_dart 0.3.3`，pub.dev 列出 Dart/Flutter 及 Android/iOS/macOS 平台與 MIT license：[套件來源](https://pub.dev/packages/unorm_dart)。套件未引入 platform plugin。
- 驗證證據：`test/features/subtitles/subtitle_engine_test.dart` 測試兩英句對一中句、一英句對多中句、offset、重疊、相似 stem、歧義及 10,000 cue 定位；`subtitle_repository_test.dart` 驗證 manual 保護及 schema v1 升級。具體結果見 WP-03 handoff。

### ADR-022 — WP-04 AudioEngine 與中斷政策

- `AudioEngine` 維持 Stage 1 公開契約，adapter 僅透過注入式 `AudioPlayerPort` 使用 plugin。這讓 T-AUDIO 測試不載入原生 plugin，並保留後續平台替換邊界。播放器依賴固定為 `just_audio 0.10.6`、`audio_session 0.1.25`；0.1.25 符合 just_audio 相依範圍並保留 minSdk 21。官方套件文件列出平台支援與 clip/LoopMode API。[just_audio 0.10.6](https://pub.dev/packages/just_audio/versions/0.10.6)、[audio_session changelog](https://pub.dev/packages/audio_session/changelog)
- iOS/Android session 配置為 speech；中斷開始（含 duck）及耳機拔除都暫停，結束事件不自動恢復。選此策略是因精聽播放不應在系統中斷結束後未經使用者操作突然續播。macOS 中斷、背景與媒體鍵不由本 ADR 宣稱支援，交 WP-10 實測。
- 句循環用原生 clip + `LoopMode.one`，開啟/清除 loop 時恢復原本播放狀態；超出 loop 的 seek 與載入新音源會清除 clip。測試使用假 port 驗證命令順序與快照，不證明原生解碼器 ≤150ms 的邊界精度。真機裝置、三類媒體來源與誤差量測仍為 WP-10/WP-15 的必要驗證。
- 證據：套件版本由 `pubspec.lock` 固定。首輪 Android build 證實 audio_session 0.2.4 因 manifest minSdk 24 與專案 minSdk 21 衝突；改用 Android Gradle minSdk 19 的 0.1.25 後，三平台 debug build 均通過。官方 changelog 記錄 Android minSdk 變更，just_audio 0.10.6 支援此 audio_session 相依範圍。`test/features/audio/just_audio_adapter_test.dart` 覆蓋 T-AUDIO-01..08、競態、取消、中斷及快照。詳見 [WP-04 交棒](agent/wp-04-handoff.md)。

### ADR-023 — WP-05 LearningSession 狀態與 cue 操作

- `LearningSession` 綁定 owner/material 一致的英文軌、可選中文軌及其 AudioEngine；若 AudioEngine 切到不同 material，session 清空目前 cue 並拒絕 replay/loop/next/playCue。這避免播放器切換後舊字幕命令作用到新教材。
- 精聽揭露只允許 blind → English → bilingual。replay 不改 reveal phase；選取不同 cue 或 next cue 在 intensive 模式回到 blind，並清除不相符的現存 loop。句循環使用獨立 `setCueLoopEnabled` 命令；無中文 cue 時可進入 bilingualShown 並讓 View 顯示「未提供翻譯」，cue 空檔則不顯示此提示。
- cue 起點/終點採 `SubtitleSynchronizer` 的 positive offset 顯示延遲方向，換成音訊位置後 clamp 至媒體 duration；Original SRT cue 保持不變。對齊仍由 WP-03 `SubtitleAligner` 負責，不在本 WP 修改字幕契約。
- 證據：`test/features/learning/learning_session_test.dart` 覆蓋 T-LEARN-01..05、reveal 順序、缺失翻譯、換句重設、loop/replay、offset、播放 snapshot 與教材隔離；詳見 [WP-05 交棒](agent/wp-05-handoff.md)。

### ADR-025 — WP-07 書籤錨點與字幕修訂重定位

- 書籤保存 owner/material、track ID/revision、language tag、cue ID、原始 cue text 及套用字幕 offset 後的半開音訊時間區間。字幕重匯時保留原 anchor，不刪除、不以 cue 序號當定位條件。
- 重新定位先檢查同一 track ID、revision 與 cue ID。若版本已變，限制在目前已選且語言 family 相同的 track，先比較小寫、合併 whitespace 後的 cue text，再以 anchor/audio interval overlap 及中心距離排序。文字變動時只接受至少覆蓋較短 interval 50% 的時間重疊候選。
- 只有唯一最佳候選才能播放。最佳候選 overlap 與中心距離同分則標 ambiguous；找不到則標 missing。兩者都保留 bookmark 和原始 anchor，Favorites 不自動 seek，使用者可移除。此策略以避免錯播優先於猜測；修訂內容大幅改時且同時改寫文字可能需要使用者手動處理。
- 本機刪除只寫 `deleted_at_ms` tombstone；雲端 outbox、墓碑 retention/sweep 留待 WP-08，故本機收藏不因字幕更新或未定位而被刪除。
- 證據：`test/features/bookmarks/bookmark_repository_test.dart` 驗證 v2→v3 migration、DB 重開後保留並重定位到新 cue ID、account namespace 與 ambiguous/missing；Player widget tests 驗證收藏切換及 Favorites 從新 cue 開始播放。細節見 WP-07 handoff。

### ADR-026 — WP-08 outbox 與 Firebase Emulator 邊界
狀態：PROPOSED（Stage 2 可測實作；正式雲端接線未核准）

- WP-02 的 `materials.status` 僅允許 `localReady`，不重建既有表。schema v4 新增 `material_sync_state` 作 UI 狀態 overlay，以及 `(owner_id, op_id)` 唯一的 `sync_outbox`。匯入教材與 outbox、sync state 在同一 SQLite transaction 建立；v1/v2/v3 舊教材升級時也建立待同步操作。
- outbox payload 是版本化 canonical material metadata；其中只含教材/資產 ID、標題、SHA-256、位元組數及 MIME。App 私有相對路徑、授權 bookmark、原始路徑、登入 token、字幕全文不進雲端 payload 或日誌。asset object key 固定為 `users/{uid}/assets/{assetId}/{sha256}`，Firestore 路徑以 UID namespace 隔離。
- 新匯入只排入本地佇列；派送前必須同時存在相符 Auth UID 與明確的 `SyncConsentProvider` 同步授權。授權未開啟時保持 localReady/outbox pending，不上傳。
- `CloudSyncCoordinator` 僅接受 Auth UID 與 `AccountScope.ownerId` 完全相同的 session；上傳及每次 await 後重驗身分，帳號切換即暫停原 UID 操作。只有 Storage 回報的 SHA-256、大小、MIME 與預期 key 一致，且 asset/material metadata 發佈成功後才完成 outbox 並呈現 `cloudReady`。部分成功重送原 opId；暫時錯誤依 ADR-009 退避並於第 8 次進入待處理；同 UID 重新登入可續送，權限/資料錯誤須人工修復後以同一 opId 手動重試。
- Firebase Rules 的媒體上限暫設 100 MiB，以限制 emulator 測試及可接受的媒體大小；此數值**不是產品上限核准**。ADR-011 的費率、區域與最大教材尺寸仍 OPEN，正式發布前須選定限制與成本政策。Rules 限制 owner、欄位 allowlist、音訊 MIME、path/UID 關聯、媒體 size 與不可公開存取；Rules 不驗證實際內容 SHA-256。
- Storage object 建立後不可覆寫。冪等 adapter 重送時先讀取既有 object，核對 UID path、大小、MIME 及實際位元 SHA-256；完全一致才可回傳既有 receipt，否則回 integrity error。這避免相同 assetId/key 被不同位元替換。
- 雲端 SHA-256 的「遠端驗證」必須由 transport 讀回物件並重算、或由經核准的可信後端計算。單靠 client metadata/custom metadata 是聲明值，不能作完整性證明；讀回會增加流量與費用。WP-08 只定義並以 Fake transport 驗證收據契約，尚未完成 FlutterFire adapter，因此不宣稱真實 Firebase Storage 上傳具 SHA-256 read-back 驗證。
- 本地 Node Rules tests 使用 `demo-english-learning-player`，透過 `firebase emulators:exec --only auth,firestore,storage` 執行合成資料；demo ID 使未模擬雲端服務呼叫失敗。這些測試不建立 Firebase 專案、不觸發計費，也不驗證 FlutterFire 原生登入。Auth provider、UID/profile mapping、macOS Keychain entitlement、Apple SDK 套件管理及部署最低 OS 沿用 ADR-005/010/017/018 未決狀態。
- 依據：[Firebase Emulator demo project](https://firebase.google.com/docs/emulator-suite/connect_firestore)、[Firestore Rules Emulator testing](https://firebase.google.com/docs/firestore/security/test-rules-emulator)、[Cloud Storage pricing transition](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024)。
- 證據：`test/core/sync/cloud_sync_coordinator_test.dart` 覆蓋成功、重送、認證暫停、UID 切換、權限拒絕、損壞媒體、8 次退避及重試；`test/firebase/rules.test.cjs` 在 Firestore/Storage Emulator 覆蓋 owner allow、anonymous/cross-UID/錯欄位 deny。見 [WP-08 交棒](agent/wp-08-handoff.md)。

### ADR-012 — 進度衝突與回復

1. 每個 `(UID, materialId)` 有 canonical revision，無紀錄為 0。每次播放工作階段建立 sessionId；sequence 依 `(UID, materialId, deviceId, sessionId)` 單調遞增。每筆 checkpoint 帶有當時確認的 `baseRevision`。
2. 提交時先讀 opId receipt，重送回傳既有結果。交易內讀取該 session 的 sequence high-water 與 canonical。sequence 已見過或較舊就忽略。baseRevision 等於 canonical 才接受並遞增 revision。否則保留該 session 最新候選及原 baseRevision。交易同時寫入結果 receipt、高水位與適用的 canonical／候選，避免併發與回覆遺失造成重複效果。
3. 離線 checkpoint 留在本機，候選確認後 outbox 可完成，候選仍可供使用者選擇。若使用者選定候選或保留目前位置，用畫面當時的 canonical revision 和候選識別提交明確的解決操作，交易檢查兩者仍有效後更新 canonical 並標記已解決的候選。任一版本已改變則重新呈現，保留其他候選。後續本機 checkpoint 可以承接同 session 自己剛確認的寫入；只可在產生新未送出操作時使用該 revision，不能借用別台裝置的新版本覆蓋衝突。
4. 裝置時鐘與播放位置大小都不能決定勝負，倒帶也能合法接受。進度的 server timestamp 用於呈現，遠端更新只影響下次開啟／明確續播選擇。依據：[時序測試](../test/unit/progress_policy_test.dart)、[Firestore 交易隔離](https://firebase.google.com/docs/firestore/transaction-data-contention)。WP-09／13 尚需驗證 receipt 重送、兩裝置併發、切帳號與播放中的 Seek 隔離。

### ADR-013 — WP-10 系統媒體控制

- 以 `audio_service` 0.18.19 的 `AudioHandler` 作為 OS media session adapter；handler 命令只呼叫現有 `AudioEngine`，不另建播放器或讓 UI 直接呼叫平台 plugin。教材 metadata 由 Player ViewModel 在成功載入後發布，handler 訂閱 engine snapshot 更新 playback state。
- `audio_service` 官方支援矩陣列出 Android、iOS、macOS；macOS 有 Now Playing / Control Center 媒體控制能力，沒有 Lock Screen control。選用直接 `audio_service` 是因其官方文件定位為可擴充的 background audio service；`just_audio_background` 文件將自身定位為較簡單的單播放器封裝，並建議需要更多服務控制時直接使用 `audio_service`。依據：[audio_service 支援矩陣](https://pub.dev/packages/audio_service)、[audio_service API](https://pub.dev/documentation/audio_service/latest/index.html)、[just_audio_background 文件](https://pub.dev/packages/just_audio_background)。
- 已在本專案 Flutter 3.32.2 / Dart 3.8.1 上由 `flutter pub get` 實際解析 `audio_service` 0.18.19；Dart handler 與 metadata/state 測試通過。Android Manifest 設定 media playback foreground service 與 media button receiver，iOS 設定 `UIBackgroundModes=audio`；不得推論這些 build 結果等同真機鎖屏/耳機 smoke。
- Android 設定 `androidStopForegroundOnPause: false` 以保持 Android 12+ 背景服務可恢復；`androidNotificationOngoing` 必須為 false。暫停時 OS 通知/foreground service 可能持續存在，使用者可透過 Stop 結束。此行為是 Android resume 相容性與通知持續時間的明確取捨。
- 啟動時若平台 service 初始化失敗，保留前景本機播放並使用 no-op media session；不得因此阻擋播放。macOS 只承諾官方列出的媒體中心控制能力，尚無 Mac 實機媒體鍵/背景實測。Android/iOS 真機 smoke 需在接上/準備測試裝置後補做。
- 證據：`test/features/audio/english_audio_handler_test.dart` 驗證系統 pause/seek/stop/speed 命令經 `AudioEngine` 執行及狀態/metadata 發布；Player widget tests 覆蓋教材載入後發布 metadata。`flutter analyze`、93 個 Flutter tests、iOS Simulator/macOS/Android APK build 均通過。Android/iOS 實際背景播放控制未測；Android build 有現用 NDK 26.3 與 plugin 建議 NDK 27.0 的 warning，但 APK 成功產出且本 WP 未更動 NDK。詳見 [WP-10 交棒](agent/wp-10-handoff.md)。

### ADR-027 — WP-09 進度持久化與播放器邊界
狀態：ACCEPTED（本機與 adapter 契約）；OPEN（正式 Firebase transaction）

- Drift schema 升至 v5，`playback_progress` 保存 owner/material 的本機 canonical；`progress_stream_state` 保存 device/session 下次 sequence 與該 session 自己確認的 revision；`progress_conflicts` 保存尚未解決候選；`progress_device_identity` 保存 profile-scoped 安裝 ID。新增表均帶 owner/material 外鍵，v4→v5 不修改教材或既有 material outbox。
- 進度操作共用 `sync_outbox` 冪等欄位，但以 `entity_type='progress'` 和 `writeProgress`／`resolveProgress` operation 分類。舊 WP-08 `SqliteSyncOutbox.claimNext` 明確只領取 `material`，避免進度 payload 進入媒體上傳 coordinator。payload 是版本化 JSON，保存 owner/material/device/session、position/state/sequence/baseRevision；媒體路徑不在進度文件。
- PlayerViewModel 將 AudioEngine snapshot 轉成純 Dart recorder 事件：本機週期 checkpoint 為 15 秒，並在 pause、seek 完成、教材切換與 ViewModel dispose 記錄。每次播放器開啟建立新 session；device ID 在 profile DB 持久化。正常開啟使用已合併的本機 canonical 位置；`initialCueId` 明確導航優先。遠端 snapshot merge 只改 repository，沒有播放器 seek callback，因此活動播放不會被遠端進度跳轉。
- 衝突候選選擇先原子建立 immutable `resolveProgress` outbox，payload 帶 `candidateId`、觀察到的 canonical revision 與選擇；本機 canonical/candidate 只有收到交易成功後才更新。過期 revision 的交易回覆須回傳當下 canonical 並保留候選，UI 重新載入後再選。舊的同 opId receipt 必須回傳同結果；相同 opId 不可用不同 hash。
- 本 WP 的 `ProgressSyncTransport` 是正式交易 adapter 契約；測試 fake 模擬 receipt、session high-water、revision 和 candidate 規則，不代表 Firebase 驗證。FlutterFire 正式 Apple/Core 設定仍受 ADR-005/010/011/017/018 阻擋，故真實 Firestore transactions、Rules 和兩實機競態列 BLOCKED，交由 WP-13/14 完成。
- WP-13 在 consent 檢查後、恢復佇列後、claim 後及套用 ack 前重新核對目前 UID。切帳號時已 claim 的操作進 `waitingForAuth`，保留 opId；同 UID 恢復後重送相同操作，由 receipt 避免重複效果。這是 client coordinator guard，不取代 transport 對已登入 UID 的綁定，也不證明遠端交易。
- 證據：`test/features/progress/progress_sync_test.dart` 覆蓋兩個獨立離線 profile 同 UID 交錯寫入、consent 中帳號切換不派送、提交後切帳號延後本機 ack 並以同 opId 回放、權限拒絕不重試。真實 Auth listener race、Firestore receipt、Rules 與雙實機仍 BLOCKED。
- 重試沿用 ADR-009 的 1 秒起始、指數 cap 60 秒及 `[cap/2, cap]` jitter；8 次暫時錯誤後 `needsAttention`，同 opId 重試。無同 UID 身分時等待認證；同步未同意時不 claim/outbox 不變。權限錯誤進 `needsAttention`。
- 驗證：`test/features/progress/progress_sync_test.dart` 覆蓋 11 項 local/fake transaction 邊界；`test/features/player/player_page_test.dart` 覆蓋 canonical resume 與 cue seek checkpoint。正式跨裝置交錯與 Firestore atomicity 尚無實際服務證據。

### ADR-028 — WP-12 資料夾重整與本機清單
狀態：ACCEPTED（本機重整及 App 分類同步設計）。正式部署與真機收送待驗。

- `FolderAccessGateway.scan` 必須成功回傳完整 inventory 後，才把已知來源標為本輪缺席；scan 失敗不變更來源存在狀態。pendingDownload 代表存在。只有成功 staging 的音訊會建立新 material；來源檔案唯讀，私有 media copy 與 WP-02 source hash/outbox 路徑重用。
- 每個 account DB 保存 `playlists`、`playlist_entries` 與 `folder_source_entries`。相對來源路徑只限本機帳號資料庫，不進同步 payload。缺席只更新本機來源目錄，不刪教材、playlist entry、bookmark 或 progress。
- rename 的可測判定是同 binding 下，唯一缺席的舊來源具有相同 SHA-256；命中時新路徑沿用舊 materialId。若候選不唯一則保留新教材，遵守 ADR-020 的不同來源不得自動合併。這不保證識別內容改變的 rename；檔案資源識別子尚未由 `FolderEntry` 提供。
- subtitle 每輪使用 WP-03 `SubtitleFilenameMatcher`。歧義不自動匯入；已選 manual track 的 sourceName 優先；late subtitle 在之後完整掃描時匯入。相同來源名及原始 bytes 的 track 不重複建立。
- Schema v6 新表只加本機清單/來源目錄，v5→v6 不改舊教材/收藏；migration 測試建立含舊 material 的 v5 情境後升級確認資料仍在。
- WP-12 初版的 `SqliteSyncOutbox.claimNext` 只派送 `entity_type='material'`，`CloudSyncCoordinator` 也只發布 material/asset；因此 playlist 和 folder binding 的 remote metadata 尚未送出。WP-12 不建立未被 transport 消費的孤兒 outbox 操作，也未連雲端/付費服務。App 分類的後續補件見下方。
- 使用者已指定將遠端 playlist/folder metadata 記為後續整合項；該項不屬於 WP-13 的進度衝突/帳號隔離範圍。後續整合須先核准 metadata schema、Rules 與 transport，並保持本機 source path/bookmark 不外送。
- 目前延伸實作採用 SQLite v9 持久化待送異動，以及 Firestore UID 專屬欄位文件。使用者已要求同帳號同步 App 分類樹。衝突、刪除與發佈順序見 [同步規格第 8 節](06-cloud-sync.md#8-教材分類名稱與刪除同步)。
- 證據：`test/features/library/folder_import_reconciler_test.dart` 覆蓋 late SRT/重開 DB、playlist 與 material outbox、唯一 rename/刪來源保留收藏、歧義 rename 不合併、scan failure 保留狀態、pending download、v5→v6 migration。日期：2026-11-17。

### ADR-024 — WP-06 播放器 UI 狀態與資料存取邊界
狀態：ACCEPTED（WP-06 實作選擇）

- 一般字幕可見模式屬於單次 Player session 的呈現狀態，不寫入教材或跨裝置同步。使用者選取的字幕軌與 offset 是教材設定，沿用 WP-03 `MaterialRepository.saveSubtitleTrack` 持久化，並尊重 manual track 保護。
- `PlayerViewModel` 透過 `MaterialPlaybackLoader` 取出帳號範圍內教材的私有媒體副本與字幕，再呼叫 `AudioEngine` / `LearningSession`；UI 不直接操作資料庫、檔案或 just_audio。播放器準備失敗需呈現可重試錯誤。
- 變更字幕顯示不 seek；變更字幕軌只重建 LearningSession、不重載媒體，確保播放位置不被字幕設定重置。這保持 View → ViewModel → Repository / Service 邊界，也避免 UI 狀態進入 WP-09 跨裝置進度同步。
- 證據：`test/features/player/player_page_test.dart` 驗證點句只呼叫一次 cue replay、字幕可見模式切換保留 1800ms 播放位置，並在 320×700、1280×720、1.8 倍字體下無 Widget layout exception；`test/features/player/material_playback_service_test.dart` 驗證帳號限定的媒體解析與私有檔案載入。具體執行結果見 WP-06 handoff。
- 影響工作包：WP-06；沒有新增 schema 或 migration。未包含字幕目錄即時監看、播放進度持久化與跨裝置偏好同步。

### ADR-029 — WP-14 Firebase 同步接線

- 以 Firebase REST／Callable 串接 `SyncIdentityProvider`、`CloudSyncTransport` 與 `ProgressSyncTransport`，沿用目前 Flutter SDK、原生最低版本、SQLite schema 與 outbox。進度寫入由經驗證 UID 的 Callable 交易執行，Firestore 規則只允許客戶端讀取自己的 canonical。
- Email/Password 用於既有測試帳號。憑據與同步同意只存在記憶體。重開 App 會進入原離線帳號，Firebase 帳號需再次登入。App 目前以前景手動操作消費可重試佇列，網路恢復觸發、正式登入提供者與跨啟動身分保存仍待驗。
- macOS Release 實測登入、帳號隔離、下載與續播。demo Emulator 對相同 UID 驗證音訊與字幕原始資料、SHA-256、canonical 與衝突處理。遠端環境、簽章與 Gate C 仍需取得 [交棒所列條件](agent/wp-14-firebase-handoff.md)。

### ADR-030 — WP-16 字幕發布與持久化佇列

- 決定以選取字幕集合作為發布單位。字幕 Repository 在更新已選軌的 SQLite 交易內排入 `publishSubtitles`。工作儲存版本、教材 ID 與 payload hash，處理時從同 UID 的本機庫讀取當前軌道及原始 bytes。
- 沿用現有 `sync_outbox`。音檔先完成 `uploadMaterial`，字幕發布失敗仍保留音檔的 `cloudReady`。發布中的新選取另外排隊，同教材在有效 lease 期間只會有一筆字幕工作在處理。已選軌更新與 v6 → v7 補排都限本機來源教材，下載快取不發布。
- 佇列消費仍由既有的前景同步操作觸發。Firestore 路徑、manifest 格式、權限與 Storage SHA-256 驗證沿用 WP-16 已有契約。正式跨裝置與部署證據見 [WP-16 驗收紀錄](agent/wp-16-architecture-remediation.md)。

### ADR-031 — Web 第四平台

- 選用 Drift 官方 `WasmDatabase` 保持現有 SQLite schema、migration 與 Outbox。瀏覽器媒體由專用 adapter 保存，OPFS 優先，IndexedDB Blob 作為候選 fallback。帳號及 origin 隔離、配額、重新載入與多分頁行為須實測。依據：[Drift Web](https://drift.simonbinder.eu/platforms/web/)、[Storage Standard](https://storage.spec.whatwg.org/)。
- Google Web OAuth 採既有 Firebase 專案與 UID 契約，驗收 popup、redirect 需求和 HTTPS origin。COOP／COEP 的部署選擇須兼顧 Wasm 資料庫與 OAuth。現行方案、實作順序與證據門檻見 [WP-17](14-web-platform.md)。

### ADR-035 — Google writer 與 `kuroneko_li` password reader

- `kuroneko_li` 不是另一個 Firebase Auth 使用者；它是既有 Google Auth UID 上的 Email/Password 登入憑證。email alias 固定為 `kuroneko_li@english-learning-player-auth.firebaseapp.com`，避免把 username 當作 Firebase Auth 原生欄位。只有此 alias 且 token `firebase.sign_in_provider == password` 時才套唯讀規則；同一 UID 的 Google 登入仍可寫入。一般 Email/Password 測試使用者不因此降權。
- Firestore、Storage 規則同時保留讀取並拒絕該憑證的 create/update/delete。`syncProgress` Callable 亦依經驗證 token 拒絕寫入。客戶端唯讀狀態只控制 UI／outbox，不作為安全邊界。正式權限只有在 Firebase Rules 與 Functions 部署後才生效。
- Password 登入使用 `${username}@${project}.firebaseapp.com` Firebase email alias。Google owner 可由 App 連結 credential；成功後要求重新登入，確保後續 token 反映真正的登入 Provider。密碼由使用者在遮蔽欄位輸入，原對話內提供過的弱密碼不應重用；UI 要求至少 12 字元。Firebase Auth Console 的 Email/Password provider 必須先啟用。
- password reader 以 `${uid}:password-reader` 作為本機 `AccountScope`，但 `cloudUid` 仍為同一 Firebase UID。可讀教材／字幕／遠端進度並下載到本機 reader DB；讀取的遠端進度改以 reader scope 保存。其 outbox、學習紀錄與本機變更不會併入 Google writer scope。退出後仍須先以 Emulator Rules／Functions 驗證，才可部署。
- 證據：Firebase 官方 REST 文件提供以已登入 ID token 將 Email/Password 連結至目前使用者的 `accounts:update`；Security Rules 可讀取 `firebase.sign_in_provider`；Admin/Rules 文件說明權限必須由服務端規則執行。FlutterUI 官方套件有預建 Email UI，但本專案原生 Auth 使用 REST、Web 使用現有 JS SDK，故沿用既有 Adapter 並提供專用 username 表單，避免引入第二套 Auth 狀態管理。[REST linking](https://firebase.google.com/docs/reference/rest/auth/)、[Auth token fields](https://firebase.google.com/docs/rules/rules-and-auth)、[FirebaseUI Flutter](https://pub.dev/packages/firebase_ui_auth)。
- 正式前置條件：在 `english-learning-player-auth` Firebase Console 啟用 Email/Password；以 Google 登入原 UID，在 App 設定 alias 並由使用者輸入全新長密碼；部署 `firestore.rules`、`storage.rules` 與 `syncProgress` Function；用 Google 與 password 兩種登入實測同 UID、讀取、拒絕所有雲端寫入、下載及本機 profile 隔離。這些步驟尚未於正式 Firebase 執行。

## 風險清單
| 風險 | 嚴重度 | 失敗形態 | 降低方式 / 檢驗 |
|---|---|---|---|
| R-01 macOS/iOS/iCloud 權限 | High | 無法重啟授權、App Store sandbox 不可訪問 | Swift Gateway Spike、signed app 測試、授權撤銷測試 |
| R-02 Firebase rules | Critical | A 用戶讀取 B 媒體 | emulator deny-by-default tests、code review |
| R-03 離線合併 | High | 舊進度覆寫新、意外遠端 Seek | session/sequence 與 conflict tests |
| R-04 SRT 不等長/不對齊 | Medium | 字幕匹配錯誤 | 時間重疊+人工 override，fixture tests |
| R-05 Cloud Storage 費用 | High | 巨大檔案導致不可控傳輸費 | 按需下載、限制單檔、用量預算與使用者明確同意 |
| R-06 Apple 背景限制 | High | 誤宣稱即時同步 | UI 清楚顯示掃描條件，重新啟動補掃 |
| R-07 損壞的 iCloud placeholder | Medium | 將未下載檔誤判刪除 | pending download status + retry |
| R-08 外部套件版本變動 | Medium | Flutter 平台 build 壞掉 | lockfile、pin、三平台 spike |
| R-09 跨帳號殘留 | Critical | 舊用戶本機資料洩漏給新用戶 | UID namespace，登出隔離測試 |
| R-10 操作時序競爭 | High | 切媒體、seek、loop 時串流倒退 | generation token + cancel + fake clock |
| R-11 Web 本機儲存與 OAuth 相容性 | High | 分頁競態、配額耗盡、瀏覽器清除離線資料、彈窗受限 | 觀察 Wasm 儲存模式、驗證多分頁和配額失敗、依 browser matrix 驗收授權設定 |

## ADR 變更模板
```md
### ADR-XXX：標題
狀態：PROPOSED/ACCEPTED/REJECTED
背景/限制：
考慮選項：
選擇與證據：
替代方案成本：
資料遷移與回滾：
影響工作包：
決策者及日期：
```

## 當下外部前置條件
- 確認 Apple Xcode 環境、真機與開發者簽章權限。
- Firebase 專案所有權、Auth providers / Firestore / Storage / Rules、計費方案。
- iCloud 測試資料夾的明確使用者選取，不掃描未授權資料夾。
- 若缺任何一項，該項標 BLOCKED，其餘可測純 Dart 工作照常推進。
