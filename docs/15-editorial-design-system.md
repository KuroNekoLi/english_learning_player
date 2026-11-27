# Editorial Reader — Design System v1.0
日期：2026-11-27。狀態：Visual Baseline v1.0，使用者已確認 Editorial 視覺方向並回報人工驗證完成。Phase 5–6 主要 Flutter 實作已落地；Phase 7 發布驗收仍未全部完成。人工驗證未明列平台及檢查矩陣，不視為四平台、無障礙或上架 Gate PASS。詳見 [WP-22 交棒](agent/wp-22-editorial-handoff.md)。Figma Phase 1–3 初稿已建立；Phase 4 同步仍受 Starter MCP 額度限制。
Figma: https://www.figma.com/design/E1cnuhAjVxOU3hfFewyfOW
機器可讀 token：[editorial-tokens.json](design-system/editorial-tokens.json)。

## 1. 設計原則與範圍
- Content first：暖白紙感、墨黑、森林綠、低干擾控制；不使用全頁漸層、玻璃擬態、大量陰影或裝飾插畫。保留原有操作及錯誤狀態。
- 四平台 Android、iOS、macOS、Web；不因示意稿簡化而移除資料夾、搜尋、匯入、排序、下載/同步、原句、唯讀登入或帳號切換。
- 本文件只規範 Presentation。AudioEngine、LearningSession、Riverpod DI、Repository、Drift/Firebase、安全規則及原始 SRT 不變。舊文件若描述早期逐句播放行為，以現有已測程式契約為準；任何行為變更另立工作包。
- 英文閱讀採 Source Serif 4，介面 Inter，繁中 Noto Sans TC。三套已從 Google Fonts 官方來源固定版本取得並隨 App 內嵌，OFL 文件與 LicenseRegistry 登記見 assets/fonts/、editorial_font_licenses.dart；約 13 MB。正式發布仍需確認平台渲染、包體及 Web 初次載入效能。使用者既有字幕樣式優先於主題預設。

## 2. 語意 token
JSON 是 Phase 5 程式實作的對照基線，不是 runtime 配置。採 ThemeData/ColorScheme 加 EditorialColors（ThemeExtension），所有 feature 從 context 讀取語意角色，不寫 hex。明暗皆完整指定，不使用 indigo seed 推導。主題提供 system/light/dark；透過 themePreferenceProvider 與 SharedPreferences 的 appearance.theme_mode.v1 持久化，獨立於帳號資料；原生及 Web 共用。
- background 是閱讀紙張；surface 是底部 transport/浮窗；activeSubtitle 淡底＋左側 3px 線；primary 是強調/播放；onPrimary 是填色按鈕文字。
- divider 只作裝飾分隔，不能當唯一可操作邊界。controlOutline 是必要輸入邊界/進度軌的識別色；focus 為 2px 可見焦點線。wordHighlight 與 onWordHighlight 必須成對使用。
- Error 使用 error 色與文字/圖示並行，不以顏色獨立傳達下載、同步、權限或收藏狀態。
- 禁用控制項顯示低干擾但可辨識，維持語意 disabled；不能將合法功能當 disabled 來逃避對比驗收。

## 3. Typography / layout
- 英文閱讀 19 logical px、w400、1.45 行高（保留 14–32 使用者設定）；中文 15、w400、1.45（12–26）；metadata 12；UI label 13；頁標題 32（窄視窗可 28）；長文章標題自然換行。不可關閉系統 TextScaler。讀取長行不裁切、不固定字幕列高。
- spacing 4/8/12/16/24/32/48，radius 4/6/8，陰影僅浮層必要時使用。英文與翻譯間距 4–8；字幕垂直 padding = 使用者 spacing/2；選中與未選中保持同一文字寬度。
- Reader width 使用 480–1200 的現有偏好（預設 900），實際寬度不得超出安全區。播放器控制列不隨閱讀寬度變窄；桌面 48 / 手機 56 的主按鈕視覺尺寸，操作區最少 48×48。
- Compact (<600)：單欄，控制列窄時雙列；Medium (600–899)：單欄，三區 transport 有空間才使用；Expanded (>=900)：教材庫保留現有側欄與功能，播放器仍單欄閱讀、置中；Web resize、macOS 視窗、旋轉、系統大字體都由 LayoutBuilder 決定，而非平台名稱。600/900 是本產品建議斷點，不是平台強制標準。

