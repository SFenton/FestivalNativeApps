# Festival Native Apps — Plan & Progress

Single source of truth for **what is being built, by whom, in which order**. Update the lane table and log whenever a lane lands work on `master`. Detailed per-route gaps stay in `contracts/parity-backlog.json` (`python3 tools/parity_backlog.py --list`).

_Last updated: 2026-09-27 · Orchestrator: Claude Opus 5.5 (Claude Code) · took over from Copilot CLI (GPT-6 Sol) session `215f6b3e` at `05aaaeb`._

---

## 1. Operating model (changed 2026-09-27)

| Before (Copilot) | Now |
|---|---|
| One agent, strictly sequential | **Orchestrator + parallel lanes**, each in its own git worktree |
| Tandem research (Sol + Opus) for every page/control | Opus researches and decides; lanes implement. No tandem passes. |
| Full device matrices + coverage gates on every slice | **Tests phased by maturity** (see §3). During feature build: unit tests + quick screenshots only. |
| Offline/warm-cache disclosure UX | **Online-only for now.** Keep in-process caches for speed; no offline UX. |
| Leaderboards "blocked" by Cloudflare 1010 | Re-probed 2026-09-27: `/api/rankings/*` returns **200** for native-style requests. Unblocked. |

### Lanes and file ownership

Parallel work is safe because **every lane owns a disjoint set of folders**. A lane may *read* anything but only *edit* what it owns. Shared seams (`AppRoute`, `AppRouteDestination`, `Design/`, `Package.swift`, `project.yml`) are orchestrator-owned — ask in your final report if you need a change there.

```
apple/Sources/FestivalUI/
  App/            AppRoute, AppRouteDestination, FestivalTabStack   → orchestrator
                  FestivalRootView, SongNavigationRoot, Shell/*     → Lane A (Shell)
                  FestivalSession.swift                             → Lane P (Profile); others add FestivalSession+<Feature>.swift
  Design/         GlassSurface, SectionHeader, InstrumentIcon       → orchestrator (Lane A may add new files)
  Background/     everything                                        → Lane B (Background)
  Common/         status views, ComingSoonView                      → Lane A
  Features/Songs, SongDetail, Shop                                  → Lane S (Songs)
  Features/Profile                                                  → Lane P (Profile)
  Features/Leaderboards, SongLeaderboard                            → Lane L (Leaderboards)
  Features/Settings                                                 → Lane A
  Features/Rivals, Statistics, Suggestions, Compete, Bands  → Wave 2 lanes
apple/Sources/FestivalCore/   new domain files per lane (FestivalAPI+<Domain>.swift); edit an existing file only if your lane owns that domain
apple/Tests/**                tests for your own files only
apple/Apps/iOSUITests/**      frozen during Wave 1 (UX tests come at feature completion)
.agents/**                    → Lane D (Docs) restructures; other lanes only ADD new files under .agents/pages/<page>/ or .agents/controls/<control>/
tools/**                      → orchestrator
```

### Integration protocol

1. Lanes commit small, cohesive commits on their worktree branch (`lane/<name>`).
2. `tools/lane_integrate.sh` fetches, rebases onto `origin/master`, runs `swift build --build-tests` + the iOS build, pushes `HEAD:master`, and retries if another lane landed first. `--test` also runs `swift test`.
3. Simulator access **only** through `tools/ios_sim.py shot …` (global `flock`; one simulator at a time). Deep-link with `--tab`/`--route` (see `DebugLaunchRoute` in `FestivalRootView.swift`).
4. Lanes report back: what landed (SHAs), screenshots taken, open issues, seam changes needed.

---

## 2. Priorities (from operator, 2026-09-27)

1. **Liquid Glass & native navigation components**, plus docs/agent updates.
2. **Instrument features and missing pages** — UX match to web, Apple HIG first, Fluent second.
3. **Profile pages** (selected and unselected) → other missing pages → refinement. *Features first, then full UX parity.*
4. **Shared animated background & seamless transitions.**
5. Testing phases: unit tests as we go → UX tests when a *feature* is complete → accessibility tests when the *app* is complete → VoiceOver testing after that.

