# English Learning Player

Flutter 語言學習播放器：Android、iOS、macOS；M4A/MP3 與中英 SRT；逐句精聽、跨裝置進度，以及 macOS iCloud Drive 授權資料夾匯入（規劃中）。

**目前狀態：** Flutter 官方樣板已建立；產品功能尚未實作。需求、架構、四階段模型分工與工作包請從 [docs/README.md](docs/README.md) 開始；Agent 先讀 [AGENTS.md](AGENTS.md)。

## 本機命令
```sh
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```
Android/iOS 執行時改用對應已連線的裝置；Firebase 與 iCloud 尚未接線，不需先建立雲端資源。

## Coding Agents
- 模型分工：[docs/09-four-stage-execution.md](docs/09-four-stage-execution.md)
- 可貼上的 Prompt：[docs/10-agent-prompts.md](docs/10-agent-prompts.md)
- 各工作包驗收：[docs/11-work-packages.md](docs/11-work-packages.md)
- 官方 Flutter/Dart Skills 與更新方式：[docs/13-skills-and-sources.md](docs/13-skills-and-sources.md)
