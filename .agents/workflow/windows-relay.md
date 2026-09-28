# Remote build host relay

> **What:** how Android/Windows work runs on `sfenton-primary` and moves to GitHub. **Read when:** running, collecting or integrating a Windows-host lane.

The Windows host has no working GitHub credentials over SSH, so **this Mac is the only machine that talks to GitHub**. `tools/win_relay.py` moves history as git bundles over `scp`.

| Command (run on the Mac) | Effect |
|---|---|
| `python3 tools/win_relay.py sync` | Ship `origin/master` to Windows (`C:/Users/sfent/workspace/FestivalNativeApps`, `origin` = `relay/master.bundle`) |
| `python3 tools/win_relay.py lane <name>` | Create worktree `C:/Users/sfent/workspace/FestivalNativeApps-lanes/<name>` on branch `lane/<name>` |
| `python3 tools/win_relay.py run <name> <prompt.md>` | Run a headless Claude Code session in that worktree (run it as a background job) |
| `python3 tools/win_relay.py collect <name>` | Fetch `lane/<name>` back to the Mac as `win/<name>` |
| `python3 tools/win_relay.py integrate <name>` | Collect, rebase onto `origin/master`, push, then `sync` |
| `python3 tools/win_relay.py exec "<cmd.exe command>"` | Ad-hoc remote command |

Rules for Windows-host lanes:
- Commit locally on `lane/<name>`; never try to push (no credentials). To pick up new master: `git fetch origin && git rebase origin/master` after the orchestrator runs `sync`.
- Own only `android/**`, `windows/**`, `tools/android/**`, `tools/windows/**` and per-platform docs (`.agents/**/android*.md`, `.agents/**/windows*.md`, `.agents/pages/<page>/{android,windows}.md`). Never edit `apple/**`.
- Run **one Android emulator at a time**; the Windows app itself isn't a simulator.
- Build and tests must pass on Windows before asking the orchestrator to integrate.