Platform order: **iPhone (iOS 26.5) → iPhone Duo → iPadOS → macOS → iPhone on iOS 17 (no Liquid Glass)**. Android/Windows remain in scope; the Windows host is paused by the operator — do not reconnect.

---

## 3. Testing phases

| Phase | When | What |
|---|---|---|
| **Build** | Every commit | `swift build --build-tests`, iOS build (via `lane_integrate.sh`) |
| **Unit** | As we go | Swift Testing for new Core logic (target 95% non-UX); run only new/changed tests while iterating |
| **Visual smoke** | While building UI | `tools/ios_sim.py shot` screenshots compared to the web app at the same viewport |
| **UX tests** | Feature complete | XCUITest journeys + hosted snapshot states per control (target 90% UX coverage) |
| **Accessibility** | App complete (per platform) | Audits, focus order, Dynamic Type, contrast, in-app a11y toggles |
| **VoiceOver** | After accessibility | Scripted VoiceOver walkthroughs per page |

---

## 4. Work breakdown

Legend: ⬜ not started · 🟨 in progress · ✅ landed · ⛔ blocked

### Wave 0 — Foundation (orchestrator)
- ✅ Split `SongScreens.swift` into feature folders; add `AppRoute` for all 24 web routes, `AppRouteDestination`, `FestivalTabStack`, placeholder screens (`9a5754a`)
- ✅ Shared design primitives: `festivalGlass` (Liquid Glass + pre-26 fallback), `FestivalSectionHeader`, `InstrumentIcon` + bundled icons
- ✅ Deployment targets iOS 17 / macOS 14
- ✅ `tools/ios_sim.py` (serialized sim + deep links), `tools/lane_integrate.sh`, `FestivalBackgroundHost` seam (`2ff8338`), `festivalRootChrome` seam (`915fde4`)

### Wave 1 — parallel lanes (iPhone, iOS 26.5)

**Lane A — Shell & Liquid Glass chrome** (Opus) — ✅ landed `4b1f11c`…`0f4ebd9`
- ✅ Conditional tabs mirroring web `BottomNav`: Songs · Suggestions* · Leaderboards / Compete* · Statistics* · Settings (*when a profile is selected)
- ✅ Profile button **top-right** on every tab root (notifications slot reserved beside it)
- ✅ Apple-style hamburger drawer (leading) with expanded options — Item Shop, Bands, Rivals, Manual, Licenses, profile-specific actions
- ✅ Liquid Glass judgment pass → `.agents/design/apple/liquid-glass.md`; apply to Settings sections and other glass containers
- ✅ Modals: dark glass backgrounds, native sheet detents, Title Case white section headers (`festivalSheet` style)
- ✅ Settings persist across cold starts (verify every setting)

  - Follow-ups: drawer swipe/VoiceOver dismissal and tab re-tap untested (no tap tooling → Lane T); band tab rules unit-tested only

**Lane S — Songs, Song Detail, Shop** (Sonnet) — ✅ landed …`eaecd6c` (follow-up running: scrubber `#` labels, keyboard icons)
- ✅ Native toolbar controls on Liquid Glass nav bar: search, sort, filter (Item Shop button removed → drawer)
- ✅ Song rows as Liquid Glass; tighten row spacing to match web
- ✅ Instrument icons inside the instrument status circles
- ✅ Right-side section index scrubber for Title/Artist/Year sorts; animate out for sorts where it doesn't make sense
- ✅ Instrument selection moved into Filter (only when a profile is selected), like web
- ✅ Search pill to native iOS standard; decide chevrons (HIG: no disclosure chevrons inside card rows)
- ✅ Song Detail: intensity card uses instrument icons instead of text
- ✅ Remove offline/warm-cache disclosure UI (online-only)

**Lane P — Profile + Statistics tab** (Sonnet) — ✅ landed `4f3dfae`, `8324dc2`, `3eba1af`
- ⬜ Fix: selected profile survives app close / cold start
- ✅ Player profile page `/player/:accountId` — viewed (unselected) and selected states, select/deselect action
- ✅ Profile selection sheet redesign: native, dark glass, "Find Player"/"Find Band", centered "Enter at least…" hint, Title Case headers

