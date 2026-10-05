# Suggestions — Windows notes

> **What:** Windows (WinUI 3) implementation state, parity evidence and decisions for the Suggestions section. **Read when:** changing Suggestions on Windows or its generator port. Behavior reference: [ios.md](ios.md) (the Apple port is the source of truth until [spec.md](spec.md) is promoted).

## Implemented

| Piece | File (under `windows/`) |
|---|---|
| Generator: line-for-line C# port of the Apple `SuggestionGenerator` (Mulberry32, pipeline list order, emit table + skip streaks, `selectNewFirst`, decade variants, `near_max_*`, all ten `song_rival_*` families, late rival splice) | `Festival.Core/Domain/SuggestionGenerator.cs`, `SuggestionRng.cs` |
| Models: category types (Apple raw values as persisted keys), `SuggestionScore` input (decoupled from the wire `PlayerScore`; `SuggestionScore.Index` adapts the session index), items, categories, season fallback | `Festival.Core/Domain/SuggestionModels.cs` |
| `RivalDataIndex.Build` over `GET /api/player/{id}/rivals/all` (win-rivals' `RivalsAllResponse`) | `Festival.Core/Domain/SuggestionRivalData.cs` |
| Persisted filter (instrument visibility, global + per-instrument type toggles, web cascade rules) and `SuggestionCategoryFilter` | `Festival.Core/Domain/SuggestionFilterSettings.cs` |
| Filter persistence as its own file `%LOCALAPPDATA%\FestivalScoreTracker\suggestions-filter.json` (untouched filter = no file; corrupt/oversize = defaults) | `Festival.Core/Data/SuggestionFilterStore.cs` |
| Row metadata by category key (web `getRowLayout`: rival, UNFC accuracy, season, percentile tier, stars, instrument chips) and Narrator names | `Festival.Core/Domain/SuggestionRowPresentation.cs` |
| Page model: web batching (10 first, 6 per trigger, endless `resetForEndless` remix, 1,000-category cap + Start New Mix), one generator per (player, catalogue, score publication), rivals fetched in parallel and spliced when they answer, filter applied without regenerating | `Festival.Core/ViewModels/SuggestionsViewModel.cs`, `SuggestionsFilterDraft.cs` |
| Page: virtualized `ListView` of Fluent cards; third-from-last realized card loads the next batch; filter `DropDownButton` flyout (Instruments / General expanders, collapsed like the web accordions; Instrument-Specific uses the web **Instrument Selector** with `DeferSelection`, nothing selected on opening, the chart's type switches expanding under it; switches apply live; Reset is the web Modal's full-width red button (batch 7.10); gold tint when active). Rows end with an in-card chevron (›, batch 7.3). The title and Filter action stay hidden behind the spinner until the first cards are ready, then fade in with them (web `headerStagger`, batch 6.41). Each card's title, description and category instrument (36 epx) sit above the card; rows follow the web `CategoryCard` (10 × 24 epx padding, separators between rows only, 34 epx instrument chips with 20 epx icons, 20 epx star images for star-gain categories, marquee titles on hover/focus); cards stagger in | `Festival.App/Pages/SuggestionsPage.xaml(.cs)`, `Festival.App/Controls/SuggestionSongRow.cs` |

States: no player, loading, syncing (202), failed (catalogue or profile; Retry), empty (no suggestions / filtered with Reset Filters), loaded, end-of-mix footer. Rows push Song Detail with the row's (or category's) chart.

## Apple parity evidence

- `tools/windows/suggestion_parity/run_parity.py` compiles the **unmodified** Apple `SuggestionGenerator.swift`, `SuggestionModels.swift`, `SuggestionRivalData.swift`, `RivalsAll.swift`, `ScoreFormatting.swift` and the Instrument/Song part of `SongCatalog.swift` with a small `Shim.swift` (`PlayerScore` fields) and `main.swift`, runs six fixed-seed scenarios over `windows/Festival.Core.Tests/Fixtures/suggestions-parity.json` (140 synthetic songs, 555 scores, 3-combo rivals) and writes `suggestions-parity.expected.json`. It runs with the Swift toolchain on Windows (`winget install Swift.Toolchain --scope user`, installed on `sfenton-music` 2026-09-28) or on the Mac; `--check` compares without rewriting.
- `SuggestionParityTests` asserts Mulberry32 doubles/ints for four seeds, the rival index, and every page of every scenario (228 pages, including endless remixes, late rival data, season 0, `uint.MaxValue` seed) match exactly: keys, titles, descriptions, types, instruments, row IDs, stars, percent, FC, percentile labels and rival annotations. Regenerate the fixture with `make_fixture.py`, then `run_parity.py`, whenever either port changes.
- Order-sensitive details the port must keep: `InstrumentInfo.All` = Apple `Instrument.allCases`; stable sorts (`OrderBy`, never `List.Sort`) where Swift's stable `sorted` has ties (rival gap/protect/spotlight); ordinal string ordering for keyed groups.

