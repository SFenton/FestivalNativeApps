# Lanes, worktrees and integration

> **What:** the parallel-lane operating model (since 2026-09-27). **Read when:** you are a lane agent, before your first edit. Ownership table: [PROGRESS.md §1](../../PROGRESS.md).

## Model

- Opus 5.5 orchestrates and is the sole researcher. **No tandem research/review passes.** Lanes implement.
- Each lane works in its own git worktree (`../FestivalNativeApps-lanes/<lane>`, branch `lane/<lane>`) and **edits only folders it owns**; it may read anything.
- Shared seams (`AppRoute`, `AppRouteDestination`, `FestivalTabStack`, `Design/`, `Package.swift`, `project.yml`, `tools/**`) are orchestrator-owned: request changes in your final report.
- `.agents/**` is owned by the Docs lane; other lanes may only **add** `pages/<id>/<platform>.md`, `controls/<id>/<platform>.md` or `design/apple/*.md`, then run `python3 .agents/_tools/check_docs.py --fix`.

## Commands

| Need | Command |
|---|---|
| Build iOS app for this worktree | `python3 tools/ios_sim.py build` |
| Screenshot a tab/route (takes the global sim lock) | `python3 tools/ios_sim.py shot --out /tmp/x.png --tab leaderboards` / `--route player:<id>` / `--device ipad` |
| Integrate to `master` (rebase, `swift build --build-tests`, iOS build, push, retry ×5) | `tools/lane_integrate.sh` (`--test` also runs `swift test`) |
| Check docs structure | `python3 .agents/_tools/check_docs.py` |

Debug deep links: `FST_DEBUG_TAB` / `FST_DEBUG_ROUTE` are parsed by `DebugLaunchRoute` in `apple/Sources/FestivalUI/App/FestivalRootView.swift` (routes: `player:<id>`, `playerBands:<id>`, `leaderboards`, `fullRankings`, `bandRankings:<type>`, `shop`, `rivals`, `statistics`, `suggestions`, `compete`, `bands`, `band:<id>`, `manual`, `licenses`).

## Rules

- **Never call `simctl` directly** while lanes run; `tools/ios_sim.py` holds `~/.fst-sim.lock`. One product simulator at a time per host; never touch other projects' devices ([simulators](../platforms/apple/simulators.md)).
- Commit small cohesive commits ending with the `Co-Authored-By` trailer; on rebase conflicts keep both sides' intent and never delete another lane's new files.
- Final report: SHAs landed, screenshots taken, open issues, seam changes needed. The orchestrator updates PROGRESS.md.
- PR auto-merge only when the PR author is exactly `SFenton`.