**Lane L — Leaderboards** (Sonnet) — ✅ landed `f50dce9`…`65e8607`
- ⬜ Leaderboards overview: top-10 cards per visible instrument (+ band types), metric picker
- ✅ Full rankings (paginated) and band rankings
- ✅ Song leaderboard page native navigation pass; rows navigate to player profile

**Lane B — Shared background & transitions** (Opus) — ✅ landed `8cd7f00`…`47345fa`
- ⬜ One animated background hosted by the shell — no restart/jitter across tabs or pushes; Item Shop uses the same one
- ✅ Song Detail: animate from the carousel to that song's album art, hold still; animate back on pop/tab change
- ✅ Carousel loads independently of the Songs tab

**Lane D — Agent docs architecture** (Opus) — ✅ landed `7c8b6eb`…`0b01884`
- ✅ Split every multi-platform doc by platform, then form factor (`.agents/<area>/<topic>/{spec,ios,ipados,duo,macos,android,windows}.md`)
- ✅ Router tables with direct pointers at every level; workflow docs for the lane model
- ✅ Remove tandem-research requirements; encode testing phases

### Wave 2 — remaining pages

**Lane T — Simulator driver tooling** (Sonnet) — ✅ landed `8d8a6ac`
- ✅ `ios_sim.py drive`: scripted tap/swipe/type/scroll/screenshot/accessibility-tree via an XCUITest driver, under the simulator lock

**Lane R — Rivals & Compete** (Sonnet) — ✅ landed `6bfa5da`…`8a3ab84`
- ✅ Compete hub · ✅ Rivals hub · ✅ All rivals · ✅ Rival detail · ✅ Rivalry (read-only endpoints verified)

**Lane G — Suggestions** (Sonnet) — 🟨 running in `~/repos/FestivalNativeApps-lanes/suggestions`
- ⬜ Port suggestion algorithms to Core (unit-tested) · ⬜ Suggestions screen + filter sheet

