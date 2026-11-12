# ADR 決策與風險紀錄

狀態定義：`ACCEPTED` 已由產品需求/已知條件確認；`PROPOSED` 建議但尚需 Stage 1 審核；`OPEN` 需使用者或平台實測決定；`BLOCKED` 需要外部資源。禁止把 PROPOSED 視為功能已完成。

## 決策表
| ID | 狀態 | 決策/選項 | 為什麼 / 後續行動 |
|---|---|---|---|
| ADR-001 | ACCEPTED | Flutter 支援 Android/iOS/macOS | 使用者要求 |
| ADR-002 | ACCEPTED | M4A/MP3 優先，雙語 SRT 逐句精聽 | 使用者要求 |
| ADR-003 | ACCEPTED | 同 App 帳號跨平台同步教材、字幕與進度 | 使用者要求 |
| ADR-004 | ACCEPTED | Mac iCloud 使用者自選資料夾，播放清單綁定 | 使用者要求 |
| ADR-005 | PROPOSED | Firebase Auth / Firestore / Storage 保留為候選 | macOS Core 與本機 Firestore／Storage 傳輸通過，Auth 卡在 Keychain entitlement。正式環境受 ADR-010／011／018 阻擋 |
| ADR-006 | ACCEPTED | Riverpod 3.3.2 接入 bootstrap；Drift 2.31.0、just_audio 0.10.6 作後續 Spike 基準 | 同一個 Dart 3.8.1 solver 已解析成功；套件與原生驗證分開記錄；單頁暫緩 go_router |
| ADR-007 | ACCEPTED | macOS 自選來源採唯讀授權 | grant 留在裝置，原始檔不經 app 寫入；sandbox 實測留 WP-11 |
| ADR-008 | ACCEPTED | Mac 是 MVP 自動 iCloud 入口，iOS 直接 folder scan 延後 | 產品範圍 §4 與 folder 規格 §3 |
| ADR-009 | ACCEPTED | SQLite 原子寫入與 durable outbox；先驗證 blob 再發佈 metadata | 依同步規格與 Firestore 交易限制；重試與部分失敗規則見下方 |
| ADR-010 | OPEN | Auth providers（Google/Apple/Email） | 需看 App Store 登入規則與使用者偏好 |
| ADR-011 | OPEN | Firebase 所有權、費率預算、最大單檔限制 | 不能擅自建立付費資源 |
| ADR-012 | ACCEPTED | 以 canonical revision 和 session sequence 判斷進度寫入；落後版本保留候選 | 純 Dart 時序已測；伺服器交易及規則由 WP-08／09／13 驗證 |
| ADR-013 | OPEN | macOS 背景播放與 Media key 控制方案 | 實測 just_audio_background / audio_service plugin support |
| ADR-014 | OPEN | 登出時保留／移除快取的產品選項 | 強制 UID 隔離與暫停舊 UID outbox；實際保留期限與磁碟政策待定 |
| ADR-015 | OPEN | 音訊外再支援 MP4 的里程碑 | 使用者主要使用音訊，影片之後擴充 |
| ADR-016 | OPEN | SRT encoding fallback 與語言偵測套件 | UTF-8 優先；需平台與授權評估 |
| ADR-017 | OPEN | 正式最低 OS、Flutter SDK 與 Android JDK 選型 | Flutter 3.32.2 固定；Gradle 8.12 用 JDK 17。候選 Firebase 原生最低版本須審核 |

| ADR-018 | OPEN | FlutterFire Apple 發佈的套件管理方式 | CocoaPods pin 可重跑 Spike；評估 SwiftPM 與 Flutter SDK 升級的相依性後再定正式方案 |
| ADR-019 | OPEN | 刪除保留期、孤兒資產回收、字幕錨點重定位 | 先保留 tombstone 和舊錨點；清理視窗與重定位規則分別在 WP-08／07 前審核 |
| ADR-020 | ACCEPTED | WP-02 以 owner namespace 隔離本機 DB/媒體；媒體按 SHA-256 去重，教材只對相同來源鍵與內容雜湊冪等 | 保留不同來源的獨立 materialId；來源鍵不得含原始路徑。孤兒媒體回收沿用 ADR-019，待後續工作包處理 |
| ADR-021 | ACCEPTED | WP-03 SRT 配對以半開區間重疊判斷；有效重疊至少覆蓋較短 cue 的 25% | 依 T-SRT fixture 驗證多對一、一對多及邊界擦碰；保留門檻參數以便後續 fixture/產品決策調整 |
| ADR-022 | ACCEPTED | WP-04 透過 `AudioPlayerPort` 隔離 just_audio；audio_session 固定 0.1.25 以保留 Android minSdk 21；iOS/Android 中斷暫停且不自動續播 | 0.2.4 實測宣告 minSdk 24；0.1.25 Android Gradle 設定 minSdk 19，且符合 just_audio 0.10.6 相依範圍。speech session 與事件依套件文件；loop 用原生 clip + LoopMode.one。真機精度仍待驗 |
| ADR-023 | ACCEPTED | WP-05 LearningSession 綁定一個教材；replay 保留揭露，換 cue 重設遮蔽；句循環由獨立命令控制 | 對應精聽狀態機；無翻譯仍允許揭露並提示；跨教材 snapshot 不得誤操作播放器。T-LEARN-01..05 自動測試 |

