# Player profile — Windows notes

> **What:** what the Windows player page (`/player/:accountId`) implements, its layout decisions and open gaps. **Read when:** changing `windows/Festival.App/Controls/PlayerProfileView*`, `Pages/PlayerProfilePage*`, `PlayerProfileViewModel` or the player Core reads. Behavior reference: [ios.md](ios.md) (spec.md is still a stub); Statistics reuses this view: [statistics/windows.md](../statistics/windows.md).

## Reads (all keyless; see [service-safety](../../platforms/service-safety.md))

| Data | Endpoint | Client |
|---|---|---|
| Compact scores (202 = syncing) | `GET /api/player/{accountId}` | `FestivalApiClient.GetPlayerProfileAsync` → `PlayerProfilePayload` (header-verified `PublicationId`, observed generation) |
| Global rank (404 = unranked) | `GET /api/rankings/{instrument}/{accountId}` | `GetPlayerInstrumentRankingAsync` (`PlayerInstrumentRanking : AccountRankingEntry`; blank live `instrument` accepted) |
| Rank history (30 days) | `GET /api/rankings/{instrument}/{accountId}/history?days=30` | `GetPlayerRankHistoryAsync` |

Never player-stats: overview/instrument stats and percentile buckets are computed client-side (`PlayerStatistics`, mirroring the web's `playerStats.ts`). `ReadPinnedResponseAsync` accepts a documented 202 without publication checks and never caches it.

## Layout (operator batch 6, 2026-09-28: separate cards like the web)

- One `ScrollViewer` (max 1280 epx): the name title row, **Overview** heading + stat cards, then per Settings-visible instrument a header (36 epx icon + title, above its cards), its **Rank History** card, its stat cards and its **Percentiles** table card, then the inline **Bands** section. Unplayed charts show a single empty-state card.
- **Stat cards** (`Controls/PlayerStatTileView`, web `StatBox` in the `autoFitDetailCards` grid): every stat is its own card in an `ItemsRepeater` + `UniformGridLayout` (min 180 × 88 epx, max 4 columns): **2 columns at compact (500 epx), 4 at medium/wide** (Apple AP3 `StatGridColumns`). Value (20 epx bold, web colour: accent blue, gold, green when every catalogue song is played) over an uppercase label. A **linked** card is a `Button` with an in-card trailing chevron and a help text naming the destination; a plain card has no chevron and is one static element.
- Instrument card order follows the web `InstrumentStatsSection`: Songs Played, Full Combos (only when > 0), Gold / 5 / 4 / 3 / 2 / 1 Stars (non-zero only), Avg Accuracy, Avg Stars, Best Rank, then **Global Rank / Total Score / Percentile**, which sit in the grid from the first frame as dimmed "—" placeholders and update in place (`PlayerStatTile` is observable; tiles keep their identity), "Unranked" on 404, "—" plus a Retry line on failure.
- **Rank History card**: the combined chart (`Controls/RankHistoryGraph` + Core `RankHistoryCombinedChart`, web `RankHistoryChart`/`GraphCard`: Total Score bars coloured by placement, the `#4C7DFF` rank line on a reversed right axis — best rank at the top, padded like `getRankHistoryDomain` — legend, and pages of 96 epx bars with older/newer buttons `fst.player.rank-history.<chart>.older|newer`, arrow keys, wheel and swipe). Axis gutters are measured from the scaled tick labels (RankHistoryCombined.AxisGutter); in contrast themes the bars are opaque with a WindowText outline and the gridlines use WindowText (issue #204). While the read runs the card shows a spinner in a 376 epx area (the loaded chart's height) so nothing below moves; it hides for charts with no ranked snapshots and shows Retry on failure.
- **Percentiles card** (`Controls/PlayerPercentileRowView`, web `PlayerPercentileTable`): PERCENTILE | SONGS header, one row per non-empty band with a "Top N%" pill (gold outline for the top 5%), the count and a chevron, hairline separators.
- **Bands section** (issue #312, web `buildPlayerBandsItems`): `<Name>'s Bands` heading (`FSTSectionHeaderStyle`, level 2) with a trailing **View All** `HyperlinkButton` (section-headers R8, the Rivals header link; spoken "View All, <Name>'s Bands"; never "See All", owner #321) to `AppRoute.PlayerBands(id, All, name)`; then **Duos**, **Trios** and **Quads** (`CardHeader`, level 3), each with up to 6 `BandCardView` cards (the Player Bands card, `LeaderboardsCardGridLayout` min 320 epx, at most 3 columns, `FadeIn.Stagger`), a **No Bands Yet** card when the group is empty and a **View All Bands (N)** frosted card (`Controls/ViewAllCard`: card surface and stroke, 48 epx, centred label and in-card chevron, web `BandViewAllCard`; [surface-materials](../../patterns/surface-materials.md) R7, never the purple `FSTViewAllButtonStyle`; label and name from `ViewAllCta`, view-all-cta R4) when the group has more than the preview, opening Player Bands on that group (`?group=duos|trios|quads`). Core `PlayerProfileBandsViewModel` reads the keyless `GET /api/player/{id}/bands?group=<g>&page=1&pageSize=6` once per group in parallel (the web's preview comes from player-stats, which is blocked); it is kept across chart-visibility rebuilds and dropped with the profile. One section state: loading ring (`Loading bands`), or `ServiceStatusInline` with Retry when any group read fails; the rest of the profile never waits for it. The Quick Links **Bands** item lands on this section.
- Charts are static XAML shapes redrawn only on data or size change. **Sections and band groups never virtualize (#533):** both repeaters use `LeaderboardsCardGridLayout` as a one-column stack (Compete #276 precedent). Sections differ widely in height (scored charts with Rank History vs. one-line unplayed rows), so a virtualizing `StackLayout` re-estimated the unrealized ones near the page end. The extent shrank and the scroller jumped back (scrollbar to the end landed at 76%, PageDown went backwards), and the Trios and Quads band groups could not be reached. Rank and history reads stay lazy: each section starts them once its `EffectiveViewportChanged` comes within one viewport (`LazySectionReach`, the repeater's old cache reach). The x:Bind template root has no `DataContext`, so the section is resolved through `GetElementIndex`. Unplayed charts read nothing.
- Motion (web page load): spinner until the profile read lands, then the title row, Overview heading and Overview grid fade up 125 ms apart (a page entrance on its scroller, `FadeIn.BeginEntrance` + `FadeIn.Enter`; any scroll or Quick Links jump during it starts every pending fade at once, [load-transition](../../patterns/load-transition.md) R5, #323) while instrument sections stagger through `FadeIn.Stagger`; nothing runs when motion is off.
- Full Combos use the web notation: "N (x.x%)", or the bare count in gold at 100% (never "FC 100%"). Confirmation dialog titles are Title Case ("Deselect Profile?", "Switch Selected Profile?").
- Title row (`TitleRow`, no card or avatar since issue #97): the name as the page's H1 (`FSTPageTitleStyle`, like other pages' in-content titles, `fst.player.name`) with no subtitle (operator 2026-09-28); under it **Select Profile** accent button, **Deselect Profile** solid `#C62828` (web `btnDanger`) and the Quick Links menu, then the paused-selection notice and action error. Overview follows directly. The buttons sit in the shared `controls:WrapPanel` (`TitleActions`, 8 epx both ways, like Rivals' `Commands`), never a horizontal `StackPanel`. A StackPanel can't wrap, so at 225% text in a compact window it clipped Quick Links (issue #285). The notice stays an emphasis `TextBlock` rather than a Fluent `InfoBar`, so it matches the web and the other platforms.

## Stat links (web `StatBox.onClick`; Apple AP3 table)

| Card / row | Web target | Windows |
|---|---|---|
| Overview Songs Played / Full Combos | `/songs`, `defaultSongFilters` + `hasScores`/`hasFCs` on every visible chart, Title | Songs root, same preset (`SongsStatPreset(null, …)`), search cleared |
| Instrument Songs Played / Full Combos | that instrument, `cleanFilters` + one check, Score sort | same preset; **Title** sort (native Songs has no Score sort) |
| Gold / 5…1 Stars | `instStarsUpdater`: stars filter + Stars sort | Songs filtered to that chart and star level (`SongScoreBandFilter.Stars`), Title sort |
| Percentile table rows | `instPercentileBucketUpdater`: one band, sort kept | Songs filtered to that chart and band (`SongScoreBandFilter.TopPercent`), sort kept, ascending |
| Best Rank (overview / instrument) | `/songs/:id?instrument=` | `AppRoute.SongDetail(songId, instrument)` |
| Global Rank | `/leaderboards/all?instrument=&rankBy=totalscore&page=` | `AppRoute.FullRankings(instrument, "totalscore")` (first page) |
| Gold Stars (overview), Avg Accuracy, Avg Stars, Total Score, Percentile tiles | plain / Songs sorts natives lack | plain |

- **Select first** (web `withProfileSwitch`, `PlayerLinkPolicy`): on a viewed player every link selects that player first, after the Switch confirmation when someone else is selected. While selection is paused (unverified or changed publication) Songs links are drawn plain; Song Detail and Full Rankings still open.
- Songs presets are written to the saved Songs state (`AppSettings.SongFilter`, `PlayerScoreFilter`, `ScoreBandFilter`, sort) and `MainWindow.ShowFilteredSongs()` shows the Songs root with its search cleared. The percentile/stars filter is additive Songs state (see [songs-filter/windows.md](../../controls/songs-filter/windows.md)).

## Identity actions (never navigate away)

| Read state | Header |
|---|---|
| Selected account | **Deselect Profile** → `ContentDialog` (Cancel default) |
| Viewed, verified and current, no selection | **Select Profile** (accent), immediate |
| Viewed, another player selected | **Switch to This Profile** → confirmation dialog |
| No `X-FST-Publication-Id` | "Selection is paused" notice (`fst.player.identity-notice`) |
| Publication advanced since the read | "Reload before selecting" notice |

`FestivalSession.SelectPlayer(payload, name)` re-checks `IsSelectable` and seeds the selected scores from the same payload (no second read). The shell diffs its section set in place, so selecting or deselecting keeps the current section (a `Clear()` used to bounce to Songs).

## IDs

`fst.player` (page root), `fst.player.{available,loading,syncing,no-profile,name,subtitle,select,deselect,identity-notice,action-error,overview}` (failures use the shared `fst.service-status.*`), bands: `fst.player.bands-section` (named group, Quick Links anchor), `fst.player.bands` (heading), `fst.player.bands-link` (title-row View All), `fst.player.bands.loading`, `fst.player.bands.retry`, `fst.player.bands.{header,empty,view-all}.<duos|trios|quads>`, cards `fst.player-bands.row.<bandId>`, `fst.player.instrument.<ServiceId>` (the section heading), `fst.player.section.<ServiceId>` (the section's named `AccessibleGroup`, e.g. "Lead, group"), `fst.player.instrument-empty.<ServiceId>`, `fst.player.rank-history.<ServiceId>` (`.loading` while the read runs), `fst.player.percentiles.<ServiceId>` (table heading), `fst.player.stat.<overview|ServiceId>.<key>` (keys `songs-played`, `full-combos`, `gold-stars`, `stars-<1…5>`, `avg-accuracy`, `avg-stars`, `best-rank`, `global-rank`, `total-score`, `percentile`), `fst.player.percentile.<ServiceId>.<top>` (table rows).

UIA gotcha: `Border`, `StackPanel`, `ItemsRepeater` and `UserControl` are not in the control view, so an AutomationId set on them never reaches the tree. IDs live on headings, repeaters, buttons and text; `PlayerProfileView` supplies its own group peer so the page roots `fst.player`/`fst.statistics` are findable. Each instrument section is wrapped in an `AccessibleGroup` named after the instrument (issue #221): without it, its tiles and percentile rows were focusable siblings of the Overview tiles with the same name and type ("Songs Played: 2"), which Axe.Windows flags (`SiblingUniqueAndFocusable`) once both are on screen (wide at display 100%/150%).

## Tests

- Core: `PlayerDataTests.cs` (wire decode/validation, client reads, session selection), `PlayerViewModelTests.cs` (page/instrument/history view models, charts, flyout, launch options), `PlayerStatLinksTests.cs` (presets vs. the web updaters, link routes, select-first policy, tile/row state, follow flows), `SongScoreBandFilterTests.cs` (band maths, Songs pipeline/draft/deselect) and `LazySectionReachTests.cs` (sections read within one viewport, #533).
- UI journeys: `python tools/windows/journeys/profile.py [names…] [--exe …] [--shots dir]`. All are UIA-only (`invoke`/`select`/`reveal`), so they run on a locked console:
  - **select**: route-launch a player → select → Statistics → deselect.
  - **restart**: selection persists across a restart.
  - **links**: a viewed player's Songs Played selects them and opens filtered Songs.
  - **rank-history**: Older/Newer page the Lead chart's date range.
  - **instrument-links**: a revealed percentile row opens the Songs Filter preset.
  - **syncing**: the syncing state.
  - **bands-scope**: the Bands scope.
  - **bands-section** (issue #312): fixture-player-1's inline Bands section shows the Duos, Trios and Quads headers. Duos and Trios show 6 preview cards plus **View All Bands (18|8)**; Quads shows all 4 cards and no View All. The Trios View All Bands (8) is the frosted card (paint probe: no purple fill, a white chevron right of the centred label). Duos View All opens Player Bands on Duos, the title-row View All opens it on All, and a card opens the Band page.
  - **bands-empty**: fixture-player-2 shows **No Bands Yet** in every group, with no cards and no View All. A second phase scrolls the page to 100% and requires the Quads empty state on screen, with Narrator order heading → Duos → Trios → Quads (#533: virtualized sections pulled the end back to about 76%, found at the 1080p CI runner's 800×1032 portrait-tablet window).
  - **bands-retry**: with `rivals_fixture.py --player-bands fail-once`, every group read fails once. The section shows Retry while the rest of the profile stays; Retry then loads the groups.
  - The Quick Links **Bands** item lands the section on the shared 32 epx line ([section-jump-landing](../../patterns/section-jump-landing.md) R2). This is asserted in `statistics-quick-links` and in `journeys/quick-links*.json` (`assertinset:id=fst.player.bands-section|id=fst.player.available|32`).
  - **statistics-\***: the Statistics page journeys ([statistics/windows.md](../statistics/windows.md#validation-issue-204)).
- The `history*` journeys in the same file drive the Song Detail score history (`AppRoute.PlayerHistory` opens Song Detail, history sort and states); they belong to that page's validation.
- Accessibility pages in `journeys/a11y.json`: `player`, `statistics`, `player-lead` (the Lead section, revealed) and `player-empty` (an empty instrument).
- Title row (issue #285): `PlayerTitleMarkupTests.cs` checks there is no `PersonPicture`/card, the H1 comes first, the actions sit in the `TitleActions` WrapPanel (select → deselect → Quick Links) and the notice and error follow. `journeys/a11y-profile-title.json` (checked by `tools/windows/tests/test_profile_title_journey.py`) has one page per identity state:
  - `pt-switch`, `pt-anonymous`, `pt-selected` and `pt-notice` (`profile_fixture.py` rollover): name → action or notice → Overview, the H1 12 epx under the title bar, and no other action. Since issue #446 each also asserts the name is a non-focusable `text` element at heading level 1 read as "<name>, text", that no control-view `PersonPicture` exists (the title bar's avatars are `AccessibilityView=Raw`), and that Select/Switch or Deselect is an enabled, invokable `button` at least 40 × 40 epx that Narrator reads as "<label>, button" (`test_profile_title_journey.py` requires all of these).
  - `pt-actions-row` (one row at normal text) and `pt-actions-wrap` (Quick Links below Select at 225% compact).
  - `pt-keyboard-*`: Tab order, plus focus returning after the menu and confirmation dialog.
  - `pt-live-*`: SFentonX on the live service.
  - Run the fixture pages with `--only` (the live pages need `--live --only pt-live-anonymous,pt-live-selected`).
  - CI (issue #446): `tools/windows/ui_ci.py` runs the fixture pages (`PROFILE_TITLE_FIXTURE`) as `profile-title` (compact and medium) and `profile-title-text-225` (compact, 225% text), both with Axe scans, in the `windows-ui` job.

## Validation (issue #199, 2026-10-03)

The live public service was viewed as `SFentonX` with no selected-profile headers. Statistics was checked with that player selected. The fixture is `rivals_fixture.py`. The host console was locked, so actions ran through UIA patterns and screenshots used PrintWindow.

| Configuration | Result |
|---|---|
| Compact 500, medium 900 and wide 1440 epx; maximized; snapped left and right | ✅ Live and fixture: 0 Axe errors. Cards reflow from 1 to 2 to 3 columns; the Lead section and percentile table are reachable by scrolling |
| Light / Dark | Dark ✅. The app is dark-only (`RequestedTheme="Dark"`), so the system Light theme doesn't apply. This is a deliberate brand decision |
| Contrast themes Aquatic, Desert, Dusk and Night sky | ✅ (fixed) 0 Axe errors. Card hover/press surfaces and percentile pills used hard-coded brushes; they now use theme resources with system colours. Charts keep their brand data hues (accessibility Open issue 2) |
| Text 200% (compact and medium) and 225% (medium) | ✅ 0 Axe errors. Tiles wrap and scale |
| Display 100% / 150% | The host runs at a fixed 300% scale. Layout is in epx, so breakpoints match at every scale |
| Keyboard | UIA only (as in #196): every tile, row, chart pager and link is a focusable Button or Image, and SendInput Tab walks can't run on a locked console |
| Narrator / UIA | ✅ (fixed) Each stat tile and percentile row is one stop whose name holds the value. The child texts are Raw: they used to be read twice in scan mode. The Lead chart's Older/Newer buttons kept the previous instrument's IDs after the section repeater recycled them; the IDs are now re-forwarded when they change |
| Automated | Core 1549 tests, coverage 98.9% logic / 97.9% UX; 7/7 player journeys |

## Validation (issue #285, 2026-10-07)

This validates #97's card removal. Live runs viewed `SFentonX` on the public service (anonymous, and as the selected player on Statistics) with no selected-profile headers. Fixture runs used `rivals_fixture.py` and `profile_fixture.py`, with every state in `journeys/a11y-profile-title.json`. The host runs at 300% display scale and the console was unlocked, so real Tab walks ran.

| Configuration | Result |
|---|---|
| Compact 500, medium 900 and wide 1440 epx; maximized; snapped left and right | ✅ Live and fixture: 0 Axe errors. There is no avatar or card: the H1 name sits 12 epx under the title bar, then the action row, then Overview, with no gap |
| Light / Dark | Dark ✅. The app is dark-only (brand decision, as in #199). The light-theme mode run still passes with 0 Axe errors |
| Contrast themes Desert and Night sky | ✅ Live and fixture: 0 Axe errors. Buttons, the notice and tiles use system colours |
| Text 200% (compact, medium, snap-left) | ✅ 0 Axe errors. The actions still fit on one row |
| Text 225% (compact) | ✅ (fixed) "Switch to This Profile" + Quick Links used to clip Quick Links at the window edge in a horizontal `StackPanel`. They now wrap (`TitleActions` WrapPanel), so Quick Links sits below. Live "Select Profile" still fits on one row |
| Display 100% / 150% | ✅ 0 Axe errors at compact, medium and wide (`scale-100`/`scale-150` modes) |
| Keyboard | ✅ Tab goes Select/Switch or Deselect → Quick Links → first Overview tile. Esc from the Quick Links menu and from the Switch/Deselect dialog returns focus to the button that opened it |
| Narrator / UIA | ✅ Reading order: name ("Fixture Player 2", heading level 1), "Switch to This Profile, button", "Quick Links, current section Global Statistics, button, collapsed", "Overview", then the tiles. The paused notice is read between the name and Overview. There is no avatar or image stop |
| Motion | ✅ Live: the title row fades in, then the Overview heading, then the grid (125 ms apart), with no leftover gap |
| Identity states | ✅ Select, Switch, Deselect and the paused notice (fixture rollover) each show only their own action. The action error is reached only through a selection race; markup and view-model tests cover it |
| Automated | Core 2110 tests, coverage 99.0% logic / 98.2% UX; tool tests 403 |

## Gaps

- No experimental rank metrics, no top-songs section, no family/scope Global Statistics cards (they need player-stats, which is blocked); Full Rankings opens on page 1, not the page holding the rank.
- The web keeps one toggle per percentile band and star level; native Songs offers one band and one level (enough for every profile drill-down).
- Compact windows rely on the shell's `NavigationView` `PaneDisplayMode="Auto"`.
