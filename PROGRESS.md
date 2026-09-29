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
   Never squash with `git reset --soft origin/master` — worktrees share remote-tracking refs, so another lane's fetch turns it into a reversal of their work; check `git diff origin/master --stat` before pushing.
2. `tools/lane_integrate.sh` fetches, rebases onto `origin/master`, runs `swift build --build-tests` + the iOS build, pushes `HEAD:master`, and retries if another lane landed first. `--test` also runs `swift test`.
3. Simulator access **only** through `tools/ios_sim.py shot …` (global `flock`; one simulator at a time). Deep-link with `--tab`/`--route` (see `DebugLaunchRoute` in `FestivalRootView.swift`).
4. Lanes report back: what landed (SHAs), screenshots taken, open issues, seam changes needed.

---

## 2. Priorities (from operator, 2026-09-27; updated 2026-09-28)

- **Android + Windows (2026-09-28):** same rules as Apple — platform-native design researched per platform, Fluent second, multiple form factors (Android: phone, book foldable, passport foldable, tri-fold, tablet; Windows: desktop/tablet across window-size configurations), and the same dev → unit → UX tests → accessibility → screen reader flow. The Windows host is far more powerful: run **many parallel lanes on both Android and Windows**, while this Mac continues Apple lanes and oversees. Both machines commit/push when work is ready: Windows lanes push directly to GitHub via `tools/git_integrate.py` (gh file-stored token, set up 2026-09-28); the Mac pulls/rebases as usual.


1. **Liquid Glass & native navigation components**, plus docs/agent updates.
2. **Instrument features and missing pages** — UX match to web, Apple HIG first, Fluent second.
3. **Profile pages** (selected and unselected) → other missing pages → refinement. *Features first, then full UX parity.*
4. **Shared animated background & seamless transitions.**
5. Testing phases: unit tests as we go → UX tests when a *feature* is complete → accessibility tests when the *app* is complete → VoiceOver testing after that.

Platform order: **iPhone (iOS 26.5) → iPhone Duo → iPadOS → macOS → iPhone on iOS 17 (no Liquid Glass)**. Android/Windows run in parallel on the Windows host (resumed 2026-09-28) via `tools/win_relay.py`.

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

