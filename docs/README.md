# 工程文件入口

> 狀態：Specification baseline v0.1。Stage 1 契約及 Stage 2 WP-02..10、Stage 3 WP-11～WP-14 已重驗；遠端 playlist metadata 與實機跨裝置 E2E 仍有未完成項目，Gate C 尚未通過。日期：2026-11-17。
> 優先完成一條可量測的使用者旅程：Mac iCloud 資料夾新增 M4A＋雙 SRT → 自動配對匯入 → 雲端同步 → iPhone 同帳號續播。

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
