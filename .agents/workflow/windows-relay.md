# Remote build host relay

> **What:** how Android/Windows work runs on `sfenton-primary` and moves to GitHub. **Read when:** running, collecting or integrating a Windows-host lane.

Since 2026-09-28 the Windows host **pushes to GitHub directly** (gh token in `%APPDATA%\GitHub CLI\hosts.yml`, `gh auth setup-git`; the main clone's `origin` is `https://github.com/SFenton/FestivalNativeApps.git`). Lanes there integrate themselves with `tools/git_integrate.py`; the Mac pulls as usual. The bundle relay below remains as a fallback if GitHub auth breaks.

| Command (run on the Mac) | Effect |
|---|---|
| `python3 tools/win_relay.py sync` | Fast-forward the Windows main clone to GitHub `origin/master` (fallback: bundle relay) |
| `python3 tools/win_relay.py lane <name>` | Create worktree `C:/Users/sfent/workspace/FestivalNativeApps-lanes/<name>` on branch `lane/<name>` |
| `python3 tools/win_relay.py launch <name> <prompt.md>` | **Preferred.** Start the lane as a named Remote Control session `FST-<name>` in the operator's desktop session (own console window; visible/steerable in claude.ai/code). The lane writes `relay/status/<name>.done` when finished |
| `python3 tools/win_relay.py wait <name>` | Block until that done marker exists and print the lane's final report (run as a background job for completion notifications) |
| `python3 tools/win_relay.py run <name> <prompt.md>` | Legacy: headless `claude -p` run (not monitorable) |
| `python3 tools/win_relay.py collect <name>` | Fetch `lane/<name>` back to the Mac as `win/<name>` |
| `python3 tools/win_relay.py integrate <name>` | Collect, rebase onto `origin/master`, push, then `sync` |
| `python3 tools/win_relay.py exec "<cmd.exe command>"` | Ad-hoc remote command |

Rules for Windows-host lanes:
- Commit small cohesive commits on `lane/<name>`; when a slice is ready, integrate with `python tools/git_integrate.py --verify "<build+unit tests>"` (fetch → rebase on `origin/master` → verify → push, retries on races). Rebase often (`git fetch origin && git rebase origin/master`).
- Own only `android/**`, `windows/**`, `tools/android/**`, `tools/windows/**` and per-platform docs (`.agents/**/android*.md`, `.agents/**/windows*.md`, `.agents/pages/<page>/{android,windows}.md`). Never edit `apple/**`.
- **Never squash with `git reset --soft origin/master`** (or any reset against `origin/*`): all worktrees share one object store and remote-tracking refs, so another lane's fetch moves `origin/master` and a soft reset silently pulls their commits into your diff as reversals (near miss 2026-09-28). Squash with `git rebase` onto the merge base, or just keep small commits; before pushing, check `git diff origin/master --stat` touches only your folders.
- **Never use `git stash` in a worktree** (e.g. for a before/after capture or a baseline test run): `refs/stash` is one stack shared by every worktree, so a parallel worker's push between your `stash push` and `stash pop` swaps your changes with theirs (incident 2026-10-01, issues #18/#23). Keep a baseline with `git worktree add --detach <tmp> HEAD` (remove it afterwards) or `git diff > <tmp>.patch` + `git apply`.
- Run **one Android emulator at a time**; the Windows app itself isn't a simulator.
- Build and tests must pass on Windows before asking the orchestrator to integrate.
- Lane worktrees are created over SSH (owned by Administrators); `lane` resets ownership to `sfent` so git's safe.directory check passes in the desktop session.