## 4. Components 與狀態契約
| 元件 | 正常 | Hover | Focus | Pressed / Selected | Disabled / Loading |
|---|---|---|---|---|---|
| Primary button | primary/onPrimary, radius6 | 輕微 overlay | 2px focus、不能被裁 | 明確 pressed overlay | 禁止重覆提交，loading 有語意 |
| Text/Icon button | textSecondary/primary | surface/activeSubtitle 淺底 | 2px focus | 選中填色＋圖示或文字 | disabled 語意、保留可讀提示 |
| Language control | 純文字＋分隔或留白 | 淺底 | 個別按鈕焦點 | primary 底線＋selected 語意 | 精聽時禁用全域語言切換 |
| Transcript row | 無卡片、時間 rail、自然換行 | 淺底、不跳動 | play/translate/bookmark 可分別操作 | 左線＋activeSubtitle＋播放/暫停 icon | 缺字幕/翻譯有文案，無假內容 |
| Player transport | 左倍速、中播放、右學習模式 | Tooltip + 淺底 | Tab/Space/箭頭可用 | 播放 icon 與狀態同步 | duration 未知不可 Seek |
| List row | 分隔線、標題與 metadata | 淺底 | 可見 focus | 選中語意與顏色 | 缺檔、同步、定位失敗有狀態 |
| Slider/Switch | semantic track/thumb | hover feedback | 鍵盤與 Semantics value | 明確 on/off、顯示數值 | 禁用時不能改值 |
| Dialog/Sheet | surface、細框、最大寬度 | — | focus trap、Esc 關閉 | 確認/取消可見 | loading/error/retry 不丟失表單 |
| Input/Search | surface、controlOutline | 適度邊框 | 2px focus | 保留輸入與清除 | error 文字與語意 |
| Auth buttons | Google 官方資產/Apple 官方元件 | 官方狀態 | 可見焦點 | busy 不重覆請求 | provider 未配置才 disabled |

圖示統一線性風格，常用 20、主播放 24；可採單一有授權的 icon family，保留 Semantics/Tooltip，不以 Unicode 模擬圖示。按鈕、輸入、選單、滑桿優先保留 Flutter 原生可操作元件並透過 Theme/style 客製，不為視覺重寫其互動。Google/Apple 登入品牌圖示與按鈕不套品牌色硬改。

## 5. Subtitle / word interaction
- 當前 cue 和 playing 是兩個狀態：當前已暫停仍保留高亮，圖示為播放；其他句點播放跳至該句，現有 mode 不被視覺改版重設。重播只保留在 transport。
- 精聽 blind→English→bilingual 的遮蔽契約不變；單句翻譯 toggle 不 seek、不 pause、不透露精聽答案。收藏單字依現有正規化完整詞匹配，不導入詞形還原；單字查詢、發音、原句片段、唯讀限制保持。
- 保留 player.subtitle_style.v1 舊資料、範圍、預設和 reset。translationOpacity 原始偏好不更改；在實際背景上先求合成色對比，若 <4.5:1，將有效 alpha 提升至最小通過值（以實際顏色及背景計算；預覽使用同一演算法）；提示「已依可讀性調整」，不要聲稱 50% 就一定以 50% 呈現。金色高亮用 onWordHighlight。
- 回到播放位置應在手動停止跟隨且當前 cue 不在可視範圍時顯示，避免遮擋正文；已實作可視範圍檢查；仍需在實際平台確認邊界情形，不重寫播放時序。
- 不自動翻譯或覆寫任何教材、SRT、收藏內容。

