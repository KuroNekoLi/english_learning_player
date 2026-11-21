# English Learning Player

Flutter 語言學習播放器，正式支援目標為 Android、iOS、macOS、Web。核心功能包含 M4A／MP3、中英 SRT、逐句精聽及跨裝置進度。macOS 提供 iCloud Drive 授權資料夾匯入。

原生版本已有本機匯入與精聽功能；跨裝置與真機驗收見工程文件。Web 實作與發布驗收由 [WP-17](docs/14-web-platform.md) 追蹤。需求、架構與工作包請從 [docs/README.md](docs/README.md) 開始；Agent 先讀 [AGENTS.md](AGENTS.md)。

## 本機命令
```sh
flutter pub get
flutter analyze
flutter test
flutter run -d macos
```
Android／iOS 執行時改用對應已連線的裝置。本機學習可離線使用；登入與同步需對應的 Firebase 環境。設定方式見 [WP-14 登入補件](docs/agent/wp-14-social-sign-in.md)。

## Coding Agents
- 模型分工：[docs/09-four-stage-execution.md](docs/09-four-stage-execution.md)
- 可貼上的 Prompt：[docs/10-agent-prompts.md](docs/10-agent-prompts.md)
- 各工作包驗收：[docs/11-work-packages.md](docs/11-work-packages.md)
- 官方 Flutter/Dart Skills 與更新方式：[docs/13-skills-and-sources.md](docs/13-skills-and-sources.md)