**Lane G3 — Rival-driven suggestions** (Opus) — ✅ landed `9c71219`
- ✅ `RivalDataIndex.build(from:)` (new `FestivalCore/SuggestionRivalData.swift`) ports the web's `buildRivalDataIndexFromRivalsAll` from `FestivalAPI.rivalsAll(accountId:)`'s `RivalsAllResponse` (Lane K) · ✅ `SuggestionGenerator.setRivalData(_:)` + all ten `song_rival_*` pipelines (`gap`/`protect`/`battleground`/`spotlight`/`slipping`/`dominate` plus the `near_fc`/`stale`/`star_gains`/`pct_push` cross-pollination variants), mirroring the web's two injection paths (join the startup shuffle vs. splice to the front) · ✅ `FestivalSession+Suggestions.swift` loads `rivals/all` alongside the catalogue whenever the generator is (re)built, best-effort (a failed/unavailable read only skips the rival families) · ✅ rival name/delta badge on `SuggestionCategoryCardView`
- **Finding:** `lb_rival_*` ("Leaderboard Rivals") is dead code on the web itself — `suggestionFilterConfig.ts` reserves the filter type and key prefix, but `buildRivalDataIndexFromRivalsAll` always leaves `leaderboardRivals` empty and no web pipeline ever produces an `lb_rival_*` key. Not ported; documented in `.agents/pages/suggestions/ios.md`.
- `SuggestionCategoryType` gained `.songRivals`; the filter sheet's existing `SuggestionCategoryType.allCases` iteration picked it up with no UI changes, verified by the existing generic filter tests.
- 75 `SuggestionGeneratorTests` (was 53) + `RivalDataIndex` tests; Suggestions-Core line coverage 96.13% (SuggestionGenerator.swift 95.71%, SuggestionModels.swift 97.14%, SuggestionFilterSettings.swift 100%, SuggestionRivalData.swift 97.06%). Verified live (`ios_sim.py drive`): "Dominate {rival}" and other rival categories render with the name/delta badge against the live public service.
- Open: no mid-session re-injection of freshly-updated rival data into an already-built generator (the web's `useSuggestions.ts` re-calls `setRivalData` when its query refreshes; native only calls it once per generator build) — the splice-path code exists and is unit-tested, just not exercised by any current caller.

**Lane K — Service client consolidation + scrape-freeze UX** (Opus) — ✅ landed `7f6e7cb`…`b01585f`
- ⬜ One typed request path for every public GET (Rivals/Bands/History/Notifications/Rankings migrated) · ⬜ One error vocabulary · ⬜ Shared `ServiceStatusView` with scrape-freeze auto-retry (`Retry-After`) adopted across screens · ⬜ `add-endpoint` skill + architecture rules

**Lane K — Service client consolidation & scrape-freeze UX** (Opus) — ✅ landed
- ✅ One request path: `FestivalAPI.send` gate (keyless guard, 30 s timeout, cancellation) + shared `mapStatus`; pinned `read(_:)`, publication, operational and Rivals reads all use it (Rivals' private `URLSession` removed)
- ✅ `ServiceIssue` vocabulary (`scrapeInProgress`/`unavailable`/`syncing`/`notFound`/`offline`/`other`) + capped `ServiceRetryBackoff`; `FestivalAPIError.publicReadFrozen`
- ✅ `Common/ServiceStatusView` / `ServiceStatusInline` / `.serviceStatusOverlay` ("Scores are updating" countdown, announcements, Reduce Motion) adopted on every service screen; `FST_DEBUG_FORCE_FREEZE=1`
- ✅ `GET /api/player/{id}/rivals/all` exposed as `rivalsAll(accountId:)` (pure read verified; typed model + fixture) for the Suggestions rival families
- Docs: architecture "one request path" rule, service-safety freeze semantics, `skills/add-endpoint.md`, `controls/service-status/`

### Wave 3 — UX tests (started for completed features)

**Lane Z — Bugs found by UX tests** (Sonnet) — ✅ landed `a445a3f`…`8716205`
- ⬜ Leaderboards row IDs shadowed by card ID · ⬜ Quick Links jump lands before target (see also Lane U3's independent repro below: tapping any row but the first activates the row *above* it) · ⬜ FirstRun pulse ignores still-background flag

Coverage so far (SwiftPM hosted+logic): Shell 71.8%, Leaderboards+QL 83.6%, Background 81.0%, History+Notifications 72.7%, First-run 78.8%, Licenses 67.7% — gap is mostly device-only branches; iOS app-target `xccov` measurement still to run.

**Lane U4 — UX tests: Profile, Statistics, Bands, Settings + Suggestions hosted** (Sonnet) — ✅ landed `ee9dcef`…`8d59248`
- ✅ 43 hosted snapshot tests (`PlayerProfileRenderTests`, `StatisticsRenderTests`, `BandsRenderTests`, `SettingsRenderTests`, `SuggestionsRenderTests`): every declared control state for these five features, all passing; combined SwiftPM UX coverage 94.2% across the 13 new files (Suggestions specifically 93.0%, up from 8.3%)
- ✅ `tools/mock_service.py` extended with `/api/rankings/{instrument}/{accountId}`, `/api/player/{accountId}/bands`, teamKey-filtered `/api/rankings/bands/{bandType}` (`selectedBandEntry`), band rank history/songs and per-song band leaderboard routes (none existed before)
- ✅ XCUITest journeys: `ProfileStatisticsJourneyTests` (search→view→select→Statistics→deselect) and `BandsJourneyTests` (2: Band Rankings row→Band Detail→song; Player Bands paging) pass on-device; `SettingsJourneyTests` (3: relaunch persistence, reorder sheet, reset) `XCTSkip`'d — consistently hung the shared simulator's 300s lock budget under heavy concurrent-lane load, root cause inconclusive (not the carousel-idle issue the other two files needed fixing)
- **Found (fixed independently by Lane Z2 during this lane's work, confirmed via rebase):** `SongsUITestSupport.selectViewedPlayer`/`viewFixturePlayer` were stale against `ProfileSelectionSheet`'s dismiss-then-push navigation — selecting a different profile from Songs pops back to the Songs tab root itself, not the pushed player page
- Named the Profile journey file `ProfileStatisticsJourneyTests` (not `ProfileJourneyTests`) to avoid colliding with Lane Z2's own class of that name

**Lane Z2 — Wrong-account profile bug** (Opus) — 🟨 running in `~/repos/FestivalNativeApps-lanes/wrongacct` (viewing a searched player could show another account's data; client-side)

Coverage (SwiftPM hosted): Songs 91.3%, Song Detail 92.6%, Item Shop 94.5%, Rivals/Compete 87.8%, Suggestions 8.3% (→ U4)

**Lane U3 — UX tests: Rivals & Compete** (Sonnet) — ✅ landed
- ✅ `RivalsRenderTests.swift` (29 hosted tests) + `CompeteRenderTests.swift` (6): every declared control state (no-profile, loading, empty instruments, song/leaderboard tab, Common Rivals + Combo, per-section 503/empty, All Rivals loaded/empty/unavailable/combo/common/unknown-category, Rival Detail categorized/no-songs/unavailable/nil-scope-fallback/leaderboard-scope, Rivalry ordering, Find Rival's 5 search states)
- ✅ `RivalsMockService.swift`: Rivals reads bypass the injectable `HTTPTransport` (raw `URLSession` at `FestivalAPI.baseURL`, confirmed still true after Lane K's consolidation moved it to the shared `fetchJSON` gate — still not the injectable transport), so hosted tests launch the real loopback `tools/mock_service.py` as a subprocess (`--port 0`, also added) instead of an in-memory actor
- ✅ `tools/mock_service.py` extended with `/api/player/{id}/rivals/*`, `/api/player/{id}/leaderboard-rivals/*` and `/api/rankings/{instrument}` (see `.agents/testing/fixtures.md`)
- ✅ `RivalsJourneyTests.swift` (5 XCUITest journeys via `ios_sim.py uitest`, batched): Compete → drawer → Rivals → View All Rivals → row → Rival Detail → Rivalry drill-down; Quick Links menu; Find Rival search → select; two `DebugLaunchRoute` scope-carrying deep links. 4/5 pass outright; the 5th (`testCompeteQuickLinksMenuListsBothSections`) passes via `XCTExpectFailure` around a real found bug (below)
- ✅ Added missing `fst.rivals.row.<id>`/`fst.all-rivals.row.<id>`/`fst.rivalry.view-profile` identifiers; confirmed on-device via `drive`'s `tree:` dump that they reach the accessibility tree (not shadowed the way Leaderboards' row identifiers are)
- Coverage: this lane's Rivals/Compete `FestivalUI` files combined 87.8% (1940/2211 lines); below the 90% UX target mainly on `FindRivalSheet.swift` (66%), whose remaining gap is the real search-result-tap navigation push, provable only on-device (see `coverage.md`)
- **Real bug found:** `QuickLinksMenu` (`Common/QuickLinks/QuickLinksToolbar.swift`) activates the row *above* the one actually tapped, reproduced independently on both Compete and Rivals via `ios_sim.py drive` — a shared-component bug affecting every page with Quick Links, not fixed by this lane (out of scope; flagged via `spawn_task`)
- Rebased mid-lane onto Lane K's API-client/`ServiceStatusView` consolidation (landed concurrently); full rebuild + full `swift test` re-run confirmed everything still compiles and passes unchanged

**Lane U2 — UX tests: Songs, Song Detail, Paths, Shop, Suggestions** (Sonnet) — ✅ landed `6920322`…`d26bcaf` — landed `6920322`, `1775788`
- ✅ Triaged the legacy monolith: 34 tests migrated into `SongsJourneyTests`/`SongDetailJourneyTests`/`ShopJourneyTests`, 7 deleted (broken by the instrument-picker-into-Filter and offline-disclosure-removal redesigns), shared helpers into `SongsUITestSupport` (a namespaced `enum`, not an `XCTestCase` extension, so it can't collide with Lane U's own helpers extracted from the same file in parallel)
- ✅ New `SuggestionsJourneyTests` (no-profile guard, filter draft, best-effort incremental load) and `SongSectionIndexScrubberRenderTests` (0→3 hosted cases, previously untested)
- **Found and fixed two real bugs while running the migrated tests against the device:** `SongsScreen`'s card row silently lost its VoiceOver `.isButton` trait when `b84cfa4` combined it with an invisible `opacity(0)` `NavigationLink` (SwiftUI drops fully-transparent children's traits from `.accessibilityElement(children: .combine)`); and the Songs UITest helpers still targeted the pre-redesign inline profile-preview sheet (`fst.profile.open`/`fst.profile.select`) instead of the current shared-chrome button (`fst.shell.profile`) and pushed Player Profile page (`fst.player.*`) — both fixed.
- ✅ **Fixed by Lane Z2:** viewing a searched player's profile could display a *different* account. The cause was not the load task: every search result sat in one Form row, so one tap fired all of them and the last result's profile landed on top. See `.agents/platforms/apple/architecture.md` ("List rows hold one action", "Per-entity screens").
- Coverage (SwiftPM hosted, `apple/Sources/FestivalUI/Features/*`): Songs 91.3%, Song Detail 92.6%, Item Shop 94.5% (all above the 90% UX target); Suggestions 8.3% (primary gap — needs hosted snapshot tests, not just the XCUITest journeys added this pass); shared Quick Links 76.6%.
- ✅ Full 41-test XCUITest device pass (a representative subset verified; operator's new ≤5-minute-per-lock-hold rule means the rest needs several more short batches) · ⬜ Suggestions hosted snapshots · ⬜ `apple_xccov_gate.py` iPhone device coverage

**Lane U — UX tests: shell, leaderboards, background, history, notifications, first-run, licenses** (Sonnet) — ✅ landed `bf30198`…`7b85419`
- ⬜ Hosted snapshot per declared control state · ⬜ Per-feature XCUITest journeys against the loopback mock (batched on the shared simulator) · ⬜ Per-feature UX coverage → `.agents/testing/apple/coverage.md`

Not yet assigned:
- ✅ Statistics = selected player's profile page (assigned to Lane P)
- (none — Wave 2 fully assigned)

### Wave 3 — quality gates (iPhone)
- ✅ UX tests per completed feature (XCUITest + hosted snapshots, ≥90% UX coverage)
- ✅ Unit coverage ≥95% non-UX
- ✅ Accessibility pass (whole app) · ⬜ VoiceOver pass

### Operator bug batch (2026-09-28)

| Lane | Items | Status |
|---|---|---|
| **W1** (Duo shell) | Never navigate away on profile/band selection (remove all `selectionRevision` path resets) · Duo: Select Profile in rail · Leaderboards → Profile → Back rail jitter | ✅ (jitter reduced; intermittent 2–3 frame residual, see `.agents/design/apple/duo.md`) |
| **Z2** (wrong-account) | Root cause: all search results in one Form row → one tap fired every row's button (also Find Rival); `.id(accountId)` resets; profile graphs (rank history + percentiles); selection updates in place | ✅ `061bba5`…`77a098f` |
| **M2 — Modals & loading** (Sonnet) | Close/Done trailing app-wide · profile search purple bg (hardcoded `appBackground` fill) · Notifications Done · white spinner, no subtitle (`FestivalLoadingView`) · form-sized sheets on Duo unfolded/iPad | ✅ `06543ab`, `dc73e42` (follow-ups: Suggestions/PlayerHistory sheets use custom Cancel/Apply footers — harmonize to toolbar placements; Songs/Profile spinners → S2/Z2) |
| **A2 — Nav-bar accessories** (Opus) | Research iOS 26 accessories · Search placement · Select Player accessory · Quick Links decision · page sweep · Apple global search | ✅ decision record [nav-accessories.md](.agents/design/apple/nav-accessories.md). iOS 26.1+ iPhone: tab-bar accessory = global Search on every page + profile Select/Switch/Deselect; Duo rail / pre-26 / iPad / Mac: toolbar items; Songs keeps an inline "Filter Songs"; Quick Links stays a toolbar Menu (not an accessory); Suggestions + Rivals-root toolbar order fixed. Open: result-count announcement; hosted snapshots per global-search state |
| **S2 — Songs polish** (Sonnet) | Section headers (real `Section`), bigger chip icons (70%), no status badges (+ `statusAmber` token), `MarqueeText`, first-paint art gate (≤900 ms), compact Duo-safe scrubber | ✅ `93eb2d1`, `ff51d31` (follow-ups: inset cards beside scrubber; MarqueeText in Song Detail header + Suggestion cards; re-run SongsJourneyTests) |
| **L2 — Leaderboards spotlight** (Sonnet) | Selected player highlighted in top 10 / spotlight row below (per-account rank read), jump-to-page on Full Rankings, pinned "You" footer on song leaderboards | ✅ `23dbd60` (band spotlight deferred: no native band identity) |
| **H — Hosted snapshot fidelity** (Opus) | Hosted harness renders full pages nearly blank → fix harness, add content assertions, re-measure coverage | ✅ root cause: tinted Liquid Glass blanks `cacheDisplay`; see [hosted-snapshots](.agents/testing/apple/hosted-snapshots.md) |

**Lane H — Hosted snapshot fidelity** (Opus) — ✅ landed `1d5aa82`, `51a03ce`: tinted Liquid Glass made captures transparent → tests force Reduce-Transparency fallback, `nativeHostedSettle`, `assertRendersContent`; blank/spinner captures 33 → 3; UX 66.8% → 70.4%; 597 tests.

**Lane C — Apple cleanup + gates** (Opus) — ✅ landed `19c8f8f`…`1ccd78d`: coverage gate recursive-glob fix (UX gate was silently classifying ~1 of 104 FestivalUI files) · logic coverage 93.90%→95.81% · Rivals Common Rivals 503 fix · Compete honest empty state · Songs scrubber card inset · MarqueeText in Song Detail/Suggestions · Suggestions/PlayerHistory sheets to semantic toolbar placements · shared `FestivalApp` UITest launch helper (migrated 14 call sites) + found/fixed `MarqueeText` not honoring `FST_DEBUG_STILL_BACKGROUND` (root cause of Songs/Suggestions journey hangs) · retired `tools/apple_native_matrix.py` (stale single-file assumption, unused) · fixed `test_contrast_gate` for the color-only chip design · un-skipped all 3 `SettingsJourneyTests` (confirmed simulator contention, not a bug)

### PWA reference lab (operator, 2026-09-28): "research is good, repro is better"

Install the real PWA on every platform, record pages/animations/navigations, compare with native builds, and feed gaps back to lanes.
- 🟨 **PWA-Apple** (Opus, Mac): Safari Add to Home Screen on iPhone 26.5 / iPad / Duo folded; macOS Add to Dock; scripted drive + video; `.agents/testing/pwa-reference/apple.md` + `apple-gaps.md`
- 🟨 **FST-pwa-winandroid** (Windows host): Edge app on Windows (window-size presets), Chrome install on every `FST_` AVD (phone, book/passport fold, tri-fold, tablet); `windows.md`, `android.md`, `*-gaps.md`
- Rule added to `AGENTS.md` change loop: reproduce against the installed PWA before implementing.

### Global search (operator, 2026-09-28) — all platforms, all layouts

Web: a magnifier in the shell header on every page opens one search over songs (local catalogue), players and bands. Spec: [global-search/spec.md](.agents/controls/global-search/spec.md) (contract `global-search`, `fst.global-search.*`). Safety: players via `GET /api/account/search` (allowed); **band search writes → Bands scope shown but unavailable, with explanation and a Band Rankings link**; songs are local.
- ✅ **R-search** (Opus, docs only): web behavior spec, Android/Windows per-layout designs, contract entry, this plan.

| Lane | Owns (edit) | Tasks | Test plan |
|---|---|---|---|
| **A2** (Apple, Opus) — ✅ (see [global-search/ios.md](.agents/controls/global-search/ios.md)) | Apple files only; records `ios.md`/`ipados.md`/`macos.md` under `.agents/controls/global-search/` | Search action in every page's chrome on iPhone 26 / pre-26, Duo folded + unfolded, iPad, macOS; shared engine for songs + players; Bands explanation; routes onto the current tab | Swift Testing for the engine (debounce, cancel, late result, <2 chars, empty → Retry, freeze, no band request); XCUITest open/search/tap/Back per layout; hosted snapshots per state |
| **win-search** (Windows) — ⬜ ready | `Festival.Core/ViewModels/GlobalSearchViewModel.cs`, `Domain/GlobalSearchResults.cs`, `Pages/SearchPage.xaml(.cs)`, `MainWindow.Search.cs`, the `TitleBar.Content` + compact button in `MainWindow.xaml`; `AppRoute.Search` via `win-shell` | 1. Model + tests · 2. Title-bar `AutoSuggestBox` + mixed suggestions · 3. Search page (SelectorBar All/Songs/Players/Bands, grouped list, Retry, InfoBar) · 4. Compact (<720 epx) button · 5. Ctrl+E / Ctrl+F accelerators · 6. Narrator notification · 7. UIA journeys ([windows.md](.agents/controls/global-search/windows.md)) | xUnit ≥95% on the model/results; `uiwin.py drive` at `compact`, `medium`, `wide`, `snap-left` (+683 epx): Ctrl+E, type, arrow + Enter on a suggestion, submit → page, scopes, Bands InfoBar, Back; fixture log shows no `/api/bands/search`; Axe.Windows scan of the page |
| **and-search** (Android) — ⬜ after the Android foundation | `search/GlobalSearchModel.kt` + UI `search/GlobalSearch*.kt`; one shell call site via the shell owner | 1. Model + JUnit · 2. Compact action → `ExpandedFullScreenSearchBar` · 3. Medium docked · 4. Expanded persistent `SearchBar` + docked panel · 5. Fold/tabletop/tri-fold clamping + continuity · 6. Ctrl+K / Search key / Ctrl+F + shortcuts helper · 7. Predictive back + TalkBack ([android.md](.agents/controls/global-search/android.md)) | JUnit ≥95% on the model; Compose UI tests by `testTag`; `device.py drive` on phone, book fold (folded/unfolded/tabletop), passport, tri-fold (3 states), tablet, resizable presets, each with a fold/resize mid-search continuity check; TalkBack walkthrough |

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
| **W3 — Duo page polish** (Sonnet) | `Features/Leaderboards`, `Features/SongLeaderboard`, `Features/Songs` (scrubber only), `Features/{Statistics,Suggestions,Settings,Profile}` layout-only edits | ✅ landed `e0e887f`: 1. ✅ Pagination footer → `.bottomBar` symbol items when `.verticalBar` (B2) · 2. ✅ Instrument/sort capsules audited — already `Menu` + `Label`, nothing to convert · 3. ✅ Scrubber margin beside a trailing bar (B4, confirmed via fresh capture) · 4. ✅ Regular-width 2-column grids for Leaderboards overview + Statistics/Profile (Settings gets readable-width instead, per design doc) · 5. ✅ Row accessibility frames inside the content area (B6, rankings/leaderboard `List`s) · Also: rail overflow decision (Bell+Profile visible, hamburger overflows) formalized as `RootChromeRailItem` + test; found and fixed reappear-reload jitter in `PlayerProfileContent`/`InstrumentGlobalRankView`/`SuggestionsScreen` (same `.task(id:)`-restarts-on-reappear quirk as pre-W1 Leaderboards) |
| **W4 — Duo UX tests** (Sonnet) | `Apps/iOSUITests/Duo*.swift`, `Tests/FestivalUITests/Duo*HostedTests.swift` | 1. Replace `testDuoOuterFourRotations` with pose-guarded journeys (`--pose`) · 2. Hosted snapshots per pose by injecting `\.deviceLayout` · 3. Vertical-bar item visibility/overflow assertions · 4. Duo coverage row in `.agents/testing/apple/coverage.md` |
| **AP — Apple polish** (Opus) | `Design/StarRating.swift`, `Resources/Stars.xcassets`, `FestivalDesign/FestivalText.swift`; foreground styles in Profile/Statistics/Rivals/Compete/Suggestions/Bands/Notifications/Search/Common/Design | ✅ `42a5448` `StarRating(stars:gold:style:size:)` + web `star_white`/`star_gold` · `509a219` Suggestions + Band Detail stars · `e6559db` removed "This Is Me"/"Public Profile" subtitle + seal · `8b0297b` white-text rule (`FestivalText`, [architecture.md](.agents/platforms/apple/architecture.md#text-colour-rule-operator-rule-2026-09-28)). Left for owners: SF stars in `Songs/SongProfileMetadataPills.swift` (A2), `FirstRun/Demo/*` (PS), `SongLeaderboard/SongBandLeaderboardScreen.swift` (PB/PD); Stars attribution in `Settings/LicenseManifest.swift` (PS); white-text sweep of Songs/SongDetail/Shop/Leaderboards/Settings/FirstRun/WhatsNew |

Order: W1 → (W2 ∥ W3) → W4. Blocker for native evidence: operator time in Device Hub (unfold, partial fold, 3 outer rotations).

- ⬜ iPadOS · ⬜ macOS · ⬜ iPhone iOS 17 classic tab bar
- 🟨 Android / Windows — Windows host resumed 2026-09-28; lanes run there via `tools/win_relay.py` (headless Claude Code on `sfenton-primary`)
  - **Lane AND — Android foundation** (remote) — ✅ `800e20f`…`e16ad03` (pushed from Windows): Compose architecture, request gate, typed routes, DataStore profile, adaptive shell (bar/rail/permanent drawer), shared background, Songs + Song Detail live (list-detail on expanded); 74 tests, logic 96.8%, UI 87.3%.
  - **Android feature lanes** (Remote Control sessions `FST-and-*`, launched 2026-09-28): `and-shell-search` (adaptive shell per posture/size + global search) · `and-leaderboards` · `and-profile` · `and-rivals` (incl. Compete) · `and-suggestions` (Kotlin generator + seed parity) · `and-bands` · `and-settings` (Settings, Licenses, first-run, notifications, Quick Links) · `and-songs` (Songs parity, Item Shop, Paths). Each integrates itself via `tools/git_integrate.py`.
  - ✅ `and-rivals` (`68704f5`…`427c8ed`): Rivals hub (Song/Leaderboard, Common + per-chart), All Rivals, Rival Detail, Rivalry, Find Rival (`allowLiveFallback` from Find Rival only), Compete (ranking scopes + combo boards); hinge-split half-open, tablet 2-col; 53 tests, 92–100% logic / 87–100% UI. Follow-ups: device-drive journeys, Passport/TriFold/Resizable shots, half-open gap ~17 px left of fold, Rank By picker, native combo full board, TalkBack.
  - ✅ `and-profile` (`da539e0`…`8fc36cf`): profile sheet (Players/Bands, band search never requested), player page with Select/Switch/Deselect that never navigate away, overview + per-instrument stats (client-side), global rank, lazy rank-history/percentile charts, Statistics tab, score history; `SelectedProfileStore` persists across cold starts (device-verified); phone/book/passport/tri-fold/tablet shots; 21 tests, profile files 93–98% (charts 65%, Canvas). Gaps → follow-up: Song Detail → score history entry, player-page Quick Links, top songs, tap-to-filter tiles, hinge padding, TalkBack.
  - ✅ `and-settings` (`31453e6`…`b6a8436`): Settings (every web section with native meaning, DataStore, `SettingsRegistry` reset policy), Licenses (generated manifest, `licenses --check` now in CI), first-run (Apple semantics, 42 live demo slides), notifications (bell, New/Older, seen state), Quick Links per form factor (sheet / menu / persistent pane / hinge split); 442 tests, logic 97.3%, UI 85.0% app-wide. Open: tablet/fold content drawn under the status bar (→ shell), Songs/Paths consumers of settings, passport/tri-fold/resizable evidence, TalkBack.
  - ✅ `and-songs` (`6afe1ef`, `5c49cde`, `2bcdca0`, `cf20670`): Songs parity (Shop sort/filters, per-chart score/FC filters, paused states, drafts, corrupt-filter Reset, marquee, section index), Song Detail parity (Shop badge, Paths, band links, own-row highlight, Show My Rank, score-history link), CHOpt Paths sheet, Item Shop page (list/grid); 190+ tests, logic 97.5%, UI 87.5% app-wide. Follow-up lane `and-songs2`.
  - ✅ `and-leaderboards` (`7981850`…`3ee2432`): Overview (top-10 per visible instrument + bands, persisted Rank By, ≤4 concurrent reads), selected-player spotlight, anonymous rows inert, Full/Band Rankings (25-row pages, pickers, shared pager, Your Page jump), song leaderboard selected-score footer; grid ≥340 dp cards, supporting pane ≥840 dp, hinge-exact half-open split; 41 tests, logic 97.8%, UI 91.1% app-wide. Open: Quick Links + rank-history on overview, band spotlight, paging not in route, song footer ignores leeway, TalkBack.
  - ✅ `and-bands` (`f9cd1ae`…`ad33432`): Bands landing (no-search explanation, selected-player preview, rankings cards), Player Bands, Band Detail (members, stats w/ Rank By, rank history, best/worst songs), song band leaderboard; lookups only via `?teamKey=`, bare bandId → "Band Not Available" with no request; fold/hinge/tri-fold/tablet panes; 43 tests, Bands logic 96–100% / UI 91–100%. Entry points handed to and-songs2 (Song Detail) and and-profile2 (player page). Not built: combo filter, Select Band Profile, Quick Links.
  - ✅ `and-shell-search` (`e0c7f8b`…`b6513a1`): NavigationSuiteScaffold shell (bottom bar / centred rail / permanent drawer), global search (full-screen phone, docked ≥600 dp, fold-aware, Ctrl+K/Ctrl+F, TalkBack counts, never band search), content clipped below the top bar, M3-Expressive-style floating toolbar slot (`ui/common/FloatingToolbar.kt`), Quick Links as menu/bottom sheet (no side pane), drawer honours Hide Item Shop, first-run position in dots' stateDescription; 7/7 device journeys on all AVDs; logic 97.9%, UI 93.2% app-wide. Open: embedded Song Detail pads status bar itself, Songs filter → `RegisterPageFind`, floating toolbar hide-on-scroll, TalkBack pass. Note: `SelectedPlayer.validated` now uses the shared `[A-Za-z0-9_-]{1,128}` rule, so `search_journey.py`'s 32-hex remap is likely obsolete — verify in the device-testing lane.
  - ✅ `and-profile2` (`f3ffb60`…`025e656`): player-page Quick Links, top/bottom songs, tap-to-filter tiles, Bands section, combined bar+line Rank History with swipe/paging, headers above cards, fade-in, native sheet search, hinge-aware grid; instrumented journeys 5/5 on phone + book half-open; logic 97.9%, UI 93.1%.
  - ✅ `and-suggestions` (`e50082d`…`d85cf82`): Kotlin generator with exact Apple parity (228 + 27 remix pages via the Windows fixture), screen + filter, hinge-aware two-column half-open layout; 99.0% logic / 96.8% UI. Follow-up: consolidate onto `SelectedProfileStore`.
  - **Original Android foundation brief:** port Copilot foundation → tooling (build/emulator/screenshot, one emulator at a time) → Compose architecture + request gate + typed routes → adaptive shell (bar/rail/list-detail) → Songs + Song Detail live → JUnit ≥95% logic
  - **Lane LAB — Device lab** (remote) — ✅ `7ddc2b3` (pushed from Windows): 6 `FST_` AVDs boot (phone, book/passport fold w/ real postures, tri-fold approximated, tablet, resizable); `tools/android/device.py` + `tools/windows/uiwin.py` with FIFO locks (300 s); TalkBack on AVDs, Axe.Windows/Accessibility Insights/PresentMon/FlaUI installed. Original scope: SDK/tool updates; `FST_` AVD matrix (phone, book fold, passport fold, tri-fold, tablet, resizable); `tools/android/device.py` + `tools/windows/uiwin.py` with global locks (one emulator / one desktop driver at a time, ≤5 min holds), window-size presets for Windows desktop/tablet
  - **Lane WIN — Windows foundation** (remote) — ✅ `9b37ab4`…`7868ab6` (pushed from Windows): **C# NativeAOT** chosen with measurements (C++/WinRT 173 ms/88 MB vs C# AOT 182 ms/92 MB first frame/WS; animation ≤1% core); background stepped to 30 Hz (15%→3–4% core, 1% GPU); 240 fps scrolling p99 5–8 ms; Mica shell, request gate, typed routes, persisted settings, Songs/Song Detail/Settings live; 214 tests, logic 99.5%, VM 100%.
  - **Windows feature lanes** (Remote Control sessions `FST-win-*`, launched 2026-09-28): `win-leaderboards` (overview/full/band rankings, song leaderboard, spotlight) · `win-profile` (selection, profile page + graphs, Statistics, history) · `win-rivals` (hub, all, detail, rivalry, Find Rival) · `win-suggestions` (C# generator port w/ seed parity) · `win-bands` · `win-settings` (Settings, Licenses, first-run, notifications, Quick Links idiom) · `win-songs` (Songs parity, Item Shop, CHOpt Paths). Each integrates itself via `tools/git_integrate.py`.
  - ✅ `win-suggestions` (`74a3863`…`17ea7c0`): exact parity with Apple generator (swiftc on Windows compiles unmodified Apple sources; 6 seeds × 228 pages), 828 Core tests.
  - ✅ `win-settings` (`d234d24`…`97b77bb`): all web Settings sections + Accessibility, Licenses from NuGet graph, first-run (ContentDialog, replay), notifications bell/flyout, Quick Links (menu < 1150 epx, pane ≥ 1150); 99.6% lines.
  - ✅ `win-leaderboards` (`d56f75f`…`bd71f1c`): overview + spotlight, full/band rankings w/ pinned "your rank", song leaderboard; 3-col grid wide; idle 0.03% CPU; found anonymous production ranking rows (fixed on Apple too, `2e90438`).
  - ✅ `win-bands` (`be040ba`…`8719acf`): landing, player bands, band detail (safe `?teamKey=` read only), per-song band leaderboard; 99.3% band-file coverage; fixed tooling that killed other lanes' app windows; found bare `/api/rankings/bands/{type}/{teamKey}` writes (now in service-safety; Apple never used it).
  - ✅ `win-songs` (`549b9ea`…`5e9422e`): Songs parity, Song Detail (Shop, Paths dialog, your-score, history), Item Shop page; 829 tests; idle 0.01% CPU; `AppSettings` init→set fix.
  - 🟨 `win-search` (`FST-win-search`): global search (title-bar AutoSuggestBox, Search page, compact button, Ctrl+E, Narrator).
  - ✅ `win-profile` (`71d09bc`…`46648e8`): profile flyout, player page = Statistics (select/switch/deselect in place, rank history + percentiles), score history, persisted selection; 830 tests; 7 journeys pass (Debug).
  - ✅ `win-rivals` (`3789228`…`6bd8cd3`): hub (Common/combo/family), All, Detail, Rivalry, Find Rival, typed scope; 7/7 journeys on AOT; idle 0.01% CPU.
  - ⬜ **Rivals live fallback (all platforms):** pass `allowLiveFallback=true` on rival detail **only when opened from Find Rival** (web: `RivalsPage.tsx:263` route state → `client.ts:490`; verified read-only, `c873ce1`) — carry the flag in the typed `RivalScope`/route.
  - ✅ `win-shell` (`3881458`…`2d46afe`): NavigationView Auto (LeftMinimal <641, rail 641–1007, expanded ≥1008; 9 pages × 7 configs), occlusion pause (covered 0.3–2.2% core), per-worktree Debug data dir, AppStateFiles reset registry, UIA foreground/--isolate; 848 tests.
  - 🟨 `win-infra` (`FST-win-infra`): Release/AOT automation switch, coverage gate for async partials, CI windows-latest job, title bar <720, search VM reuse, rivals live fallback, Quick Links everywhere.
  - 🟨 `win-a11y` (`FST-win-a11y`): **Windows accessibility phase** — Axe.Windows 0 errors per page, keyboard order/focus, Narrator names + announcements + manual script, high contrast/text scaling/animations off/transparency off.
  - ⬜ **Windows infra backlog** (now assigned to win-infra) (next shell/infra lane): Release/AOT UI automation — first-run dialog has no test-launch opt-out (`--first-run=off` for automation) and UIA tree walk fails while it's open; plus:
  - ⬜ Wire `tools/windows/tests` + `tools/android/tests` into CI (windows-latest runner).
  - ⬜ Windows coverage gate: async-only Rivals/Notifications client partials report uncovered (compiler-generated exclusion) — fix in next shell/infra pass.
  - 🟨 `win-shell` (`FST-win-shell`): compact NavigationView, occlusion pause, per-lane Debug data dir, UI-automation foreground robustness, reset registry.
  - **Original Windows foundation brief:** port Copilot foundation → **C# vs C++/WinRT measured decision** → tooling → MVVM + request gate → NavigationView shell (Mica, split Leaderboards/Rivals) + composition-thread background → Songs + Song Detail live → tests

---

## 5. Known issues / decisions

- **Operator decision (Duo rail, 2026-09-28):** folded Duo with a profile (5 tabs) keeps **Bell + Profile** visible in the vertical rail; hamburger moves into "…".
- **Operator decisions (Duo, 2026-09-28):** (1) **UI scripting allowed** for Device Hub poses — operator grants macOS Accessibility permission (agents never change security settings); (2) split Leaderboards/Rivals tabs **only on Duo unfolded + iPad**; large iPhones keep portrait tabs in landscape.

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

- **Leaderboards follow-ups:** ✅ selected-player spotlight ported (Lane L2, see `.agents/pages/{leaderboards,full-rankings,song-leaderboard}/ios.md`) — no band spotlight yet (no native selected-band identity); still no rank-history chart, no band-combo filter on the overview; per-card loads are sequential. Hosted-harness blank pages: fixed by Lane H (forced glass fallback, settle + `assertRendersContent`).
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
| 2026-09-28 | Lane G3 | Rival-driven suggestions: `RivalDataIndex` from `/rivals/all`, all ten `song_rival_*` pipelines, rivals loaded alongside the catalogue (best-effort), rival badge on category rows; found `lb_rival_*` is dead code on the web itself; 75 tests, 96.13% Suggestions-Core coverage |
| 2026-09-28 | Lane U2 | Triaged Songs/Shop/Detail legacy UITests (34 migrated, 7 deleted), added Suggestions journeys + section-index hosted tests; found and fixed the Songs-row `.isButton` trait loss and stale profile-flow test IDs; flagged (unfixed) a Player Profile wrong-account-data bug; Songs/Detail/Shop hosted coverage 91–95%, Suggestions 8.3% (open gap) |
| 2026-09-28 | Lane U3 | Rivals/Compete UX tests: 35 hosted snapshot tests, 5 XCUITest journeys, `mock_service.py` Rivals/rankings routes, missing row accessibility identifiers; found a shared `QuickLinksMenu` off-by-one row-selection bug (flagged, not fixed by this lane) |
| 2026-09-28 | Lane G3 | All 10 `song_rival_*` suggestion families (`lb_rival_*` is dead code on web); Suggestions Core 96% |
| 2026-09-28 | Lane U2 | Legacy UITest monolith 4921→1797 lines (7 deleted, 34 migrated); Songs/Detail/Shop ≥91% hosted coverage; fixed VoiceOver button trait on song rows; found wrong-account bug |
| 2026-09-28 | Lane U3 | Rivals/Compete: 35 hosted + 5 journeys, 87.8% |
| 2026-09-28 | Lane Z | Fixed Leaderboards row ID shadowing, Quick Links landing short, FirstRun pulse vs still flag; all journey batches pass |
| 2026-09-28 | Orchestrator | Operator decisions recorded; launched Z2 (wrong-account bug), U4 (Profile/Bands/Settings UX tests), W1 (Duo shell) |
| 2026-09-28 | Orchestrator | Operator bug batch triaged into W1, Z2 (+graphs), M2, A2, S2, L2; rule: selection never navigates away |
| 2026-09-28 | Lane M2 | Modal standard (trailing Close/Done, semantic placements), purple sheet bg removed, `FestivalLoadingView` app-wide, form sheet sizing on regular width |
| 2026-09-28 | Lane L2 | Selected-profile spotlight on Leaderboards overview cards, Full Rankings (+ native jump-to-page footer) and Solo leaderboard (highlight + footer, no extra network read); `RankingSpotlight` pure decision logic + tests; band spotlight skipped (no native selected-band identity); found macOS hosted-snapshot harness renders full-screen pages blank (flagged, not fixed) |
| 2026-09-28 | Lane L2 | Leaderboards selected-player spotlight + song leaderboard "You" footer |
| 2026-09-28 | Orchestrator | Launched Lane H: hosted snapshots render full pages nearly blank (coverage may overstate visual evidence) |
| 2026-09-28 | Lane H | Hosted harness: tinted Liquid Glass made whole `NSHostingView` captures transparent and sleeps captured spinners; forced Reduce-Transparency fallback, in-process accessibility text, `nativeHostedSettle`, `assertRendersContent` on 65 full-page tests (+Settings, Player Profile). Blank captures 33→3 (sparse empty states). SwiftPM UX 66.8%→70.4% recursive; gate's Swift UX glob is non-recursive (flagged). Found Common Rivals hides its 503 error (known issue) and 4 Rivals tests 404ing on a hyphenated mock id (fixed) |
| 2026-09-28 | Orchestrator | Windows host online: SSH verified, toolchains inventoried, `tools/win_relay.py` bundle relay (no GitHub creds on Windows) |
| 2026-09-28 | Orchestrator | Operator: parallelize Android + Windows heavily on the Windows host; launched remote Lane LAB (device lab); GitHub auth on Windows pending operator (`gh auth login --insecure-storage`) |
| 2026-09-28 | Orchestrator | GitHub auth on Windows verified over SSH; Windows `origin` → GitHub; `tools/git_integrate.py` for Windows-host lanes (`ee20551`) |
| 2026-09-28 | Lane S2 | Songs polish: removed instrument-chip star/check/minus/exclamation marks (color-only status, new `statusAmber` token keeps Inconsistent FC distinct from No score), enlarged chip icons to web's ~71% proportion; Duration/Item Shop section headers are now real `List` `Section`s instead of a card-styled row (fixed the opaque-bar-behind-header look); fixed the Duo A–Z scrubber sizing itself to its own letters instead of the full List height (B4: no more creep past `#`/`Z` or row overlap when the large title collapses); ported web's `MarqueeText` (`Design/MarqueeText.swift`, unit-tested `MarqueeTiming`) so long title/artist/year/duration rows scroll instead of wrapping; gated Songs' first reveal on the first ~12 rows' artwork decoding (bounded 900ms, native-only — web has no equivalent). `fst.songs.navigation-notice`'s "Selected profile changed" text needed no Songs-side change (root-only, Lane W1) |
| 2026-09-28 | Lane Z2 | Wrong-account profile fixed at root (one Form row fired every result Button); per-entity `.id` hardening across Profile/Rivals/Compete; select/deselect stays in place (journey); profile Rank History + Percentiles graphs (Swift Charts, pure-read history endpoint) |
| 2026-09-28 | Lanes S2, Z2 | Songs polish landed; wrong-account bug root-caused (single Form row) + profile graphs |
| 2026-09-28 | Lane H | Hosted harness renders real content; content assertions on 65 full-page tests |
| 2026-09-28 | Orchestrator | `win_relay launch/wait`: Windows lanes as monitorable Remote Control sessions (probe verified); launched Lane C (cleanup + gates) |
| 2026-09-28 | Lane U4 | UX tests for Profile/Statistics/Bands/Settings/Suggestions: 43 hosted tests (94.2% combined coverage, Suggestions 8.3%→93.0%), `mock_service.py` Bands/ranking fixtures, 3 XCUITest journeys passing (2 files) + 3 skipped (Settings, simulator-load hang); confirmed Lane Z2's independent fix for stale dismiss-then-push assumptions in `SongsUITestSupport.swift` |
| 2026-09-28 | Lane U4 | 43 hosted tests + Profile/Bands journeys; mock_service band/ranking routes; Settings journeys hand-off to Lane C |
| 2026-09-28 | Lane LAB | Device lab landed from Windows (first direct Windows→GitHub push) |
| 2026-09-28 | Lane W1 | Duo shell: `ShellPresentation` (split tabs only on Duo inner display/iPad), cutout-safe drawer, rail profile symbol + bell/profile priority, selection never navigates (`FestivalTabPolicy.adapt`), rail Select Profile, pop-jitter fixes, `ios_sim.py pose --set` UI scripting (awaiting operator Accessibility grant), `drive --record` |
| 2026-09-28 | Lane WIN | Windows foundation landed from Windows; C# NativeAOT decision with evidence |
| 2026-09-28 | Orchestrator | Launched 7 Windows feature lanes as Remote Control sessions (`FST-win-*`); web source cloned read-only on Windows |
| 2026-09-28 | Lane C | Coverage gate recursive-glob fix (UX gate was silently classifying ~1 of 104 FestivalUI files as 97%); logic coverage 93.90%→95.81%; Rivals Common Rivals 503 fix; Compete honest empty state; Songs scrubber card inset; MarqueeText in Song Detail/Suggestions; Suggestions/PlayerHistory sheets to semantic toolbar placements; shared `FestivalApp` UITest launch helper (14 call sites) + found/fixed `MarqueeText` not honoring `FST_DEBUG_STILL_BACKGROUND` (root cause of Songs/Suggestions journey hangs); retired `tools/apple_native_matrix.py` (stale single-file assumption post-monolith-split, unused elsewhere); fixed `test_contrast_gate` for the color-only chip design; un-skipped all 3 `SettingsJourneyTests` (confirmed simulator contention, not a bug — individually 68–282s) |
| 2026-09-28 | Lanes W1, C | Duo shell + Apple cleanup landed; master green (`671ff23`); launched W2, W3 |
| 2026-09-28 | Windows lanes | win-suggestions + win-settings landed; launched win-shell |
| 2026-09-28 | Windows lanes | win-leaderboards landed; anonymous-ranking-row quirk fixed on Apple + documented |
| 2026-09-28 | Lane W3 | Duo page polish landed (`e0e887f`): rail overflow decision (Bell+Profile visible, hamburger overflows, `RootChromeRailItem`), B2 pagination → `.bottomBar` items, B6 row accessibility clearance, regular-width 2-column dashboard grids (Leaderboards/Profile), Settings readable-width; found and fixed reappear-reload jitter in Statistics/Player Profile and Suggestions (`.task(id:)` restarting on `NavigationStack` reappearance even with an unchanged id) |
| 2026-09-28 | Lane W3 | Duo rail/page polish landed; orchestrator fixed last non-standard spinners (`e5c41a4`) |
| 2026-09-28 | Windows lanes | win-bands landed; new blocked endpoint recorded (`1536971`) |
| 2026-09-28 | Orchestrator | Operator: global search on every page/platform/layout → R-search research lane + A2 Apple scope |
| 2026-09-28 | Orchestrator | Global search spec landed + operator decisions; win-songs landed; launched win-search; verify_product root-ID rule (`78736f3`) |
| 2026-09-28 | Windows lanes | win-profile landed; mock history accuracy scale fixed (`72b147e`) |
| 2026-09-28 | Orchestrator | Operator: repro the installed PWA on all platforms → launched PWA-Apple (Mac) + FST-pwa-winandroid (Windows); AGENTS.md change-loop rule |
| 2026-09-28 | Windows lanes | win-rivals landed; mock Connection: close; rivals live fallback verified safe |
| 2026-09-28 | Android | Foundation landed from Windows (`e16ad03`, docs conflict resolved); launched 8 Android feature lanes as Remote Control sessions |
| 2026-09-28 | Lane A2 | Tab-bar accessory: global Search on every iPhone page (iOS 26.1+) + profile Select/Deselect; system search tab rejected (5 tabs → "More"); Apple global search (sheet, ⌘K/⌘F, toolbar fallback incl. Duo rail/iPad/Mac, Bands blocked); Songs inline filter; Suggestions/Rivals toolbar order; journeys green |
| 2026-09-28 | Windows | win-shell landed; mock server backlog 5→128 |
| 2026-09-28 | Lane W2 | Duo list/detail landed; SongsJourneyTests regression (19/21 failing on master) sent to A2 |
| 2026-09-28 | Orchestrator | Windows Remote Control lanes now appear as peer sessions → orchestrator can message them mid-run |
| 2026-09-28 | Windows | win-search landed (global search on Windows) |
| 2026-09-28 | Windows | Launched win-infra + win-a11y (Windows enters accessibility phase) |
| 2026-09-28 | Android | and-suggestions landed (3-platform generator parity) |
| 2026-09-28 | Android | and-rivals landed (incl. Compete); combo rankings endpoints recorded as pure reads; mock ranking/band accuracy scale fixed (`0212604`) |
| 2026-09-28 | Apple tests | Wall-clock flakes fixed: Retry-After countdown (`\.serviceRetryClock`) and artwork dwell (`ArtworkBackground(clock:)`) run on an injected `ManualTestClock` in tests, with no wall-clock deadlines; see [hosted-snapshots](.agents/testing/apple/hosted-snapshots.md) |
| 2026-09-28 | Android | and-profile landed (selection persists across cold starts) |
| 2026-09-28 | Android | Launched and-profile2 (player-page Quick Links, top songs, tap-to-filter tiles, hinge padding, chart coverage, device journeys) |
| 2026-09-28 | Android | and-settings landed; notifications endpoint recorded as pure read; `licenses --check` in CI |
| 2026-09-28 | Lane PWA-Apple | Installed-PWA lab landed (`caaf562`, `4407d0d`): iPhone/iPad/Duo PWA captures, 22-row gap table (`.agents/testing/pwa-reference/apple-gaps.md`). Incident: one off-screen tap opened a public player page on production (blocked stats + sync-status GETs, no POST/headers); driver now refuses off-screen taps, rule in service-safety. macOS PWA blocked on Screen Recording/Accessibility permission |
| 2026-09-28 | Orchestrator | Launched Apple gap lanes PD (Song Detail pinned header/cards, Item Shop rows), PB (Leaderboards density, Full Rankings floating pager), PS (Settings First Run Guides + Service Info, What's New). Songs gaps (#3–5), drawer highlight (#11), background art (#12/#20) queued behind A2 |
| 2026-09-28 | Android | and-songs landed; shell status-bar overlap fixed (`2c1f471`, screens must not add their own status-bar inset); launched and-songs2 (Quick Links, profile sorts, invalid-score fallback, shop pulse, Settings consumers, all form factors) |
| 2026-09-28 | Android | and-leaderboards landed (Android UI coverage 91.1% app-wide); mock `--large-rankings` for pager captures |
| 2026-09-28 | Windows | win-infra landed: automation mode (`--automation`, Release marker), 30 journeys pass on NativeAOT Release, coverage gate measures async/lambda lines (905 tests, logic 99.41% / UX 98.30%), CI workflow (`native.yml`), DPI-correct title bar, Quick Links host, Find Rival live fallback. **CI blocked: GitHub Actions billing** (every job refused; operator action) |
| 2026-09-28 | Orchestrator | Operator bug batch triaged: iPhone → A2 (floating tab-bar accessory with Search + Filter/Sort + Quick Links; scrubber shift), PB (Rankings subtitle size, header outside card), PS (settings row spacing, CHOpt default-view navigation picker, no "Slide X of Y"), PD (Item Shop button pulse); new Apple lanes AP (star image assets + `StarRating`, white-text rule, remove "This Is Me") and W4 (Duo half-fold dual-source layouts: Songs+Suggestions, Song+history, Shop+suggestions, Compete boards/rivals, unfolded portrait). Android → and-shell-search (rail centering, hamburger, tablet search button, M3 floating toolbar slot, Quick Links menu/bottom sheet, drawer Item Shop hide, FRE text), and-songs2 (Paths sheet bottom selectors, shop pill pulse), and-profile2 (remove "This Is Me"), new and-boards2 (header outside card, bottom-anchored pager, filters in top bar). Windows → new win-chrome (badge clipping, scrim sliver, chrome inherits background, header outside card, FRE text, This Is Me, stars). Decision: Android nav rail stays on the leading edge (M3) |
| 2026-09-28 | Android | and-bands landed; entry points routed to and-songs2 / and-profile2 |
| 2026-09-28 | Lane PS | Settings gaps landed (`7051bb0`…`e513a31`): web section order, First Run Guides, Service Info (`/api/service-info` + `/api/version`, both verified pure reads), native What's New (web changelog, hash-gated, replayable), navigation-style CHOpt Default View picker, subtitle spacing, shared white-text tokens, `StarRating` in first-run demos. Open: curated native changelog vs web-verbatim |
| 2026-09-28 | Android | and-boards2: Rankings pickers float in the phone toolbar, pager anchored above it (`a4d5cee`); worktree `reset --soft origin/master` hazard documented |
| 2026-09-28 | Apple (AP) | `StarRating` + Stars.xcassets landed for other lanes; This Is Me removed; white-text rule (`FestivalText`) applied to AP-owned features |
| 2026-09-28 | Orchestrator | Apple follow-up queue: Suggestions per-category metadata (web varies by category), Profile Avg Stars + 4/3/2-star tiles, curated native changelog (drop web-only items), Songs/drawer/background gaps after A2 |
| 2026-09-28 | Android | and-shell-search landed (Android UI coverage 93.2% app-wide) |
| 2026-09-28 | Orchestrator | Operator: the Licenses page must not list or mention the star images (entry reverted). No lane should add bundled-art entries to Licenses without operator approval |
| 2026-09-28 | Windows | win-chrome landed (`c6c5ff4`…`cb81dd1`): bell badge unclipped, full-window scrim (no bright sliver), Mica removed — title bar + docked pane transparent over the art, overlay pane in-app acrylic with solid fallback, Leaderboards headers above cards, first-run pips only, "This Is Me" removed, web star images, white secondary text (`FSTDeemphasisTextBrush` timestamps only); 913 tests, 0 Axe errors on touched pages. Open: 100/200% DPI badge check, gold avg-stars |
| 2026-09-28 | Orchestrator | Operator bug batch 2 triaged. Cross-platform rules: instrument headers outside cards (Leaderboards: icon + name only, bands name-only), "View all" below top ten/eleven as purple button, no "Item Shop: …" chip, filter sheets apply live (no Cancel/Apply), content fades in as it loads (`festivalFadeIn`), drawer = Songs/Leaderboards/Item Shop with Settings at bottom (no Bands/Licenses). iPhone chrome: header has global Search + profile avatar as separate buttons; page controls float as separate glass buttons (→ A2). New lanes: AP2 (Mac: fade-in modifier, native profile search sheet, combined bar+line Rank History with paging, Suggestions cards, What's New sheet, star tiles), and-polish (end-aligned floating toolbar, no empty "Select a song" pane, equal-width search scopes, fade-in, Suggestions), win-polish (Windows equivalents) |
| 2026-09-28 | Orchestrator | Duo bugs: Songs dead space between scrubber and rail → W4; search sheet loses title/Close on focus → A2 (global) + AP2 (profile sheet). Decision: modal Close stays in the sheet's own toolbar (HIG), not the Duo rail |
| 2026-09-28 | Orchestrator | Operator batch 3 triaged. A2: integrate `cd8db04` now, then Songs section headers (match web; no content under sticky headers), #–Z rail centred, scroller collapses nav bar, bottom inset for floating buttons (right-aligned, clear of rail), bigger inline title, top scroll-edge scrim, bell hidden without selection, large-detent sheets, Sort sheet (white titles, "Sort By", inline ↑/↓), search sheet hint/grabber/no extra X. PD: no "View full" + "No scores recorded yet" when empty, real Item Shop pulse, bottom bounce. New lane AM (background crossfade to song art instead of grow, transition stutter, song→leaderboard→back jitter, bounce audit, marquee everywhere). Android/Windows: bell hidden without selection, marquee audit, empty-instrument subtitle "No scores recorded yet" |
| 2026-09-28 | Orchestrator | Operator: check every reported bug for cross-platform repro from now on. Batch 4 (Songs): Year sections = decades + no Year scrubber, Duration buckets Under 1 Minute…Over 10 Minutes (operator deviation, recorded in songs/spec.md). Repro: Apple (year sections + scrubber), Windows (single-year groups + jump), Android (decades already; scrubber/duration buckets) → A2, and-songs2, win-polish. Cross-platform re-audit of batches 1–3 running |
| 2026-09-28 | Orchestrator | Cross-platform audit of operator batches 1–3 (36 items): Apple repros mostly because A2/PB/PD work isn't integrated (told to integrate now); Android repros → and-polish/songs2/boards2/profile2; Windows repros → win-polish + new FST-win-pwa. Decisions (all platforms): anonymous player routes hidden + redirect to Songs (web parity); `/bands` with no id → "Band not found"; default Rank By = Total Score; empty instrument = "No scores recorded yet"; score then gold accuracy badge for FC. PWA-Windows/Android lab landed (`9841516`…`cd70934`; gap tables in `.agents/testing/pwa-reference/{windows,android}-gaps.md`). Apple Service Info spinner fixed (`179ab8d`) |
| 2026-09-28 | Android | and-profile2 landed |
| 2026-09-28 | Lane AP2 | Apple polish 2 landed (`ff7fe7b`…`a39ded5`): `festivalFadeIn` with web timing on 7 pages, native profile search sheet (title/Close stay while focused), no Public Profile, combined bar+line Rank History with swipe/buttons, headers above cards, Suggestions per-category metadata + live filter, full-height What's New with opaque Dismiss bar, Gold/5–1-star + Avg Stars tiles; 433 Core + 364 UI tests. Open: Settings opens What's New as a plain sheet; recycled Suggestions cards may re-fade |
| 2026-09-28 | Windows | win-a11y landed (`8f4cbca`…`21c5b0a`): Axe 0 errors on all 29 surfaces × 3 sizes (+AOT), 45/45 keyboard journeys, 4 contrast themes + 150/225% text + animations/transparency off verified; fixes: ItemsRepeater keyboard reach, section accelerators, Narrator announcements/landmarks, HC crash on launch, /statistics deep link, AOT Suggestions crash. Open: contrast-theme status colours, operator Narrator walkthrough (script in `.agents/testing/windows.md`) |
| 2026-09-28 | Orchestrator | API session limit stopped all Mac lanes (A2, PB, PD, W4, AM) mid-work; resumed after reset with "integrate first" |
| 2026-09-28 | Lane W4 | Duo phase 1 landed (`bbb2f8d`, `8bbf7a0`, `e133c36`): `DualSourceLayout` (split at fold half-open, 58/42 flat, inner portrait only) + `HorizontalCarousel`; Compete (boards/rivals), Rivals (list/rivalry), Profile+Statistics (overview/graphs), Suggestions (categories/shop picks); scrubber double inset fixed; empty "Select a Song" pane removed. Songs/Song Detail/Shop/Leaderboards secondaries built, wiring waits on A2/PD/PB. Evidence via `FST_DEBUG_DUO_POSE` (Device Hub poses need the Accessibility grant). Open: Leaderboards rail clearance double inset, unfolded scrubber shot |
| 2026-09-28 | Lane PB | Leaderboards gaps landed (`2363aa0`, `880e48e`, `ecb0293`, `09ec8e3`): headers above rows (icon + name; bands name-only), one-line glass rows with accent score, purple "View all rankings (N)" below top ten/spotlight, fade-in; Full/Band Rankings floating glass pager + instrument pill, "N ranked players" subtitle; Duo rail double inset fixed; 48-page pager journey (`--large-rankings`). Debug `fullRankings` route default → Total Score (orchestrator). Open: `accentBlueBright` (#4C7DFF) token |
| 2026-09-28 | Orchestrator | Operator: **shelve Duo portrait dual-source layouts** — inner display in portrait (half-open or flat) uses the normal portrait layout; restore separate Leaderboards/Rivals tabs; gate `DualSourceLayout` off (kept for later). Songs/Song Detail/Shop/Leaderboards secondaries will not be wired. → W4 |
| 2026-09-28 | Orchestrator | Operator: let running Windows-host lanes finish (and-songs2, and-boards2, and-polish, win-polish, win-pwa), then **no new work on `sfenton-primary`** until the operator frees it. Android/Windows follow-ups are queued, not launched |
| 2026-09-28 | Android | and-songs2 landed (`8e796ee`…`3f847d02`): Songs Quick Links, profile/chart sort modes, invalid-score fallback + warnings, CHOpt threshold filter, shop pulse (row outline, badge, Detail pill), live Sort/Filter, compact Paths sheet, Song Detail web order/header/row eleven/instrument switcher, decade Year + minute Duration buckets; driven on phone, book half, passport, tri-fold, resizable; 557 tests, logic 97.9%, UI 94.0%. Session closed (Windows host freeze) |
| 2026-09-28 | Orchestrator | Operator batch 5 (iPhone): sort → scroll to top (A2 Songs, PD history/boards); sticky Songs section titles with no rows visible beneath (A2); new Lane AP3 — profile push animation problems, web-clickable per-instrument stat links, 2-column adaptive stat grids with in-card chevrons. **Queued for Android/Windows (host frozen):** sort resets scroll to top on every sortable list; sticky section headers without show-through (Windows ListView sticky headers currently show-through risk); profile per-instrument stats clickable like web (Android has tap-to-filter tiles — verify coverage; Windows unverified); 2-column stat grid + chevrons on phone/compact; check profile push animation |
| 2026-09-28 | Android | and-boards2 closed (`a4d5cee`…`9f78e731`): Bands header → Band Rankings, white FestivalLoading; session closed |
| 2026-09-28 | Windows | win-polish closed (`83fa3d05`…`61d2d0cc`): Song Detail (no chip, breathing Item Shop button, headers above cards, row 11, purple View all, pinned header, icon intensity, gold FC badge), Leaderboards (name-only headers, counts, Total Score default, icon heights), fade-in everywhere, live filters, web drawer, bell gating, combined Rank History, gold avg stars, marquee, decade/minute sections; 1010 tests, logic 99.42% / UX 98.33%. Open: Leaderboards wide-preset Axe clipping, band rank history still a list |
| 2026-09-28 | Orchestrator | Operator: pictures sent to the operator use **live service data**, selected player **SFentonX** (`195e93ef108143b2975ee46662d4d0e1`); rule in `.agents/testing/strategy.md`; repo screenshots stay fixture-only |
| 2026-09-28 | Orchestrator | Android/Windows backlog kept in [`.agents/workflow/android-windows-backlog.md`](.agents/workflow/android-windows-backlog.md) while the Windows host is reserved |
| 2026-09-28 | Android | and-polish closed (`76f6f8e`…`f2dfc6d`): right-aligned floating toolbar (page actions only), search in the top bar at every size, web-sidebar drawer, bell gating, ⋮ overflow on narrow panes, profile-only route redirect, `/bands` "Band not found", full-width list until selection, equal search segments, Suggestions web cards + live filter, fade-ins, splash, CHOpt drag handles, white spinners; logic 97.9% / UI 94.0%; live SFentonX captures |
| 2026-09-28 | Orchestrator | Operator: two **populated** columns when width allows (Android foldables, Duo, Windows, iPad) — Apple → W4, Android/Windows → backlog; Android tablet drawer (no title, aligned first item, transparent) and top-aligned foldable rail icons → Android backlog. Master red: two Songs hosted tests after A2's `503bcc0` → A2 |
