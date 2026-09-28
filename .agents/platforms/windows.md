# Windows architecture and performance

> **What:** WinUI 3 architecture and game-alongside performance rules. **Read when:** working on the Windows app (host `sfenton-primary`, reached via [windows-relay](../workflow/windows-relay.md)). Design: [design/windows.md](../design/windows.md); tests: [testing/windows.md](../testing/windows.md).

- C#/.NET + WinUI 3 (Windows App SDK), `NavigationView`, virtualized lists, testable view models, composition-thread animations. [Microsoft recommends WinUI 3](https://learn.microsoft.com/en-us/windows/apps/get-started/) for new native desktop apps.
- **C# vs C++/WinRT is provisional** until the same Release screen is profiled with artwork motion, a large list and a modal beside a representative game: measure app and game CPU/GPU, memory, startup, GC/frame delivery and responsiveness. Don't adopt invented startup/memory limits or assume a notification-state API recognizes every game.
- Don't disable background visuals just because focus moves to a game (the app may stay visible beside it); use data-saving/reduced-motion and measured occlusion policies.
- Tooling on `sfenton-primary` (verified 2026-09-28): Windows SDK 10.0.22621 + 10.0.26100, Visual Studio 2022 + 2019 Community, .NET SDK 8.0.417 / 9.0.304, Claude Code 2.1.283. No GitHub credentials over SSH; history moves via `tools/win_relay.py`.