## Stage 1 決策細節（2026-11-10）

### ADR-005／006／010／011／017／018 — 版本與雲端閘門

- Riverpod 以 exact pin 與 lockfile 隨 bootstrap 交付。Drift、just_audio、FlutterFire 只在獨立 Spike 解析；個別模組在接線時再加入依賴。單頁先用 MaterialApp。版本、授權、實測與重跑步驟見 [WP-00／01 交棒](agent/wp-00-01-handoff.md)。
- Firebase Auth／Firestore／Storage 的 macOS 支援表列為 beta。正式 Storage 要 Blaze；即使有免費配額也須先核准專案、預算、單檔上限及區域。驗證先用本機 Emulator 與合成資料。本機 Auth Emulator 匿名登入在目前 debug app 的 Keychain 保存失敗（`SecItemAdd -34018`）。登入方式、具 Keychain Sharing 的有效簽章與帳號切換仍待驗。依據：[FlutterFire 平台表](https://firebase.google.com/docs/flutter/setup)、[Storage 計費要求](https://firebase.google.com/docs/storage/faqs-storage-changes-announced-sept-2024)。
- CocoaPods Spike 的 FlutterFire core 5.1.0 固定 Apple SDK 12.19.3。官方已在 2026 年 10 月停止以 CocoaPods 發佈新 Firebase 版本。正式方案需驗證 Flutter 3.32.2 的 SwiftPM 整合及三平台最低 OS；若須升級，另審 SDK、原生目標與回歸範圍。[Apple SDK 套件管理遷移](https://firebase.google.com/docs/ios/cocoapods-deprecation)。

### ADR-007／008 — Mac 資料夾權限

- 透過使用者選擇的目錄建立 app-scoped、唯讀 bookmark。bookmark bytes、絕對來源路徑及 scan cursor 限於授權裝置與本機使用者範圍。同步資料只含 binding/playlist ID、來源類型與標籤。每次成功的 scope access 成對釋放，watch 取消、disconnect 或登出時結束 session。stale 嘗試安全更新，更新失敗要求重選。
- 原生端協調讀取並檢查解析後 URL 仍位於已授權根目錄，拒絕絕對路徑、穿越與越界 symlink。只將可讀且完整的檔案複製到 app staging，再由匯入層接手。待下載列為存在。掃描失敗不得推導來源缺失，完整掃描發現缺檔只標記來源狀態。watch 事件只觸發重掃。
- WP-11 驗證 sandboxed build 的 user-selected read-only 與 app-scope bookmark 能力、重啟還原、撤銷、移動及 placeholder。直接讀取 iCloud 私有系統路徑會越過使用者選擇的範圍。依據：[Apple App Sandbox](https://developer.apple.com/documentation/security/app-sandbox)、[Security-scoped URL 存取](https://developer.apple.com/documentation/foundation/url/startaccessingsecurityscopedresource())、[資料夾規格](07-icloud-folder-sync.md)。

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

### ADR-012 — 進度衝突與回復

1. 每個 `(UID, materialId)` 有 canonical revision，無紀錄為 0。每次播放工作階段建立 sessionId；sequence 依 `(UID, materialId, deviceId, sessionId)` 單調遞增。每筆 checkpoint 帶有當時確認的 `baseRevision`。
2. 提交時先讀 opId receipt，重送回傳既有結果。交易內讀取該 session 的 sequence high-water 與 canonical。sequence 已見過或較舊就忽略。baseRevision 等於 canonical 才接受並遞增 revision。否則保留該 session 最新候選及原 baseRevision。交易同時寫入結果 receipt、高水位與適用的 canonical／候選，避免併發與回覆遺失造成重複效果。
3. 離線 checkpoint 留在本機，候選確認後 outbox 可完成，候選仍可供使用者選擇。若使用者選定候選或保留目前位置，用畫面當時的 canonical revision 和候選識別提交明確的解決操作，交易檢查兩者仍有效後更新 canonical 並標記已解決的候選。任一版本已改變則重新呈現，保留其他候選。後續本機 checkpoint 可以承接同 session 自己剛確認的寫入；只可在產生新未送出操作時使用該 revision，不能借用別台裝置的新版本覆蓋衝突。
4. 裝置時鐘與播放位置大小都不能決定勝負，倒帶也能合法接受。進度的 server timestamp 用於呈現，遠端更新只影響下次開啟／明確續播選擇。依據：[時序測試](../test/unit/progress_policy_test.dart)、[Firestore 交易隔離](https://firebase.google.com/docs/firestore/transaction-data-contention)。WP-09／13 尚需驗證 receipt 重送、兩裝置併發、切帳號與播放中的 Seek 隔離。

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
