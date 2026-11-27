# WP-22 — Editorial Reader Visual Baseline v1.0 交棒

日期：2026-11-27
分支：codex/product-design-system
基底：a99ef92（Add saved word highlights, per-cue translations and subtitle preferences）
狀態：Phase 5–6 主要實作完成；使用者明確回報「我已人工驗證完成」。此回報未細分平台、頁面或無障礙測試項目，故僅記錄人工視覺驗收，不宣告 release gate PASS。

## 1. 下一個 Agent 必讀
- AGENTS.md、docs/README.md、docs/15-editorial-design-system.md、docs/design-system/editorial-tokens.json。
- 專案 skill：.agents/skills/english-learning-player-engineering/SKILL.md。
- WP-22 工作包及 ADR-037 / R-12（docs/11-work-packages.md、docs/12-decisions-and-risks.md）。
- Figma：https://www.figma.com/design/E1cnuhAjVxOU3hfFewyfOW 。Phase 1–3 已建立可編輯畫板；Phase 4 明暗 Variables / component variants 未同步，Starter 工具額度曾受限。Flutter 實作規格以 repo 為準。

## 2. 已實作與程式定位
| 範圍 | 程式位置及契約 |
|---|---|
| 設計基礎 | lib/core/design_system/editorial_tokens.dart：EditorialColors ThemeExtension、Spacing、Radius、Size、readableTranslation 對比保護；editorial_theme.dart：ThemeData 明暗主題 |
| 字體 | editorial_typography.dart；assets/fonts/ 三套 OFL 字型及授權；editorial_font_licenses.dart 註冊授權，pubspec.yaml 宣告資產。來源 Google Fonts commit 5026800714d07231937d92eb4cceabf06e05d74e |
| 外觀 | theme_preference.dart、theme_mode_tile.dart；appearance.theme_mode.v1 裝置本地偏好，system/light/dark，原生與 Web 入口共用 |
| 共用元件 | editorial_components.dart：EditorialListRow、EditorialLanguageControl、EditorialPageHeading；控制項樣式由 ThemeData 集中管理 |
| 播放器 | player_page.dart 與 widgets/：襯線英文、當前 cue 左線、語言底線、置中播放控制、精聽標籤、可視範圍提示及樣式預覽 |
| 字典與單字庫 | dictionary_lookup_panel.dart、dictionary_word_text.dart、word_bank_page.dart；保留查字、收藏、原句與發音，新增單字/詞義搜尋 |
| 教材與收藏 | lib/app/library_page.dart、web_library_page.dart、library_material_list.dart、bookmarks_page.dart；保留匯入、資料夾、搜尋、下載、同步、續播與原句定位 |
| 帳號及設定 | account_sign_in_view.dart、web_account_page.dart、source_management_page.dart、firebase_sync_panel.dart；保留 Google/Apple 與唯讀登入、錯誤及載入訊息 |

注意：Phase 5–6 是主要視覺實作完成，不代表所有 Figma 細節逐像素相符、每個元件狀態全面驗證或所有平台已建置。不得重寫既有音訊、同步及資料層以追求視覺一致性；不修改原始 SRT。既有 player.subtitle_style.v1 保持相容，使用者選的翻譯 alpha 仍保存，實際合成色按 WCAG 對比基準調整。外觀偏好不跨裝置同步。

## 3. 實際驗收證據（2026-11-27）
以下自動化數據源自本次重構執行的工具與留存日誌；不是使用者人工測試數量。
| 項目 | 結果 | 備註 |
|---|---|---|
| flutter analyze --no-pub | PASS | 收尾時重新執行，No issues found!（16.3s） |
| dart format | PASS（先前重構階段） | lib/test 已執行格式檢查；收尾僅修改文件 |
| flutter test --no-pub --reporter expanded | 243 PASS / 4 SKIP / 1 FAIL | /tmp/editorial-final-tests.log；唯一失敗 T-FOLDER-08 |
| 基底重現 | FAIL（既有） | 原始 a99ef92 的獨立 worktree 重現 T-FOLDER-08 watch notifications schedule a full rescan；/tmp/editorial-baseline-folder.log |
| 明暗色彩、偏好持久化、RWD | PASS | test/core/design_system/editorial_theme_test.dart、test/features/player/player_page_test.dart；全套結果含這些測試 |
| Golden | 2 PASS | desktop light、mobile dark；已檢視實際渲染並修正主播放圖示前景色。兩張 PNG 置於 test/features/player/goldens/ |
| Web build | PASS（JS） | flutter build web --no-pub；flutter_tts 4.2.5 JS interop 的 Wasm dry run 警告；未證明 Wasm build 或正式部署 |
| macOS build（工具環境） | BLOCKED | Xcode SPM 解析失敗、DVTFilePathFSEvents、DARWIN_USER_CACHE_DIR Code=5；未關閉 SPM 或改動簽章 |
| Android build（工具環境） | 未確認 | 執行中斷，留存 KGP plugin 遷移警告，無成功產物證據 |
| iOS build（工具環境） | 未執行 | 不推定已通過 |
| 使用者人工驗證 | 已回報完成 | 未提供平台／頁面／版本細節，不覆蓋上述工具驗收結果 |

完整測試曾因磁碟不足中斷，僅清除專案可重建編譯快取約 3 GiB，未刪除教材與資料庫。交棒整理時 df 顯示約 2.6 GiB 可用；仍應先確認磁碟與原生 SDK，再執行完整平台建置。暫存日誌可被 OS 清除，故本表保留長期摘要。

## 4. 維護及回歸指令
- dart format --output=none --set-exit-if-changed lib test
- flutter analyze --no-pub
- flutter test --no-pub test/core/design_system test/features/player/player_page_test.dart
- flutter test --no-pub test/features/player/player_page_test.dart --plain-name 'editorial golden'
- flutter test --no-pub --reporter expanded

不可用 --update-goldens 直接消除未審查的差異。必要時固定相同 SDK、DPR 與內嵌字型驗證跨 OS 渲染差異。改品牌色同步 Dart、JSON 與對比測試；改元件狀態同步規範及 Widget Tests。新畫面重用既有元件而非複製。

## 5. 尚未關閉的發布條件
1. 獨立工作包排查 T-FOLDER-08；不把既有失敗靜默標 skip，也不在視覺重構中改同步時序。
2. 解決磁碟及 Xcode/Android 建置環境，完成各平台建置與實機驗證。Web JS 已建置，Wasm 相容性警告仍在。
3. 逐頁完成 Accessibility Guideline API、VoiceOver/TalkBack、鍵盤、極端字體及明暗實機測試；Golden 和使用者人工回報不取代完整矩陣。
4. Figma 額度恢復後同步 Phase 4 與補足畫板渲染驗收；評估 13 MB 字型資產的下載及包體成本。
5. 依既有 Gate C/D 與 WP-17 檢查發布，未經明確授權不 push、merge 或變更雲端資源。

本次交棒目的為保存已確認的產品視覺基線與真實開發證據，非宣告正式發布。
