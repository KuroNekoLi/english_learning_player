# Flutter / Dart Agent Skills：來源、安裝、更新與覆寫

## 1. 使用已確認的官方來源
- Flutter 團隊：<https://github.com/flutter/agent-plugins>，本次複製版本 commit `b7d5a0b`。
- Dart 團隊：<https://github.com/dart-lang/skills>，本次複製版本 commit `fa69167`。
- Flutter 官方 AI 工具說明：<https://docs.flutter.dev/ai/tools>。
- Flutter 官方架構：<https://docs.flutter.dev/app-architecture/guide> 與 <https://docs.flutter.dev/app-architecture/recommendations>。
- Codex Skills 位置：<https://learn.chatgpt.com/docs/build-skills>（Repo `.agents/skills/<name>/SKILL.md`）。

已安裝至儲存庫的官方 Skills：
| Skill | 用途 / 觸發任務 |
|---|---|
| `flutter-apply-architecture-best-practices` | 分層、依賴方向、Repository/ViewModel |
| `flutter-build-responsive-layout` | 手機與 Mac 的 RWD |
| `flutter-add-widget-test` | WidgetTester 測試 |
| `flutter-setup-declarative-routing` | go_router 導航 |
| `dart-add-unit-test` | Domain / Repository Unit Test |
| `dart-run-static-analysis` | 靜態檢查與修正 |
| `dart-resolve-package-conflicts` | 套件版本相容性 |

這些 `SKILL.md` 與其各自資源內容沿用官方版本（只清除行尾空白以通過 Git 檢查），非本專案自創的官方規範；原始授權條款副本放在 `docs/agent/flutter-agent-plugins-LICENSE`、`docs/agent/dart-skills-LICENSE`。如要移植或修改，保留出處與授權。

## 2. 專案專用 Skill
`.agents/skills/english-learning-player-engineering/SKILL.md` 定義播放器、字幕、同步、原生權限與交棒流程。與官方 Skill 衝突時：保留官方分層原則，但此專案既有決策（Riverpod、audio engine、outbox、Swift gateway）優先；不得偷偷改寫官方 Skill 以掩蓋差異。

## 3. 為什麼沒有安裝某些官方 Skill
當前 Flutter repo 的 `flutter-add-integration-test` 範例含 legacy `enableFlutterDriverExtension()` 步驟；本專案統一依當前 Flutter `integration_test` 官方指南，避免對新專案誤加舊式 Driver extension。因此不把該 Skill 複製進 repo。

## 4. 使用和升級方式
`cd /Users/linli/AndroidStudioProjects/english_learning_player`；在 Codex 中查閱 `/skills` 或輸入 `$flutter-apply-architecture-best-practices`。如工具支援 implicit match，當任務符合 description 時也可自動載入。
未來可以透過 Flutter 官方推薦的 Plugin 安裝法（Codex `codex plugin marketplace add flutter/agent-plugins`、`codex plugin add dart-flutter@dart-flutter`）使用全域技能，但不要同時維持彼此衝突的兩套規則而不說明。
若需更新 project vendored Skills：取官方最新 commit、檢查差異及授權，再逐一替換，跑一次 Skill frontmatter 與連結檢查，最後獨立 commit；不可自動覆蓋專案 `AGENTS.md`。

## 5. 規格引用來源
- `just_audio` 音訊 API：<https://pub.dev/packages/just_audio>
- `audio_service`：<https://pub.dev/packages/audio_service>
- `audio_session`：<https://pub.dev/packages/audio_session>
- FlutterFire：<https://firebase.flutter.dev/>（實際版本/平台支援依 <https://firebase.google.com/docs/flutter/setup> 驗證）
- Firestore Offline：<https://firebase.google.com/docs/firestore/manage-data/enable-offline>
- Apple Security Scoped Bookmarks / NSFileCoordinator：<https://developer.apple.com/documentation/foundation/>
- Flutter testing：<https://docs.flutter.dev/testing>

除明確標記為已實作的依賴外，文中套件名是規劃選項，不表示已安裝或已驗證在本機 SDK 可運作。WP-04 已安裝 `just_audio 0.10.6` 與 `audio_session 0.1.25`；版本與本機 build 證據見 lockfile 及 [WP-04 交棒](agent/wp-04-handoff.md)。