## Decisions

- Accuracy stays in expanded units (0–1,000,000) inside the generator, like Apple; `SuggestionSongItem.Percent` is 0–100.
- The filter is a separate file rather than an `AppSettings` field so it does not widen the shared settings model; Settings' future "Reset" should also delete it (open issue).
- The filter follows Settings' visible instruments (batch 6.37): hidden charts are not offered, an open filter rebuilds at once when Settings change, and toggles left off on a hidden chart don't count toward the gold accent, the filtered-empty message or Reset (`SuggestionFilterSettings.IsActiveFor`); they return when the chart is shown again.
- A filter that disables every type skips generation entirely (nothing could show) instead of spinning the generator.
- Filter and global search stay put while the cards scroll (issue #52 check, 2026-10-01): the header Grid (title + `fst.suggestions.filter-button`) sits above the `CardList` and only the list scrolls; UIA rects were identical before/after scrolling at compact, Filter opened while scrolled and Esc returned focus. No change needed.
- **Rival name badge, native deviation (2026-10-02, issue #59 check of #29):** single-rival cards (`song_rival_spotlight_`/`gap_`/`protect_`/`slipping_`/`dominate_`) name the rival in their title, so rows drop the web's per-row name pill and show only the signed delta + icon (`SuggestionRowPresentation.ShowsRivalName`, as Apple). Mixed-rival cards (`song_rival_battleground`, `song_rival_pct_push` and the other cross-pollination families) keep the pill. Narrator still names the rival on pill-less rows: the row's `AutomationProperties.Name` ends "2 ranks behind Rival B1" (`RivalDeltaAccessibilityLabel`); mixed rows keep "rival X, behind by 2 ranks" (singular "rank" fixed at the same time). Verified in the running app with `uiwin.py` screenshots and the UIA tree (fixture mode, seed 1).
- Art: one retry on a failed fetch, and a stale `Unloaded` (WinUI re-parenting) no longer cancels a row's in-flight art load.

## Fixture mode

`python tools/windows/suggestions_fixture_server.py` (port 8766) serves the parity fixture as publication/songs/player/rivals-all plus generated abstract art. Launch Debug with `--base-url http://127.0.0.1:8766/`, `FST_DEBUG_PROFILE=fixture-suggest:Fixture Player` (preselects in an in-memory settings store; never touches the shared settings file) and `FST_DEBUG_SUGGESTIONS_SEED=1`. Screenshots: `windows/reports/screenshots/suggestions-{wide,wide-rivals,medium,compact,filter-medium}.png`.

## Open issues

- Compact (500 px): the shell keeps the `NavigationView` pane expanded, leaving ~350 px of content (shell lane).
- Filter reset is not wired into Settings' Reset; no first-run slides; no scroll restoration across launches (the page and its mix are cached for the session).
- Journey `tools/windows/journeys/paths-suggestions.json` covers the filter's Instrument Selector; `tools/windows/suggestions_journey.py` covers every other reachable state (below).

## Validation (issue #205, 2026-10-03)

Checked with the `winui-design` and `winui-code-review` skills. Fixes:
- The filter's Instruments and General `Expander`s had no UIA name: Axe raised 4 NameNotNull errors with the flyout open. They now carry `AutomationProperties.Name` and HelpText.
- Down/Up on a row scrolled the list instead of moving to the next song. Rows are now one Tab stop per card (`TabFocusNavigation="Once"`, XY keyboard navigation). `CardList.PreviewKeyDown` moves focus Up/Down across card boundaries (`FocusManager.TryMoveFocus` scoped to the list), and Tab moves between cards (`TabNavigation="Local"`). This follows winui-design: arrow keys within a group, Tab between groups.
- The rival pill and the default percentile pill kept brand fills in contrast themes. They now use the neutral pill roles (ButtonFace / ButtonText with an outline), like the accuracy pill.
- The syncing, choose-profile and no-results IDs sat on `StackPanel`s, which have no UIA peer. They moved to each state's title (`HeadingLevel` 2), and the syncing ring is named.

Per configuration:
- **Widths:** compact (500), medium, wide, maximized and resizing across breakpoints all lay out with the filter pinned above the list. Snapped width is covered by compact and medium.
- **Themes:** the app is dark-only (documented deviation in [design/windows.md](../../design/windows.md)), so the system light theme still shows dark. The Desert and Night sky contrast themes use system colours.
- **Text and display scale:** at 200% text, card titles clip into the motion-aware marquee and the full name stays in the row's Narrator name. Display scale 100% and 150% both pass.
- **Keyboard:** the Filter button and cards each take one Tab stop, and arrow keys move between rows.
- **Axe:** 0 errors in every one of the 24 runs: `a11y_matrix.py --only suggestions --scan --tabs 20` in normal, hc-desert, hc-night-sky, light, dark, scale-100, scale-150 and text-200 modes, each at compact, medium and wide. `suggestions_journey.py --axe` also scans the filter, filtered-empty, end-of-mix, loading, syncing and denied states.
- **Not reachable:** the page's no-player panel is defensive. The shell redirects player-only routes to Songs, and the journey asserts that redirect. `fst.suggestions.error` sits on `ServiceStatusView`, which has no UIA peer, so tests use `fst.service-status.{title,retry}`.

## Validation (issue #259, 2026-10-04): rival rows of #59

Rechecked #59 (no rival name pill on single-rival rows) with the `winui-design` and `winui-code-review` skills.

Live public service (SFentonX):
- Spotlight, gap, protect, slipping and dominate rows show only the signed delta and the instrument icon.
- Their row names end with the rival, e.g. "Ride, Epic Games · 2025, Tap Vocals, 1 rank behind MarioFan1993".
- Mixed families such as "FC These to Beat …" (`song_rival_near_fc`) keep the pill, because each row can name a different rival.

Fix:
- **Problem:** the delta's red literal (`#C62828`, from the web) measured 3.0:1 on the card. That fails WCAG 1.4.3's 4.5:1 for text.
- **Change:** the delta now uses the Rivals text roles `FSTRivalWinTextBrush` (#5ED68A) and `FSTRivalLoseTextBrush` (#FF8A80), both above 7:1. The literal brushes are removed. winui-design says: "Hard-coded color literals → {ThemeResource} brushes by semantic name". In contrast themes the roles are WindowText, as before.
- **Deviation:** this is a deliberate colour difference from the web's #C62828. The + or − sign still carries the meaning without colour.

Tooling:
- `suggestions_journey.py --only rival-rows` scrolls to the mixed `song_rival_pct_push` card and the spotlight `song_rival_spotlight_rival-below-1` card (seed 1).
- It checks the dumped UIA tree: the pill is present only on the mixed card, and each spotlight row name ends "… ranks behind Rival B1". It then runs an Axe scan at compact, medium and wide.
- The runner's Axe gate parsed text that `drive` never prints, so it could not fail. It now uses `songs_filter_journey.scan_errors` on the JSON response.
- `suggestions_fixture_server.py` prints its bound port, so `a11y_matrix.py` can start it with `--port 0` for the new `suggestions-rivals` page.

Per configuration:
- **Widths:** fixture `rival-rows` passed at compact, medium and wide; `resize` passed at compact, wide, maximized, snap-left, snap-right and medium. Live SFentonX screenshots were taken at wide and compact.
- **Themes:** in light and dark the app stays dark (documented deviation). In Desert and Night sky the delta is WindowText; the sign still reads without colour.
- **Text and display scale:** at text 200% the delta and icon stay beside the title block without clipping. Display scale 100% and 150% both pass.
- **Keyboard:** `keyboard` passed, and the Tab walks reached 20 in-app stops with no stops outside the app and no traps.
- **Axe:** `a11y_matrix.py --only suggestions` scanned 0 errors in normal, Desert, Night sky, light, dark, scale-100, scale-150 and text-200, at compact, medium and wide.
- **Axe, rival rows:** the new seeded `suggestions-rivals` matrix page (`journeys/a11y.json`: Spotlight card in view) scanned 0 errors in normal, Desert, Night sky and text-200 at compact, medium and wide. The one exception is scale-150 medium, which reported 2 `BoundingRectangleSizeReasonable` findings. They are on one subtitle clipped to zero height at the list's viewport edge, which is WinUI clipping ([windows-accessibility](../../testing/windows-accessibility.md) item 3).
- **Journeys:** the full `suggestions_journey.py` run passed.
- **Loading:** `loading` (an 8 s state) kept expiring while it waited behind other sessions on the shared desktop lock (`LOCK_BOUND`). A later retry passed at medium. It doesn't touch rival rows, and it passed at every width in the #205 run.

## IDs

`fst.suggestions.{filter-button,list,loading,syncing,choose-profile,error,no-results,reset-filters,start-new-mix}` (the state IDs are on the state titles; `error` is not exposed, see Validation), `fst.suggestions.category.<key>[.<mix>]`, `fst.suggestions.row.<songId|songId|Solo_X>`, `fst.suggestions.filter.{form,title,instruments,general,instrument-specific,instrument-picker.{<Solo_X>,compact,previous,next},instrument.<Solo_X>,type.<type>,type.<Solo_X>.<type>,reset}`.
