# 可直接貼到 Codex / ChatGPT Work 的四階段指令

使用方式：將以下任一段 Prompt 在專案根目錄的 Code Agent 對話貼上。可直接指派不同模型／推理強度；不要把 Stage 2 的整批工作一次交給 Luna，應每次指定一個 WP。

## Prompt A — Stage 1 / Sol High
```text
工作專案：/Users/linli/AndroidStudioProjects/english_learning_player
角色：架構負責人（Stage 1 / Sol High）。
先讀 AGENTS.md、docs/README.md、docs/00-02、docs/06-09、docs/11-13，以及相關官方 Flutter Skill。
本次只執行 WP-00 與 WP-01；禁止開發超出 bootstrap、契約與風險 Spike 的整套播放器。
任務：核驗目前 Flutter SDK、Android/iOS/macOS 工具鏈、Firebase FlutterFire 對 macOS 的實際可用性、Riverpod/Drift/just_audio 版本相容性；選定可測試的 interfaces 與資料模型；決定同步衝突方案、失敗重試和 iCloud 授權邊界，將未決事項寫 ADR。所有 decisions 附證據，未知不可假設。建立最小可測假實作、測試骨架與可驗證的第一個 vertical slice。
驗收：實際執行 flutter analyze、flutter test，回報三平台 build 的 PASS/FAIL/BLOCKED，確認沒動未授權設定、不啟動雲端付費資源。
交付：具體修改清單、接口清單、ADR、測試、交棒狀態與建議下一個 WP。除非我要求，請勿 push 或合併。
```

## Prompt B — Stage 2 / Luna High（每次替換 WP）
```text
工作專案：/Users/linli/AndroidStudioProjects/english_learning_player
模型角色：功能實作（Stage 2 / Luna High）。
這次只做 [WP-03]（請把此 ID 改成 docs/11-work-packages.md 的單一 WP）。
先讀 AGENTS.md、docs/README.md、docs/11-work-packages.md 中對應工作包、它指向的模組規格，以及適用 .agents/skills/*/SKILL.md。
依既有契約實作最小功能、測試 fixtures、正反邊界案例與錯誤處理。不可把 Firebase SDK 或 AudioPlayer 引入 Widget，不得偷偷更改 schema/接口，不得越權改其他模組。遇到規格不明或涉及 iCloud / progress conflict 時，寫入 docs/12-decisions-and-risks.md 並先完成可單測的部分。
請實際跑 dart format、flutter analyze、flutter test 及本 WP 專用測試；報告 PASS/FAIL/BLOCKED、修改檔案、風險和下一步。完成後如我授權，才在獨立 branch commit；勿 push。
```

## Prompt C — Stage 3 / Sol High
```text
工作專案：/Users/linli/AndroidStudioProjects/english_learning_player
角色：跨平台整合負責人（Stage 3 / Sol High）。
先讀 AGENTS.md、docs/01、docs/02、docs/06-09、docs/11、docs/12、docs/13 與目前 Stage 2 交棒報告。
執行 WP-11→WP-14，但每完成一個 WP 必須先跑測試並回報 Gate，再繼續下一個。優先完成 macOS 用戶授權 iCloud 資料夾→偵測→匯入雙 SRT→雲端發佈→iPhone 下載播放→跨裝置續播。
特別查核 macOS security-scoped bookmark、file coordination、部分下載與 rename、Firebase Auth Rules、冪等上傳、離線競態、遠端進度不搶正在播放的設備。不得宣稱 iOS 已實現任意資料夾背景常駐監控。不要提交私密憑證或付費資源配置。
交付每個 E2E 測試的設備、真實輸出、PASS/FAIL/BLOCKED、故障注入結果與 ADR；如缺開發者帳號/真機/雲端設定，明確提出 blocker，不虛報通過。勿推送遠端。
```

## Prompt D1 — Stage 4 / Luna High（測試與修正）
```text
工作專案：/Users/linli/AndroidStudioProjects/english_learning_player
角色：測試工程師（Stage 4 / Luna High）。
讀 AGENTS.md、docs/08、docs/09、docs/11 中 WP-15，以及先前各 WP 交棒。擴充 SRT fixtures、Unit/Widget/Integration regressions、screen size、離線、錯誤回復及基本 accessibility checks。不要僅測 happy path；只修能以測試重現的問題。執行 flutter analyze/test、可用平台 build，逐條映射 FR ↔ Test，提供 PASS/FAIL/BLOCKED 與可重現步驟。勿 push。
```

## Prompt D2 — Stage 4 / Sol High（審查）
```text
工作專案：/Users/linli/AndroidStudioProjects/english_learning_player
角色：最終架構與安全審查者（Stage 4 / Sol High）。
讀 AGENTS.md、docs/00-13、WP-15 測試報告與實際程式碼。本次只執行 WP-16：追查 import→local→sync→remote→download→playback→progress 全鏈路，檢查 P0 資料流失、跨帳號資料外洩、未授權 iCloud 讀取、重覆上傳/刪除、同步衝突、取消/重試時序與跨平台能力宣稱。用可核查代碼/測試證據分級問題，提出修復排序與未通過 Gate；禁止以主觀「看起來正常」批准發佈。勿 push。
```

## Prompt E — WP-17 第一段 Web 實作

先讀 [WP-17 實作交棒](agent/wp-17-implementation-handoff.md)，後續每段另開一次任務。

```text
在 /Users/linli/AndroidStudioProjects/english_learning_player 工作。先檢查 Git 狀態，保留已存在的修改。讀 AGENTS.md、docs/README.md、docs/11-work-packages.md、docs/14-web-platform.md、docs/agent/wp-17-implementation-handoff.md，依專案工程、Flutter 架構及相關測試 Skill 執行。

只執行 WP-17 第一段「Web 入口與 Drift 最小驗證」。沿用鎖定的 Flutter、Drift 和 sqlite3 版本。加入 Web scaffold、官方 worker／WASM、平台 DB adapter 和可重跑的 Chrome smoke 入口。沿用既有 LocalDatabase schema、AccountScope 和 Repository。

用 Chrome 驗證 worker、WASM MIME、兩個 scope 隔離、重新整理／重開資料庫，以及兩個分頁的安全行為。執行 dart format 檢查、Flutter Analyze、Flutter Test 及 smoke Web build。區分 smoke 入口及完整版的 PASS／FAIL／BLOCKED。到第一段為止，提出下一段所需前置條件。不要實作選檔、播放、OAuth 或正式同步，也不變更 SDK 版本、建立雲端資源或推送 Git。按使用者要求於用量低於 30% 時暫停並留下進度。
```

## 工作包報告建議格式
```text
WP: WP-xx
Branch / commit:
Inputs read:
Modified files:
Contract changes / ADR:
Tests actually run + outputs:
PASS / FAIL / BLOCKED:
Risks and unanswered questions:
Next WP:
```
