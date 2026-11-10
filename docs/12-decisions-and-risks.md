# ADR 決策與風險紀錄

狀態定義：`ACCEPTED` 已由產品需求/已知條件確認；`PROPOSED` 建議但尚需 Stage 1 審核；`OPEN` 需使用者或平台實測決定；`BLOCKED` 需要外部資源。禁止把 PROPOSED 視為功能已完成。

## 決策表
| ID | 狀態 | 決策/選項 | 為什麼 / 後續行動 |
|---|---|---|---|
| ADR-001 | ACCEPTED | Flutter 支援 Android/iOS/macOS | 使用者要求 |
| ADR-002 | ACCEPTED | M4A/MP3 優先，雙語 SRT 逐句精聽 | 使用者要求 |
| ADR-003 | ACCEPTED | 同 App 帳號跨平台同步教材、字幕與進度 | 使用者要求 |
| ADR-004 | ACCEPTED | Mac iCloud 使用者自選資料夾，播放清單綁定 | 使用者要求 |
| ADR-005 | PROPOSED | Firebase Auth/Firestore/Storage 作跨平台後端 | 需建立/選定 Firebase 專案，確認 Blaze 用量與 Storage 成本 |
| ADR-006 | PROPOSED | Riverpod + Drift + just_audio + go_router | 需確認實際 pub.dev 版本與 local Flutter 3.32 相容性 |
| ADR-007 | PROPOSED | Apple iCloud folder 為 read-only source | 保護個人原始檔案，刪來源時不抹除學習資料 |
| ADR-008 | PROPOSED | Mac 是 MVP 自動 iCloud 入口；iOS 直接 folder scan 延後 | iOS background 不保證即時任意目錄監控 |
| ADR-009 | PROPOSED | SQLite + Outbox，按需下載、雲端資產上傳後發佈 metadata | 弱網可靠性；需明確 Retry/Idempotency |
| ADR-010 | OPEN | Auth providers（Google/Apple/Email） | 需看 App Store 登入規則與使用者偏好 |
| ADR-011 | OPEN | Firebase 所有權、費率預算、最大單檔限制 | 不能擅自建立付費資源 |
| ADR-012 | OPEN | 播放進度衝突 canonical algorithm | 需 spike 對兩裝置交錯/離線事件的真實時序 |
| ADR-013 | OPEN | macOS 背景播放與 Media key 控制方案 | 實測 just_audio_background / audio_service plugin support |
| ADR-014 | OPEN | 登出時本機下載、cache 與 outbox 保留或刪除 | 涉及跨帳號隱私/容量 |
| ADR-015 | OPEN | 音訊外再支援 MP4 的里程碑 | 使用者主要使用音訊，影片之後擴充 |
| ADR-016 | OPEN | SRT encoding fallback 與語言偵測套件 | UTF-8 優先；需平台與授權評估 |
| ADR-017 | OPEN | SDK 最低 OS 版本與 Flutter SDK 升級 | 本機目前 Flutter 3.32.2；先診斷後提出升級方案 |

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
