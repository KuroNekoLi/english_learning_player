# 四階段 Agent 開發策略

## 基本原則
分工不是模型能力保證，而是讓規格化的工作落在成本較低的模型，把分散式系統、原生權限與跨模組決策留給較高推理強度模型。每次工作都以 **單一工作包 → 可執行測試 → 交棒報告** 收斂。

## Stage 1：Sol High｜架構、契約、技術風險 Spike
**輸入**：`AGENTS.md`、`docs/00-08`、`docs/12`。**產出**：可編譯的最小 app bootstrap、正式決策 ADR、domain/interface 最小契約、模擬測試環境設計、三平台依賴確認與 Firebase 接線計畫。
- WP-00：依現有專案做 SDK/套件/平台能力核驗，不任意升級。
- WP-01：決定接口、ID、schema、auth/provider/cost、資料刪除政策與大檔同步策略。
- 收尾：建立可執行的 Unit test skeleton + 風險/未決清單。
**Exit Gate**：`flutter analyze`、`flutter test` 維持通過；規格未決部分明確記錄，不用假實作填洞。

## Stage 2：Luna High｜穩定的模組實作
**輸入**：已凍結的接口與單一 WP 任務。**產出**：工作包程式碼、fixtures、Unit/Widget tests、驗收報告。
- 依序執行 WP-02（資料庫+匯入）、WP-03（SRT）、WP-04（AudioEngine）、WP-05（學習模式）、WP-06（RWD）、WP-07（收藏）、WP-08（雲端基礎）、WP-09（進度）、WP-10（平台背景播放）。
- 不要在一次 Luna 工作中同時實作 3 個跨域工作包。
- 若遇 iCloud 原生授權、Firestore 資料一致性或第三方套件不支援 → 停在可重現測試與證據，升級交 Sol。
**Exit Gate**：`docs/08` Gate B；每 WP 報告對應 acceptance ID，未測不得假 PASS。

## Stage 3：Sol High（需要時 Sol Medium）｜跨界整合
**輸入**：Stage 2 的穩定模組、真機與 Firebase 測試環境、未決 ADR。**產出**：Mac iCloud 資料夾授權+監控、媒體同步可靠性、三平台重試與衝突修正。
- WP-11：macOS 原生 folder gateway 與安全書籤。
- WP-12：folder reconcile / playlist 綁定 / 雲端上傳全鏈路。
- WP-13：並行進度、斷網回復、跨帳號隔離的整合測試。
- WP-14：Mac → iPhone / Android 下載與續播的 E2E。
**Exit Gate**：`docs/08` Gate C；對不能執行的 iOS/macOS 真機步驟明記 BLOCKED，不虛報完成。

## Stage 4：Luna High 執行 QA → Sol High 做最終架構審查
**輸入**：Stage 3 E2E 結果與風險清單。**產出**：所有 FR 回歸測試、performance/無障礙/安全報告、修補、release checklist。
- WP-15 Luna：擴充回歸、RWD/無障礙/非正常流程測試、補缺。
- WP-16 Sol：跨模組審計（資料刪除、合併、Auth、iCloud、測試證據）；提出必改項與阻斷。
**Exit Gate**：`docs/08` Gate D，任何高風險未決不宣稱已可上架。

## Git 策略與交棒規範
每個 WP 使用獨立 feature branch（推薦 `feat/wp-03-subtitles`），不重寫其他工作包，避免 merge 多個 Agent 未完成作業。完成後短 commit，PR／合併須由使用者或特別授權 Agent 操作。
交棒輸出 `WP ID / commit / 本次決策 / 規格差異 / PASS/FAIL/BLOCKED / 需要 Sol 的問題`。不可默默修改已批准契約；若需更改，以 ADR + 向下相容 migration 實施。
