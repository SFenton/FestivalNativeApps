# Workflow router

> **What:** how agents work in this repo. **Read when:** starting any lane task or editing docs.

| File | Read when |
|---|---|
| [lanes.md](lanes.md) | You are a lane: ownership, worktrees, integrating, simulator access |
| [simulator-driver.md](simulator-driver.md) | Scripting taps/swipes/scrolls/screenshots on the simulator (`tools/ios_sim.py drive`) |
| [change-loop.md](change-loop.md) | Implementing any feature: the per-change steps |
| [source-of-truth.md](source-of-truth.md) | Reading the web source, citing lines, pinning snapshots, parity backlog |
| [docs-conventions.md](docs-conventions.md) | Adding or splitting `.agents` docs |
| [release-machine.md](release-machine.md) | CI checks, the iOS App Store Connect build/submit tooling, release credentials and enabling other platforms |
| [windows-relay.md](windows-relay.md) | Running Android/Windows lanes on `sfenton-music` and moving their history via `tools/win_relay.py` |
| [android-windows-backlog.md](android-windows-backlog.md) | Queued Android/Windows work while the Windows host is reserved |
| [backlog-android.md](backlog-android.md) | Android-only queue |
| [backlog-windows.md](backlog-windows.md) | Windows-only queue |

Plan, lane table and priorities live in [PROGRESS.md](../../PROGRESS.md) (orchestrator-owned).
