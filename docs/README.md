# 工程文件入口

> 狀態：Specification baseline v0.1。Stage 1 契約及 Stage 2 WP-02..10、Stage 3 WP-11～WP-14 已重驗；遠端 playlist metadata 與實機跨裝置 E2E 仍有未完成項目，Gate C 尚未通過。日期：2026-11-17。
> 優先完成一條可量測的使用者旅程：Mac iCloud 資料夾新增 M4A＋雙 SRT → 自動配對匯入 → 雲端同步 → iPhone 同帳號續播。
> 2026-11-21 納入 Web 為第四個正式支援目標。Web 實作與發布驗收列入 WP-17。2026-11-24 新增同 UID password 唯讀登入工作包 WP-18；正式 Firebase 設定、Rules/Functions 部署仍待執行。

> 2026-11-27：Editorial Reader Visual Baseline v1.0 已獲使用者人工驗證回報；WP-22 主要 Flutter 視覺重構已實作，發布驗收與 Figma Phase 4 同步仍有未完成項目。

## 文件地圖與閱讀順序

| 文件 | 唯一責任 | 主要讀者 |
|---|---|---|
| [00-product-requirements.md](00-product-requirements.md) | MVP 目標、優先級、非目標、使用者旅程 | 全體 |
| [01-architecture.md](01-architecture.md) | 層級、依賴方向、模組邊界與 E2E 因果鏈 | Sol / Luna |
| [02-domain-models.md](02-domain-models.md) | 物件身分、狀態、SQLite/Firestore 契約 | Sol / Data Agent |
| [03-audio-player.md](03-audio-player.md) | AudioEngine 行為、Seek、Repeat、平台中斷 | Player Agent |
| [04-subtitle-engine.md](04-subtitle-engine.md) | SRT 解析、配對、對齊、校正 | Subtitle Agent |
| [05-learning-and-ui.md](05-learning-and-ui.md) | 精聽狀態機、UI、無障礙與 RWD | UI Agent |
| [06-cloud-sync.md](06-cloud-sync.md) | Firebase 傳輸、離線、衝突、資料安全 | Sync Agent |
| [07-icloud-folder-sync.md](07-icloud-folder-sync.md) | macOS/iOS 授權資料夾、掃描與限制 | Native Agent |
| [08-testing-and-quality.md](08-testing-and-quality.md) | 測試矩陣、命令、真機驗收與 release gate | QA Agent |
| [09-four-stage-execution.md](09-four-stage-execution.md) | 四階段模型分工、退出條件與交棒 | Orchestrator |
| [10-agent-prompts.md](10-agent-prompts.md) | 可直接貼給不同強度模型的 Prompt | 使用者 |
| [11-work-packages.md](11-work-packages.md) | 可單獨執行的工作包 ID、相依與驗收 | Executor |
| [12-decisions-and-risks.md](12-decisions-and-risks.md) | ADR、未決事項、風險與決策人 | Sol |
| [13-skills-and-sources.md](13-skills-and-sources.md) | 官方 Skill 安裝、更新、來源與覆寫 | 全體 |
| [14-web-platform.md](14-web-platform.md) | Web 平台範圍、瀏覽器儲存、Google Web OAuth、WP-17 驗收 | Web Agent / QA |
| [15-editorial-design-system.md](15-editorial-design-system.md) | Editorial Reader 明暗主題、共用元件與無障礙規格（Visual Baseline v1.0） | UI Agent / QA |

## 讀法：接收 → 處理 → 輸出
每一個元件都要回答：收到上一層什麼？處理哪些規則？交給下一層什麼？如何證明正確？不得堆砌互不相連的檔案名稱。

## 開發守則
- `AGENTS.md` 是 Codex 專案進入點；技能採 `.agents/skills/<name>/SKILL.md`。
- 指定工作包如 `WP-02`，先閱讀任務所引文件，不必每次讀完整文件庫。
- [WP-00／WP-01 交棒](agent/wp-00-01-handoff.md) 記錄現有程式契約、平台證據與後續工作包的驗證範圍。
- [WP-12 交棒](agent/wp-12-handoff.md) 記錄資料夾掃描重整、本機清單、schema v6 與遠端 metadata 限制。
- [WP-13 交棒](agent/wp-13-handoff.md) 記錄多裝置離線衝突、帳號切換安全與真實雲端驗證限制。
- [WP-14 與 Gate C 交棒](agent/wp-14-handoff.md) 記錄 Stage 3 的真機證據與未完成項目。
- [WP-14 Firebase 同步交棒](agent/wp-14-firebase-handoff.md) 記錄 App 同步接線、本機 Emulator 驗收及遠端部署前置條件。
- [WP-15 Stage 4 QA 報告](agent/wp-15-qa-report.md) 記錄 FR 回歸矩陣、失敗注入、Gate D 結果與未解阻礙。
- [WP-16 架構修正](agent/wp-16-architecture-remediation.md) 記錄元件拆分、行為修正、回歸證據與發布條件。
- [WP-17 Web 實作交棒](agent/wp-17-implementation-handoff.md) 記錄分段操作、鎖版資產、測試與交回架構審查的條件。第一段可用 [Prompt E](10-agent-prompts.md#prompt-e--wp-17-第一段-web-實作) 開始。
- [WP-18 唯讀登入交棒](agent/wp-18-readonly-account-handoff.md) 記錄 username alias、同 UID credential linking、服務端寫入拒絕及正式啟用前置條件。
- [WP-19 Dictionary 交棒](agent/wp-19-dictionary-handoff.md) 記錄字幕單字查詢、BlackCatNews API/模型契約、Drift local-first cache 與驗收限制。
- [WP-20 單字庫原句卡規格](agent/wp-20-word-bank-original-context-spec.md) 定義字幕快照、片段回放、TTS 備援與同步契約。
- [WP-20 實作交接](agent/wp-20-handoff.md) 記錄完成項目、測試結果與平台驗收限制。
- [WP-22 Editorial Reader 交棒](agent/wp-22-editorial-handoff.md) 記錄已實作模組、使用者人工驗收、自動化證據、既有缺陷與發布前剩餘項目。
- [Editorial Tokens](design-system/editorial-tokens.json) 為設計系統機器可讀對照基線；Flutter 色彩契約測試須與其一致。
