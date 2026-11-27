# English Learning Player — AI Agent 作業規範

本儲存庫是以 Android、iOS、macOS、Web 為支援目標的 Flutter 雙語精聽播放器。Web 的實作與發布驗收由 WP-17 追蹤。所有 Agent 在修改程式前必須先讀本檔、`docs/README.md`、本次任務所對應的模組規格，以及 `docs/11-work-packages.md`。

## 權威性順序
1. 使用者本次明確指示與安全限制。
2. 本檔與 `docs/00-product-requirements.md` 的已核准範圍。
3. `docs/01-architecture.md`、`docs/02-domain-models.md` 與各模組規格。
4. `docs/11-work-packages.md` 的任務驗收；Presentation 視覺規範以 `docs/15-editorial-design-system.md` 為準。
5. 對應的 `.agents/skills/*/SKILL.md` 與 Flutter/Dart 官方文件。

衝突時不要擅自改變產品行為；把衝突、選項、風險寫入 `docs/12-decisions-and-risks.md`。不可將「提議」視為使用者已批准的事實。

## 開發硬規則
- 先讀規格，再只實作一個有 ID 的工作包；先檢查 `git status`，不可覆蓋其他人的未提交變更。
- 遵守 Flutter 官方 View → ViewModel → Repository → Service 分層；複雜且可重用的規則才抽 Domain。共用 UI 與商業邏輯禁止直接使用 platform plugin。
- 專案決策採 Riverpod；官方架構 Skill 若示範 `ChangeNotifier` / `provider`，學習其責任分層，但在此專案使用 Riverpod DI / Notifier，不混用兩套狀態管理。
- 音訊必須經過 `AudioEngine` 單一入口；字幕對齊、循環、同步衝突、檔案配對應為可測試的純 Dart 邏輯。
- 必須同時考慮 Android、iOS、macOS、Web。原生存取使用 Platform Channel 或專用 Adapter，瀏覽器的資料庫、檔案存取與認證也透過平台 Adapter。Web 構建不可依賴原生專用 API。
- 使用者資料先落地、離線可用；網路同步可重試且具冪等性，不因資料夾來源刪除就直接抹除收藏及學習紀錄。
- 嚴禁將 Firebase admin 憑證、個人金鑰、簽章檔、登入 Token 或真實媒體教材提交 Git；客戶端 Firebase 設定不等於伺服器秘密，但仍依環境管理。
- 不要添加無關功能、帳號付費機制、強制 AI 或 Android 開發類比。
- 新增套件前檢查官方文件、現有 Flutter/Dart 相容性、macOS 支援與授權；不可默默升級 SDK 或繞過平台權限。
- 未實際執行的命令與真機測試不可標註 PASS。對需要 Apple Developer/Firebase 專案的步驟，標記 BLOCKED 與人工前置條件。

## Editorial Reader UI 硬規則（WP-22 / Visual Baseline v1.0）
- 所有 UI/UX 任務先讀 [設計規範](docs/15-editorial-design-system.md)、[Tokens](docs/design-system/editorial-tokens.json) 與 [WP-22 交棒](docs/agent/wp-22-editorial-handoff.md)。設計風格已獲使用者確認；重大視覺改動先提案確認，不得自行改品牌。
- 原生與 Web 共用 `lib/core/design_system/`；優先使用 `EditorialTheme`、`EditorialColors.of(context)`、`EditorialTypography`、`EditorialSpacing/Radius/Size` 與既有共用元件。Feature 不新增硬編碼品牌色、任意字體、獨立主題、裝飾漸層或重複元件。官方第三方品牌資產例外；必要的新 token 集中定義並同步 JSON 與測試。
- 暖白紙感、森林綠、襯線英文、低干擾控制；明暗主題皆必須可讀。保留裝置外觀及字幕偏好相容性；不得為了美觀移除功能、錯誤提示、唯讀限制或改動 AudioEngine、同步、資料契約。
- 以可用寬度及 TextScaler 決定排版；不關閉系統字體縮放。一般文字 4.5:1、必要控制邊界 3:1、操作區 48×48 logical px 為設計基準；使用可見焦點、Semantics、Tooltip，狀態不得只靠顏色。翻譯色使用 readableTranslation 保護對比。
- 重要畫面修改需涵蓋明暗、窄/寬視窗、大字體、功能回歸及適用 Golden；更新 Golden 前必須審查實際渲染，不得以更新基準掩蓋缺陷。區分使用者人工確認、工具觀察與未驗證平台，不把視覺驗收視為正式發布認證。
- 規格、程式、Tokens、測試及交棒文件須同批更新；未完成驗收與既有缺陷記錄於 WP-22 及風險文件。

## Agent Skills
依任務選擇性讀取 `.agents/skills/`，詳見 `docs/13-skills-and-sources.md`。本專案附有 Flutter/Dart 官方維護的 Skill 副本與專案專屬 Skill `english-learning-player-engineering`。

## 每個工作包的標準流程
1. 讀工作包的輸入、產出、依賴、驗收及測試案例。
2. 寫簡短執行計畫；確認 API / 資料模型契約未被任意改寫。
3. 實作最小可驗證範圍，補測試、假物件與錯誤處理。
4. 執行 `dart format --output=none --set-exit-if-changed .`、`flutter analyze`、`flutter test`；依工作包加做真機、整合或 Firebase Emulator 測試。
5. 摘要列出修改檔案、測試結果、未驗證情境與剩餘風險；必要時更新契約文件。
6. 只在任務明確要求時 commit；不得自動 push、建立遠端資源或配置雲端計費。

## 已鎖定產品目標
M4A/MP3 音訊優先，雙語 SRT 自動/手動配對、逐句播放及精聽、跨 macOS/iOS/Android/Web 同帳號同步、Mac iCloud 授權資料夾綁定播放清單。Web 的選檔、瀏覽器儲存與 Google 登入見 [WP-17 規格](docs/14-web-platform.md)。iOS 直接資料夾監控與影片留待後續。

## 開發階段
Stage 1 Sol High（架構與契約）→ Stage 2 Luna High（模組實作）→ Stage 3 Sol High（高風險整合）→ Stage 4 Luna 測試 + Sol 審查。實際模型名稱取決於可用設定；重點是任務類型與驗收門檻，而非宣稱模型保證成功。