## 6. Accessibility / QA
WCAG 2.2 AA 作為色彩設計基準（不是已通過完整 WCAG 或 App Store 認證）。普通文字 >=4.5:1，必要控制圖示/邊界 >=3:1；不以顏色獨立表達狀態。以 Flutter 48×48 共通目標覆蓋 Android 48dp 與 iOS 44pt 建議。
- 實測 320、390、600、900、1280 logical px，TextScaler 1.0/1.3/2.0，明暗及長英文/繁中、缺翻譯、無字幕、字典多詞義、同步錯誤、唯讀帳號、空清單。鍵盤 Tab、Shift+Tab、Space、Esc、A/S/D、方向鍵不得搶文字輸入焦點。
- Flutter Accessibility Guideline API（androidTapTargetGuideline、iOSTapTargetGuideline、labeledTapTargetGuideline、textContrastGuideline）搭配 Widget Test、Golden Test（固定測試字型/DPR）、VoiceOver/TalkBack、Web 鍵盤及 macOS 實機；golden 不替代行為測試。
- 對比審查：light/dark primary text/background 12.83/13.80；secondary/background 5.44/8.39；secondary/active 4.98/6.04；onPrimary/primary 6.85/8.14；onWordHighlight/wordHighlight 9.99/8.07；controlOutline/active 3.40/3.11。50% alpha secondary/background 2.06/3.15，不通過。實作後需重驗 overlay、composited color、所有實際狀態。

## 7. Phase 5–7 實作順序（WP-22）
1. Design foundation：lib/core/design_system/ 下 editorial_theme、editorial_tokens、editorial_typography、theme_preference；native/web 共用入口；裝置主題持久化；字型授權/離線資產驗證。
2. 共用元件：icon button、button、segmented language control、list row、slider、dialog、focus states；ThemeExtensions 與可操作語意。避免複製同一套元件到各平台。
3. 先 Player + Dictionary（核心）、再 Library/WordBank/Bookmarks、最後 Settings/Auth/Sync/Folder screens。每階段保留功能，先 Widget regression 再視覺驗收。
4. 全四平台驗收，依 docs/08 既有 Gate 與 WP-17 檢查；不能把未測實機標 PASS。
5. Figma Phase 4 尚無 dark variables/component variants 實體寫入證據；額度恢復再同步 token、元件及實際渲染。Phase 3 尚未全面視覺驗收。Figma 示意稿不是完整功能清單。

## 8. 實作對照與維護
- `EditorialTheme.light/dark`：原生與 Web MaterialApp 共用。Theme styles 集中處理按鈕、Card、ListTile、Input、Slider、Dialog、Sheet、PopupMenu；`EditorialLanguageControl`、`EditorialListRow`、`EditorialPageHeading` 為可直接重用的元件。
- `EditorialColors`、`EditorialSpacing`、`EditorialRadius`、`EditorialSize`、`EditorialTypography` 為 Flutter 實作來源；JSON 是對照規範。改動色彩須同步 `test/core/design_system/editorial_theme_test.dart` 驗證。
- 主題切換入口：設定與來源管理、同步帳號／Web 帳號；字型授權入口：設定與來源管理／Web 帳號。單字庫提供單字與詞義搜尋。
- 保留字幕設定 key、原始 SRT、所有音訊與資料模型；翻譯不透明度透過 readableTranslation 依實際背景合成，保存原偏好不變。
- 目前兩張實際 Flutter Golden：`test/features/player/goldens/editorial_desktop_light.png` 與 `editorial_mobile_dark.png`。Golden 不是 Figma 截圖，也不代表全頁面視覺或完整平台驗收。
- 元件狀態與無障礙矩陣為持續驗收契約；尚未逐一證明所有 Focus、Hover、可讀性與螢幕閱讀器情境。不得把本文件列出的目標當作全部實作已通過的證明。

## 9. 官方依據
- W3C WCAG 2.2: https://www.w3.org/TR/WCAG22/
- W3C Contrast Minimum: https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
- W3C Non-text Contrast: https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html
- Flutter UI accessibility: https://docs.flutter.dev/ui/accessibility/ui-design-and-styling
- Flutter Accessibility testing: https://docs.flutter.dev/ui/accessibility/accessibility-testing
- Flutter Adaptive input: https://docs.flutter.dev/ui/adaptive-responsive/input
- Apple HIG accessibility: https://developer.apple.com/design/human-interface-guidelines/accessibility