**Lane N — Bands** (Sonnet) — ✅ landed `917ada3`…`7d91e9d`
- ✅ Band detail (members + instruments, summary, statistics, rank history, best/worst songs) · ✅ Player bands (All/Duos/Trios/Quads, paginated) · ✅ Bands landing (no band search — it writes; shows selected player's bands + Band Rankings links) · ✅ Per-song band leaderboard (paginated, in-place band-size switcher)
- **New finding:** `/api/bands/{bandId}` (the web's Band Detail source) also writes on a GET — `GetBandConfigurations` → `EnsureBandTeamConfigurations` rebuilds `band_team_configurations` on a cache miss (`GlobalLeaderboardPersistence.cs:4192-4206`). Not yet in `service-safety.md`'s table; treated as blocked like band search/sync-status. Band Detail instead reads `GET /api/rankings/bands/{bandType}?teamKey=` (confirmed pure), which already returns `members[].instruments` and (Duos+combo only) `configurations`. Consequence: `bandId` is a one-way hash (`BandIdentity.CreateBandId`), so a bare `bandId` link can't be resolved without `bandType`/`teamKey` carried from the originating row — `AppRoute.band` gained additive optional `bandType`/`teamKey` for this; a bare-`bandId` link (e.g. a future universal link) shows an explicit "open from a band list" state.
- Minimal additive edit to Leaderboards' `RankingsSupport.swift`/`LeaderboardsScreen.swift`/`BandRankingsScreen.swift`: `BandRankingRow` now also passes `bandType`/`teamKey` so its existing `.band` links resolve to full detail instead of the fallback state.
- Simplified vs. web: no instrument-combo filter/picker, no rank-history chart (list of recent snapshots instead), best/worst songs show raw `songId` (no catalog title cross-reference).
- `service-safety.md`'s endpoint table needs a `/api/bands/{bandId}` blocked row (Lane D/orchestrator; this lane only adds new `.agents/pages/*` files per lane rules).

**Lane M — Settings completion, Licenses** (Sonnet) — 🟨 running in `~/repos/FestivalNativeApps-lanes/settings`
- ⬜ Every web Settings section · ⬜ Licenses

**Lane X — Player history, notifications** (Sonnet) — ✅ landed `1f31d52`, `01c0aca`, `8bfc96a`
- ✅ Player history (sort sheet, Swift Charts line) · ✅ Notifications sheet + bell (unread dot, seen state, deep links)
  - Follow-up (Lane S): entry points to Player History from Song Detail / solo leaderboard
  - Simplified: notification copy covers player-scoped kinds only (no band kinds / coalescing)

**Lane F — First-run experiences (FREs)** (Sonnet) — 🟨 running in `~/repos/FestivalNativeApps-lanes/firstrun`
- ⬜ Core seen-state store: per-slide `{version, hash, seenAt}`; show **only unseen, gate-passing slides** (new info without replaying old)
- ⬜ Native glass carousel + per-page slides/demos (songs, suggestions, player, song info, compete, rivals, shop, leaderboards)
- ⬜ Settings: view again per page (all slides), reset, enable toggle · ⬜ Applied app-wide via one route/tab seam

**Lane Q — Quick Links** (Opus) — 🟨 running in `~/repos/FestivalNativeApps-lanes/quicklinks`
- ⬜ Feasibility + native design decision (HIG + Fluent) → `.agents/controls/quick-links/` · ⬜ Reusable `Common/QuickLinks` API (toolbar jump menu, active section, VoiceOver rotor) · ⬜ Adopt on Leaderboards
- ⬜ Adoption on Songs, Song Detail, Player/Statistics, Band, Compete, Rivals, Rivalry, Rival Detail, Settings — handed to owning lanes as they finish

Queued (start when load allows):
- ⬜ **Profile follow-up:** global ranks/percentiles on the profile page via `GET /api/rankings/{instrument}/{accountId}` (pure read, verified) instead of the forbidden player-stats GET; profile sheet should dismiss and push on the presenting tab rather than push inside the sheet; `FST_DEBUG_PROFILE` should not persist selection (lanes clobber each other on the shared simulator)
- ⬜ **Rivals follow-up:** replace `RivalNavigationBridge` global singleton with scope carried in `AppRoute` payloads (deep-link/state-restoration safe); cross-instrument combo / common rivals; Find Rival search
- ⬜ **Wave 3 UX tests** for completed features (shell/drawer/tabs, leaderboards, background, history, notifications, rivals) — hosted snapshots first, XCUITest journeys batched to limit simulator contention

Not yet assigned:
- ⬜ Statistics = selected player's profile page (assigned to Lane P)
- (none — Wave 2 fully assigned)

### Wave 3 — quality gates (iPhone)
- ⬜ UX tests per completed feature (XCUITest + hosted snapshots, ≥90% UX coverage)
- ⬜ Unit coverage ≥95% non-UX
- ⬜ Accessibility pass (whole app) · ⬜ VoiceOver pass

### Wave 4+ — other form factors
- ⬜ iPhone Duo bespoke layout (folded/unfolded, outer rotations) · ⬜ iPadOS · ⬜ macOS · ⬜ iPhone iOS 17 classic tab bar
- ⛔ Android / Windows (Windows host paused by operator)

---

## 5. Known issues / decisions

- **Rivals detail endpoints** (`/rivals/{combo}/{rivalId}`, `/leaderboard-rivals/{instrument}/{rivalId}`) returned 503 "not yet published" for the sample account during development; the app shows an explicit unavailable state. Re-check later.
- **Load ceiling:** ~9 concurrent lanes pushed load to 170+ on the 10-core Mac; don't add lanes above ~100 load.

- **Simulator queue stall (fixed `c3b55f3`):** XCUITest waits for app idle before each action; the always-animating carousel never idles, so a 10-step `drive` held the sim lock 8+ min with 7 jobs queued. `drive` now sets `FST_DEBUG_STILL_BACKGROUND=1` by default (`--animate` opts out) and enforces `--timeout` (180 s).

- **Manual is deprecated** (operator, 2026-09-27): not ported. Route, drawer item, placeholder screen, contract entries and docs removed.

- **Leaderboards follow-ups:** no "your rank" spotlight row, no rank-history chart, no band-combo filter on the overview; per-card loads are sequential.
- **Background follow-ups:** the brief's plan of drawing once behind transparent pages failed (the iPhone TabView keeps an opaque layer over anything drawn behind it), so each page draws a synced mirror of one shared state. Open issues: a cancelled swipe-back on pages without a `visible` flag briefly fades; going back fades rather than shrinking the art into its tile; the tap-and-push flow is unverified.

- **Build contention:** 7 lanes on a 10-core Mac hit load 169; SwiftPM builds are serialized via `~/.fst-build.lock` (Lane T adding it to `ios_sim.py build`). Keep ≤7 concurrent lanes.
- **Test-ID families** are registered per page in `contracts/product.json` (`fst.<page>.*`), so new controls don't need registry edits.

- **Live service:** rankings, songs, account search and `/leaderboard/{song}/all` return 200 keyless to native user agents (re-probed 2026-09-27; see `.agents/platforms/service-safety.md`). Keep the no-`X-API-Key` and no-side-effect-endpoint rules from `AGENTS.md`.
- **Instrument icons** are copied from the web app's `public/instruments/` (the operator's own site), downscaled to 144 px.
- **iOS 17 runtime** is not installed on this Mac; iOS 17 is compile-checked only until Wave 4.

---

## 6. Log

| When (PT) | Lane | Change |
|---|---|---|
| 2026-09-27 | Orchestrator | Read Copilot history (11 checkpoints, 7 operator messages); designed lane model; landed foundation `9a5754a` |
| 2026-09-27 | Orchestrator | Launched Wave 1 lanes A, S, P, L, B, D in parallel worktrees |
| 2026-09-27 | Lane A | Landed tabs, root chrome, drawer, Liquid Glass doc, Settings glass, festivalSheet, settings persistence |
| 2026-09-27 | Orchestrator | Launched Lanes T (sim driver), R (Rivals/Compete), G (Suggestions); Statistics folded into Lane P |
| 2026-09-27 | Lane D | `.agents` split by platform/form factor, routers, `check_docs.py` (CI-enforced), single `service-safety.md` |
| 2026-09-27 | Orchestrator | Unblocked public reads (`b17eac2`), per-page test-ID families, serialized builds (`c972417`) |
| 2026-09-27 | Lane L | Leaderboards overview, full/band rankings, native song leaderboard with rows → player |
| 2026-09-27 | Lane B | Shared synced background, song-art zoom transitions, ~4.4% CPU animating / 0% held |
| 2026-09-27 | Orchestrator | Launched Lanes N (Bands), M (Settings/Manual/Licenses); Remote Control enabled for this session |
| 2026-09-27 | Lane T | `ios_sim.py drive` — scripted tap/swipe/type/tree/screenshot via XCUITest driver (~11–24 s/run); build lock |
| 2026-09-27 | Orchestrator | Launched Lane X (history, first-run, notifications) |
| 2026-09-27 | Orchestrator | Dropped deprecated Manual (route, drawer item, contracts, docs) per operator |
| 2026-09-27 | Orchestrator | Split FREs into dedicated Lane F per operator (versioned/hashed seen state, replay settings) |
| 2026-09-27 | Orchestrator | Launched Lane Q (Quick Links) per operator |
| 2026-09-27 | Orchestrator | Unstuck simulator queue: frozen carousel for drives + drive timeout (`c3b55f3`) |
| 2026-09-28 | Lane S | Native toolbar search/sort/filter, glass rows, instrument-icon chips, A–Z scrubber, instrument filter moved to Filter, icon intensity card, offline banners removed |
| 2026-09-28 | Lane X | Player history + notifications (read-only endpoints verified); FirstRun types handed to Lane F |
| 2026-09-28 | Lane R | Compete hub, Rivals hub/all/detail/rivalry; 18 tests; combos + Find Rival deferred |
| 2026-09-28 | Lane P | Fixed profile persistence (tautological publication check after relaunch); player profile page shared with Statistics tab; native profile sheet |
| 2026-09-28 | Lane N | Bands landing, Band Detail, Player Bands, Song Band Leaderboard; found `/api/bands/{bandId}` also writes on a GET (treated as blocked, band detail reads the rankings board by `teamKey` instead); `AppRoute.band` gained additive `bandType`/`teamKey` |
