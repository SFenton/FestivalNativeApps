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

**Lane G — Suggestions** (Sonnet) — ✅ landed `36da85d`, `2e76e59`, `1b81517`
- ⬜ Port suggestion algorithms to Core (unit-tested) · ⬜ Suggestions screen + filter sheet

**Lane N — Bands** (Sonnet) — ✅ landed `917ada3`…`7d91e9d`
- ✅ Band detail (members + instruments, summary, statistics, rank history, best/worst songs) · ✅ Player bands (All/Duos/Trios/Quads, paginated) · ✅ Bands landing (no band search — it writes; shows selected player's bands + Band Rankings links) · ✅ Per-song band leaderboard (paginated, in-place band-size switcher)
- **New finding:** `/api/bands/{bandId}` (the web's Band Detail source) also writes on a GET — `GetBandConfigurations` → `EnsureBandTeamConfigurations` rebuilds `band_team_configurations` on a cache miss (`GlobalLeaderboardPersistence.cs:4192-4206`). Not yet in `service-safety.md`'s table; treated as blocked like band search/sync-status. Band Detail instead reads `GET /api/rankings/bands/{bandType}?teamKey=` (confirmed pure), which already returns `members[].instruments` and (Duos+combo only) `configurations`. Consequence: `bandId` is a one-way hash (`BandIdentity.CreateBandId`), so a bare `bandId` link can't be resolved without `bandType`/`teamKey` carried from the originating row — `AppRoute.band` gained additive optional `bandType`/`teamKey` for this; a bare-`bandId` link (e.g. a future universal link) shows an explicit "open from a band list" state.
- Minimal additive edit to Leaderboards' `RankingsSupport.swift`/`LeaderboardsScreen.swift`/`BandRankingsScreen.swift`: `BandRankingRow` now also passes `bandType`/`teamKey` so its existing `.band` links resolve to full detail instead of the fallback state.
- Simplified vs. web: no instrument-combo filter/picker, no rank-history chart (list of recent snapshots instead), best/worst songs show raw `songId` (no catalog title cross-reference).
- `service-safety.md`'s endpoint table needs a `/api/bands/{bandId}` blocked row (Lane D/orchestrator; this lane only adds new `.agents/pages/*` files per lane rules).

**Lane M — Settings completion, Licenses** (Sonnet) — ✅ landed `169f9f3`…`30bf405`
- ⬜ Every web Settings section · ⬜ Licenses

**Lane X — Player history, notifications** (Sonnet) — ✅ landed `1f31d52`, `01c0aca`, `8bfc96a`
- ✅ Player history (sort sheet, Swift Charts line) · ✅ Notifications sheet + bell (unread dot, seen state, deep links)
  - Follow-up (Lane S): entry points to Player History from Song Detail / solo leaderboard
  - Simplified: notification copy covers player-scoped kinds only (no band kinds / coalescing)

**Lane F — First-run experiences (FREs)** (Sonnet) — ✅ landed `1930d0f`, `cbd1d0c`, `fdb1f41`
- ⬜ Core seen-state store: per-slide `{version, hash, seenAt}`; show **only unseen, gate-passing slides** (new info without replaying old)
- ✅ Native glass carousel + per-page slides/demos (songs, suggestions, player, song info, compete, rivals, shop, leaderboards)
- ✅ Settings: view again per page (all slides), reset, enable toggle · ⬜ Applied app-wide via one route/tab seam

**Lane Q — Quick Links** (Opus) — ✅ landed `b68af1d`…`4fa8bd3`
- ⬜ Feasibility + native design decision (HIG + Fluent) → `.agents/controls/quick-links/` · ⬜ Reusable `Common/QuickLinks` API (toolbar jump menu, active section, VoiceOver rotor) · ⬜ Adopt on Leaderboards
- 🟨 Adoption: Songs/Song Detail (Lane S), Player/Statistics/Band/Settings (Lane P2), Compete/Rivals/Rivalry/Rival Detail (Lane R2)

**Lane R2 — Rivals follow-ups** (Sonnet) — ✅ landed 2026-09-28
- ✅ Replaced `RivalNavigationBridge` singleton with typed `RivalScope` carried directly on `AppRoute.allRivals(scope:)`/`.rivalDetail(rivalId:name:scope:)`/`.rivalry(rivalId:mode:name:scope:)` · ✅ Common Rivals (`RivalCommonRivals.intersect`) + cross-instrument Combo/Pro-Drums-family scope (`RivalCombo`), ported to Core with unit tests · ✅ Find Rival (`FindRivalSheet`, reuses the allowlisted account-search GET) · ✅ Quick Links on Compete/Rivals/Rivalry/Rival Detail · ✅ Re-checked rival detail endpoints: live 200 outside an active scrape window; 503 during one now carries `x-fst-public-read-freeze-reason: scrape`

**Lane P2 — Profile / Statistics / Band / Settings follow-ups** (Sonnet) — ✅ landed
- ✅ Global ranks via `GET /api/rankings/{instrument}/{accountId}` (verified pure read; live probe found its own `instrument` field comes back blank, unlike the list endpoint — tolerated) · ✅ Profile sheet dismiss → push on active tab (new `\.openRoute` hook) · ✅ `FST_DEBUG_PROFILE` in-memory only (no more shared-`UserDefaults` clobbering) · ✅ Quick Links on Player/Statistics/Band/Settings (`top-songs`/`refresh-profile-name`/`export` left out — no such sections exist yet) · ✅ Band song rows show catalog titles/artist/art, link to Song Detail
- Found: a custom `@Entry` environment action set by the presenter never actually fires when read from inside `.sheet(isPresented:)` content in this SwiftUI setup (proved via `tools/ios_sim.py drive` — swapped the handler for a visible, already-proven `@State` side effect and it silently never ran, for both the new `\.openRoute` and the pre-existing `\.openDrawer`). Fixed by passing the dismiss-then-push closure directly into `ProfileSelectionSheet`'s init instead of through environment; flagged for other lanes in `.agents/controls/profile-selection/ios.md`

**Lane S follow-ups** — ✅ landed …`bb77ed4`: avatar-rightmost toolbar on Songs, Quick Links on Songs (Duration/Shop sorts) + Song Detail, row visual order + path column order consumers, `Song.maxScores`

**Lane D2 — FRE live demos** (Sonnet) — ✅ landed `789ff77`…`bdcf36e`
- ✅ Live native mini-demos for all 31 non-Songs slides (Song Info 8, Player History 2, Statistics 6, Suggestions 4, Leaderboards 3, Compete 3, Rivals 3, Item Shop 4) — every one of the 42 catalog slides now resolves to a live demo, unit-tested (`FirstRunDemoCoverageTests`)
- New: `firstRunPulse`/`firstRunStagger` reduce-motion-aware helpers, `FirstRunDemoPool` shared static sample data — see `.agents/controls/first-run/ios.md`
- **Open issue (not this lane's files):** launching directly into a non-default tab (e.g. `--tab statistics`/`--tab leaderboards`) with `FST_DEBUG_FIRST_RUN=force` reproducibly shows the first-run sheet chrome (close/skip/done) but with **zero** slides in the `TabView` (`PageIndicator: page 1 of 0`) — confirmed on 5/5 attempts across two pages. `--tab songs` (the default/first tab) shows all 9 slides correctly every time. Suspect a `TabView(selection:)` initial-tab race (transiently rendering the first `ForEach` tab before honoring the debug-selected one) in `FestivalRootView.swift`/`FirstRunModifier.swift`/`FirstRunCarouselView.swift` — none owned by this lane. `FirstRunSlideEvaluator`/`FirstRunCatalog`'s own unit tests all pass, so the slide-selection logic itself is not implicated; screenshots: `/tmp/laneD2/{statistics_a,leaderboards,leaderboards2}.png` + matching `.tree.txt` dumps.

**Lane G2 — Suggestions follow-ups** (Sonnet) — ✅ landed `f2c4cf6`…`c6d1b53`
- ✅ `near_max_5k`/`10k`/`15k` + decade variants, using `Song.maxScore(for:)`; fixed-seed determinism test (see `.agents/pages/suggestions/ios.md` "Tests" for why literal cross-language byte parity isn't the achievable bar here) · ✅ `visibleInstruments` passed from `FestivalRootView`/`AppRouteDestination` into `SuggestionsScreen`, duplicated `@AppStorage` reads removed
- ⬛ Rival-driven families (`song_rival_*`/`lb_rival_*`) still unported: verified the web needs a combined `GET /api/player/{accountId}/rivals/all` read (`buildRivalDataIndexFromRivalsAll`) that `FestivalAPI+Rivals.swift` doesn't expose yet (only per-instrument reads) — not a service-safety block, just a missing native read; follow-on for whichever lane adds it. Band suggestions still deferred (needs band identity).
- Coverage: SuggestionGenerator.swift 96.08%, SuggestionFilterSettings.swift 100%, SuggestionModels.swift 96.92% (llvm-cov). 53 `SuggestionGeneratorTests` (was 47), all Core tests green (313 total in the package).

**Lane K — Service client consolidation + scrape-freeze UX** (Opus) — ✅ landed `7f6e7cb`…`b01585f`
- ⬜ One typed request path for every public GET (Rivals/Bands/History/Notifications/Rankings migrated) · ⬜ One error vocabulary · ⬜ Shared `ServiceStatusView` with scrape-freeze auto-retry (`Retry-After`) adopted across screens · ⬜ `add-endpoint` skill + architecture rules

**Lane K — Service client consolidation & scrape-freeze UX** (Opus) — ✅ landed
- ✅ One request path: `FestivalAPI.send` gate (keyless guard, 30 s timeout, cancellation) + shared `mapStatus`; pinned `read(_:)`, publication, operational and Rivals reads all use it (Rivals' private `URLSession` removed)
- ✅ `ServiceIssue` vocabulary (`scrapeInProgress`/`unavailable`/`syncing`/`notFound`/`offline`/`other`) + capped `ServiceRetryBackoff`; `FestivalAPIError.publicReadFrozen`
- ✅ `Common/ServiceStatusView` / `ServiceStatusInline` / `.serviceStatusOverlay` ("Scores are updating" countdown, announcements, Reduce Motion) adopted on every service screen; `FST_DEBUG_FORCE_FREEZE=1`
- ✅ `GET /api/player/{id}/rivals/all` exposed as `rivalsAll(accountId:)` (pure read verified; typed model + fixture) for the Suggestions rival families
- Docs: architecture "one request path" rule, service-safety freeze semantics, `skills/add-endpoint.md`, `controls/service-status/`

**Lane G3 — Rival-driven suggestions** (Sonnet) — 🟨 running in `~/repos/FestivalNativeApps-lanes/rivalsugg`

### Wave 3 — UX tests (started for completed features)

**Lane Z — Bugs found by UX tests** (Sonnet) — 🟨 running in `~/repos/FestivalNativeApps-lanes/bugfix`
- ⬜ Leaderboards row IDs shadowed by card ID · ⬜ Quick Links jump lands before target · ⬜ FirstRun pulse ignores still-background flag

Coverage so far (SwiftPM hosted+logic): Shell 71.8%, Leaderboards+QL 83.6%, Background 81.0%, History+Notifications 72.7%, First-run 78.8%, Licenses 67.7% — gap is mostly device-only branches; iOS app-target `xccov` measurement still to run.

Queued: **UX tests for Profile / Statistics / Bands / Settings** (worktree `uxprofile` ready; start when load allows)

**Lane U3 — UX tests: Rivals & Compete** (Sonnet) — 🟨 running in `~/repos/FestivalNativeApps-lanes/uxrivals`

**Lane U2 — UX tests: Songs, Song Detail, Paths, Shop, Suggestions** (Sonnet) — 🟨 running in `~/repos/FestivalNativeApps-lanes/uxsongs`
- ⬜ Triage/migrate legacy monolith tests into per-feature files · ⬜ Hosted snapshots per control state · ⬜ XCUITest journeys (batched) · ⬜ Per-feature coverage

**Lane U — UX tests: shell, leaderboards, background, history, notifications, first-run, licenses** (Sonnet) — ✅ landed `bf30198`…`7b85419`
- ⬜ Hosted snapshot per declared control state · ⬜ Per-feature XCUITest journeys against the loopback mock (batched on the shared simulator) · ⬜ Per-feature UX coverage → `.agents/testing/apple/coverage.md`

Not yet assigned:
- ✅ Statistics = selected player's profile page (assigned to Lane P)
- (none — Wave 2 fully assigned)

### Wave 3 — quality gates (iPhone)
- ✅ UX tests per completed feature (XCUITest + hosted snapshots, ≥90% UX coverage)
- ✅ Unit coverage ≥95% non-UX
- ✅ Accessibility pass (whole app) · ⬜ VoiceOver pass

### Wave 4+ — other form factors

**Lane W — iPhone Duo research + adaptive layout architecture** (Opus) — ✅ landed
- ✅ Research + decisions: `.agents/design/apple/duo.md` (per-pose layout, list/detail pages, toolbar rules, root plan, baseline breakages B1–B8), `.agents/platforms/apple/duo.md` (SDK APIs, vertical bar, reserved regions, hinge, simulator limits)
- ✅ `App/Layout/DeviceLayout(+Environment).swift`: pure `LayoutSignals → DeviceLayout` + `\.deviceLayout`, published at the root (behavior-neutral); 14 unit tests
- ✅ `ios_sim.py pose` / `shot --pose --display` / `drive --pose` / `shutdown`; driver `back` taps the vertical-bar `BackButton`
- ⛔ **Pose/rotation cannot be scripted** (no simctl/XCTest hinge; `XCUIDevice` rotation ignored on the outer display). Unfolded, partially folded and rotated-outer captures need the operator to set the pose in Device Hub; then `shot --pose …` verifies it.

**iPhone Duo bespoke layout** — ready to launch once Lanes U/U2/U3 finish (they assert against the shell). Decisions: [design/apple/duo.md](.agents/design/apple/duo.md). Each lane rebases on the previous lane's seam; Duo captures always use `--device duo --pose …` and end with `ios_sim.py shutdown --device duo`.

| Lane | Owns (edit) | Ordered tasks |
|---|---|---|
| **W1 — Duo shell** (Opus) | `App/FestivalRootView.swift`, `App/Shell/*`, `App/Layout/*` | 1. Extract `FestivalShellContent` reading `\.deviceLayout` · 2. Regular section set from `usesRegularSectionSet` (Duo only; iPhone-landscape decision → orchestrator) · 3. Drawer insets by `overlayInsets`, never covers a leading vertical bar/camera (B5) · 4. Root chrome: profile symbol + title in vertical bars, bell `visibilityPriority(.high)` (B1) · 5. Folded captures ×4 rotations (operator rotates in Device Hub) |
| **W2 — Duo list/detail** (Opus) | new `App/Layout/ListDetailStack.swift`, `App/Layout/ListDetailPolicy.swift` (+ tests); `SongNavigationRoot.swift` handed over from Lane S | 1. Pure `ListDetailPolicy.split(section:path:)` + tests (fold/unfold keep state) · 2. `ListDetailStack` (`NavigationSplitView` list + detail `NavigationStack`, empty-selection placeholder) · 3. Songs → Song Detail · 4. Full Rankings → Player · 5. Rivals/All Rivals → Rival Detail · 6. Unfolded + partially folded captures (operator unfolds) |
| **W3 — Duo page polish** (Sonnet) | `Features/Leaderboards`, `Features/SongLeaderboard`, `Features/Songs` (scrubber only), `Features/{Statistics,Suggestions,Settings,Profile}` layout-only edits | 1. Pagination footer → `.bottomBar` symbol items when `.verticalBar` (B2) · 2. Instrument/sort capsules → `Menu` + `Label` · 3. Scrubber margin beside a trailing bar (B4) · 4. Regular-width 2-column grids for dashboards · 5. Row accessibility frames inside the content area (B6) |
| **W4 — Duo UX tests** (Sonnet) | `Apps/iOSUITests/Duo*.swift`, `Tests/FestivalUITests/Duo*HostedTests.swift` | 1. Replace `testDuoOuterFourRotations` with pose-guarded journeys (`--pose`) · 2. Hosted snapshots per pose by injecting `\.deviceLayout` · 3. Vertical-bar item visibility/overflow assertions · 4. Duo coverage row in `.agents/testing/apple/coverage.md` |

Order: W1 → (W2 ∥ W3) → W4. Blocker for native evidence: operator time in Device Hub (unfold, partial fold, 3 outer rotations).

- ⬜ iPadOS · ⬜ macOS · ⬜ iPhone iOS 17 classic tab bar
- ⛔ Android / Windows (Windows host paused by operator)

---

## 5. Known issues / decisions

- **Open operator decisions (Duo):** (1) poses other than folded-portrait can only be set via Device Hub's on-screen buttons (no `simctl`/XCTest API) — needs manual pose changes or permission for UI scripting; (2) whether large iPhones in landscape also get the split Leaderboards/Rivals tabs (web does ≥600 px). Default until decided: Duo-only.

- **One simulator booted at a time (`ad76e5e`):** `ios_sim.py` shuts down other FST simulators before booting a device (Duo lane had both iPhone and Duo booted).
- **SwiftUI sheet environment trap:** environment actions set by the presenter weren't visible inside `.sheet` content in practice; pass closures into sheets explicitly (see `.agents/controls/profile-selection/ios.md`).

- **Simulator lock budget:** UX lanes' XCUITest batches held the lock 10+ min and starved feature lanes. Rule: ≤5 min per lock hold with a hard timeout, batches split; `ios_sim.py uitest` (Lane U) enforces it.

- **Toolbar order rule (`c53b5cb`):** profile avatar is rightmost on tab roots, with the bell in one capsule. Tab roots with their own actions compose `FestivalRootTrailingItems` last and use `.topBarTrailing` (see `.agents/controls/app-navigation/ios.md`).
- **Band detail GET writes:** `GET /api/bands/{bandId}` rebuilds band team configs on cache miss → blocked; band detail resolves via `/api/rankings/bands/{bandType}?teamKey=`.
- **Test-ID families are implicit:** `verify_product.py` accepts `fst.<page-or-control-id>.*` for every declared page/control.
- **Not ported (by design / blocked):** Settings Export ZIP + profile-name refresh (POST-only); live Service Progress and `/api/version` (not on the verified-read allowlist); "select as band profile" (needs session band identity).

- **Scrape freeze UX (Lane K):** a 503 carrying a score-update `x-fst-public-read-freeze-reason` now shows "Scores are updating" with an automatic `Retry-After` countdown on every screen (see `.agents/platforms/service-safety.md#public-read-freeze`).
- **Rivals detail endpoints re-checked (2026-09-28):** `/rivals/{combo}/{rivalId}` and `/leaderboard-rivals/{instrument}/{rivalId}` return HTTP 200 for the sample account outside an active scrape window (verified live, both via `curl` and a loaded `RivalDetailScreen` in the simulator). They still 503 during one — now with an explicit `x-fst-public-read-freeze-reason: scrape` response header (`Retry-After: 30`) instead of the earlier bare 503 — while the list endpoints (`/rivals/{instrument}`, `/leaderboard-rivals/{instrument}`) keep returning 200 through the same freeze. The app's existing `ServiceUnavailableView` + retry already handles this correctly; no code change needed, just confirmation the condition is transient (scrape-scoped), not a permanent block.
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
| 2026-09-28 | Lane N | Bands: detail, player bands, landing, per-song band leaderboard; found `/api/bands/{bandId}` GET writes |
| 2026-09-28 | Lane M | Settings: visual/path column reorder, diagnostics, version; Licenses; Manual reverted (deprecated) |
| 2026-09-28 | Lane Q | Quick Links: feasible; toolbar Menu + VoiceOver rotor (iPhone), inspector later (iPad/Mac); adopted on Leaderboards |
| 2026-09-28 | Lane S | Scrubber `#` labels, keyboard icons (`Song.sig`), Player History links from Song Detail |
| 2026-09-28 | Orchestrator | Avatar-rightmost toolbar rule, implicit test-ID families, app versioning; launched Lanes R2, P2 |
| 2026-09-28 | Lane F | FREs: 44 slides / 9 pages, versioned+hashed seen state (only new slides show), gates, Settings replay; 36 Core tests |
| 2026-09-28 | Orchestrator | Launched Lane D2 (FRE demos) and Lane U (Wave 3 UX tests for completed features) |
| 2026-09-28 | Lane G | Suggestions: full generator port (seeded PRNG, 11 families + decades, 61 tests, ~96% Core coverage), filter sheet, incremental loading; fixed direct-landing load hang |
| 2026-09-28 | Lane S | Toolbar order, Quick Links (Songs/Detail), settings consumers, `Song.maxScores` — lane complete |
| 2026-09-28 | Orchestrator | Launched Lane G2 (Suggestions follow-ups) and Lane U2 (UX tests for Songs/Detail/Paths/Shop/Suggestions) |
| 2026-09-28 | Lane D2 | FRE live demos: all 42 catalog slides now render a live native mini-demo (was Songs-only, 9/42); found a likely pre-existing TabView initial-tab race in debug launch + force mode for non-default tabs (see Lane D2 entry above) |
| 2026-09-28 | Lane D2 | Live demos for all 42 FRE slides (coverage test enforces no fallback) |
| 2026-09-28 | Orchestrator | Fixed empty FRE carousel on non-default launch tab (`.sheet(item:)`, `95d799e`); native FRE copy; demo slot clipping |
| 2026-09-28 | Lane R2 | Rivals follow-up: removed `RivalNavigationBridge`, typed `RivalScope` on `AppRoute`; Common Rivals + Combo/Pro-Drums scope ported to Core; Find Rival search; Quick Links on Compete/Rivals/Rivalry/Rival Detail; re-verified rival detail endpoints live (200 outside an active scrape freeze; new `freeze-reason: scrape` header explains the earlier 503) |
| 2026-09-28 | Lane R2 | Typed `RivalScope` on AppRoute (singleton removed), Common/combo rivals (22 tests), Find Rival, Quick Links on Compete/Rivals; 503s explained (scrape freeze) |
| 2026-09-28 | Orchestrator | Launched Lane K (client consolidation + freeze UX) and Lane U3 (Rivals/Compete UX tests) |
| 2026-09-28 | Lane G2 | Suggestions follow-ups: `near_max_5k/10k/15k` + decades ported; `visibleInstruments` seam closed; verified rival-suggestion data needs a combined `/rivals/all` read not yet in `FestivalAPI+Rivals.swift` |
| 2026-09-28 | Lane G2 | near_max families (+decades), visibleInstruments seam; Suggestions Core coverage 96–100% |
| 2026-09-28 | Orchestrator | Sim lock budget rule for UX lanes; `/rivals/all` read assigned to Lane K |
| 2026-09-28 | Lane K | One keyless request path (Rivals off its own URLSession), `ServiceIssue` + `ServiceStatusView` scrape-freeze countdown on all service screens, `rivals/all` exposed, add-endpoint skill |
| 2026-09-28 | Lane K | One request gate + `ServiceIssue` across 20+ screens; scrape-freeze countdown UX; `rivalsAll`; Rivals API coverage 71%→96.7% |
| 2026-09-28 | Orchestrator | Launched Lane G3 (rival suggestions) and Lane W (Duo research + layout architecture) |
| 2026-09-28 | Lane P2 | Global ranks via per-account rankings (live #1 / Top 0.01%), sheet dismiss→push on active tab, in-memory debug profile, Quick Links on Player/Band/Settings, band song titles; Suggestions filter in reset registry |
| 2026-09-28 | Orchestrator | Enforced one booted simulator at a time (`ad76e5e`) |
| 2026-09-28 | Lane U | UX tests for shell/leaderboards/background/history/notifications/first-run/licenses; flaky artwork test fixed; `ios_sim.py uitest` (5-min holds); found 3 bugs |
| 2026-09-28 | Orchestrator | Launched Lane Z (bug fixes from UX tests) |
| 2026-09-28 | Lane W | Duo research (27.1 SDK: vertical bar, `ReservedRegion`, `onHingeChange`, `ArrangementView`), per-pose decisions, `App/Layout` model + env, pose/display tooling, folded baselines (B1–B8), W1–W4 plan |
| 2026-09-28 | Lane W | Duo research (APIs, poses, cutouts), `DeviceLayout` model + env, `ios_sim.py pose/--pose/shutdown`, folded baseline breakages, W1–W4 lane plan |
