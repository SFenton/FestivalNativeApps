# Apple platforms router

> **What:** SwiftUI app architecture and runtime facts for iPhone, iPad, Duo and Mac. **Read when:** building, running or structuring Apple code.

| File | Read when |
|---|---|
| [architecture.md](architecture.md) | Package/target layout, network client, caches, shared components, performance rules and numbers (`tools/apple_perf.py`) |
| [build-and-run.md](build-and-run.md) | Building, launching against live or fixture service, launch-screen prerequisite |
| [simulators.md](simulators.md) | Which simulator to use and the one-at-a-time rules |
| [duo.md](duo.md) | iPhone Duo simulator/posture facts |
| [macos.md](macos.md) | macOS signing and GUI-automation limits on this host |

Design decisions: [design/apple/](../../design/apple/README.md); HIG lookups go through the installed `apple-hig` skill (route with `python3 ~/.claude/skills/apple-hig/scripts/hig_route.py --request-file <req.txt>`), Duo adaptation through its `/duo` workflow ([AGENTS.md](../../../AGENTS.md)). Tests: [testing/apple/](../../testing/apple/README.md).
