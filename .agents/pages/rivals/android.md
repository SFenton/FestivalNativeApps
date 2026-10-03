# Rivals hub — Android notes

> **What:** the Android Rivals feature (hub, All Rivals, Rival Detail, Rivalry, Find Rival): data, typed scope, adaptive layout, tests and gaps. **Read when:** changing `core|data|presentation|ui/rivals/**` in `android/`. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Data

| Read | Endpoint | Notes |
|---|---|---|
| Song rivals | `GET /api/player/{id}/rivals/{Solo_*\|hexCombo\|pro_drums}` | 404 "no rivals" → empty. Combo token = `RivalCombo.deriveToken` (web `deriveRivalScopeFromSettings`) |
| Leaderboard rivals | `GET …/leaderboard-rivals/{instrument}?rankBy=totalscore` | Experimental metrics are off in production, so no Rank By picker |
| Rival detail | `GET …/rivals/{scope}/{rivalId}?limit=0&sort=closest[&allowLiveFallback=true]`, `…/leaderboard-rivals/{instrument}/{rivalId}?rankBy=&sort=` | 404 → empty. `allowLiveFallback` only when the route came from Find Rival (web `RivalsPage.tsx:261-265`) |
| Rivals for every combo (freeze fallback) | `GET /api/player/{id}/rivals/all` | `FestivalApi.rivalsAll`, unpinned (Suggestions reads it pinned); 404 → empty; echoed account must match. ~8.9 MB live, no client body cap |
| Find Rival | `GET /api/account/search` | Shared `ProfileSearchViewModel`; the selected player is filtered out |

- Reads are **unpinned** (`FestivalApi.readUnpinned` + `ServiceEndpoint.Feature(pinned = false)`, like Apple's `fetchJSON`): Rivals is outside the catalogue publication contract. Rules: [service-safety](../../platforms/service-safety.md).
- `RivalsRepository` (`AppContainer.rivals`) caches successes in-process for 120 s (the service `max-age`, 64 entries); failures are never cached. Several detail scopes are read concurrently and merged (web `fetchCombinedRivalDetail`); one failing scope still shows the rest.
- A 503 freeze uses the shared `RetryingLoader`: inline countdown per card, full-page `ServiceStatusView` when every read of the tab failed. A read already loaded in the last 10 minutes keeps showing when a newer one is refused by a freeze or 503 (`RivalsRepository.STALE_MILLIS`, operator 7.13; the web keeps a loaded rival through its query cache); first reads and bad data still show the error.
- **Cold-freeze fallback (issue #95).** The service never precomputes rival detail, so during a publish freeze every uncached detail is 503 "Published data unavailable" and natives (which never send web's selected-profile headers) can't hit web's published keys. `rivals/all` is precomputed and stays readable, and its per-rival samples are the same stored rows (≤ 200 closest per chart). Chart/combo scopes refused by a freeze or 503 are rebuilt by `RivalsAllDetail.build` (rival's samples across combo entries, scoped charts, deduped, `rankDelta = rivalRank − userRank`, closest-first, `source = "rivals-all"`), one cached `rivals/all` read per player. The Pro Drums family scope (samples lack per-player charts), leaderboard detail, non-503 errors and a rival missing from `rivals/all` keep the original error and its retry state. Samples have no titles: cards already fall back to the catalogue, and `RivalDetailViewModel.category` fills catalogue titles so Rivalry Title sort and Quick Links read correctly. Tests: `RivalsAllDetailTest`, `RivalsViewModelTest.aFrozenDetailRebuildsFromRivalsAllWithCatalogueTitles`.

## Typed scope (no navigation state)

`RivalScope` (`core/rivals/RivalScope.kt`) travels on the routes as `routeToken`: `song:A[,B…]` (2+ = Common Rivals), `leaderboard:<chart>:<metric>`, `combo:<hex|pro_drums>`, `settings:common|combo|all`. `RivalDetailRoute`/`RivalryRoute` also carry `allowLiveFallback`. Debug routes: `allRivals:<scope>`, `rivalDetail:<id>[:<scope>]`, `rivalry:<id>:<mode>[:<scope>]`.

| Opened from | Detail scope |
|---|---|
| Hub/All Rivals per-chart row | `song:<chart>` |
| Common row | `song:<visible charts>` → merged per-chart details |
| Combo row | `combo:<token>` |
| Leaderboard row | `leaderboard:<chart>:totalscore` |
| Find Rival | `settings:all` → web `deriveRivalScopesFromSettings` (pad combo, Pro Strings combo, Pro Drums family, else first chart) + live fallback |
| Bare deep link | web `resolveRivalCombos(null)`: Settings combo, else first visible chart |

Native correction: the web sends the Settings combo for **every** Song Rivals row (so a Bass row with all charts visible opens a Lead comparison); Android, like Apple/Windows, carries the row's own scope.

## Layout

- Hub (`RivalsTab` at ≥ 600 dp, `RivalsRoute` from the drawer): `PrimaryTabRow` Song Rivals / Leaderboard Rivals (leaderboard reads start on first selection; a tab switch runs the shared load swap, issue #71: the old tab fades out, the spinner `fst.rivals.loading` shows until the new tab settles, then its cards stagger in), toolbar Find Rival + Quick Links (shared `QuickLinksAction`, 7.15: web `RivalsPage` items for the current tab once it settles, one per card that loaded rivals — Common Rivals (people), the combo (notes), each chart (its icon); the Leaderboard Rivals tab lists each chart; section IDs are the card IDs, `RivalQuickLinks.hub`). Cards: Common, Combined/Pro Drums Family, then one per visible chart; 3 above + 3 below, **See All** (bold white with a chevron, shared `SeeAllButton`, 6.22) + the shared purple **View All Rivals** button (6.29). Rival rows truncate names with an ellipsis like the web `RivalRow` (never a marquee, 7.14) and end with an in-card chevron when navigable (7.3). Loaded-empty cards are removed; everything empty → web empty copy.
- Rows: 4 dp win/lose tint bar, name (anonymous → "Unknown User", not tappable), "N songs ahead / N songs behind" pills (web `RivalRow`) in a `FlowRow` that wraps the second pill at large text. The tint bar is drawn behind the row (`Modifier.rivalTintBar`, start edge, RTL-aware), **not** sized with `IntrinsicSize.Min`: `FlowRow`'s min intrinsic height ignores wrapped lines, so the row was capped at one pill line and the wrapped "songs behind" pill was dropped at font scale 2.0 (issue #107; `RivalRowUiTest.wrappedPillsGrowTheCardAtLargeText` with native graphics, `RivalsDeviceJourneyTest.largeTextRowShowsBothPills` with device fonts). One merged TalkBack label ("Name, you lead|ahead of you, N songs ahead, N songs behind") with an explicit click action.
- **No "N shared songs" count (owner decision, issue #67 / iOS #40, 2026-10-02):** `RivalRow` deliberately omits the web `RivalRow`'s `sharedSongCount` text and its TalkBack phrase: the count is always ahead + behind. Hub, All Rivals and Compete share this row. `RivalRowUiTest` asserts the label has ahead/behind and never "shared". The Rival Detail summary ("N shared songs · X ahead / Y behind") is unchanged.
- `AdaptiveCardGrid` (`ui/rivals`): `LazyVerticalStaggeredGrid` with ≥ 360 dp columns (1–3; lists 1–2). With a separating vertical hinge (book/passport half-open) exactly two columns meet at the hinge (`HingeColumns`, unit-tested), so no card straddles the fold. Only WindowManager hinge bounds and the grid's window position are used.
- Rival Detail: "You vs. Name" + web `rivals.detail.summary`, category cards (5 songs, sentiment-tinted headings, See All → Rivalry), toolbar View Profile + Quick Links. Rivalry: category songs with a native sort menu (Default, Closest Gap, Your/Their Biggest Leads, Title).

## IDs

`fst.rivals.tab[.song|.leaderboard]`, `.findRival`, `.find.sheet|search|result.<id>`, Quick Links `fst.quick-links.item.<sectionId>`, `.grid`, `.section.<common|combo|Solo_*|leaderboard.Solo_*>`, `.see-all.<sectionId>`, `.row.<accountId>|anonymous`, `.song.<songId>.<instrument>`, `.empty`, `.loading`, `.chooseProfile[.action]`; `fst.all-rivals.list|title|empty|unresolved`; `fst.rival-detail.grid|title|summary|category.<key>|see-all.<key>|view-profile|empty` (Quick Links `fst.quick-links.item.rival-category:<key>`); `fst.rivalry.list|title|sort[.<option>]|empty`.

## Tests

`src/test/.../rivals/`: `RivalsCoreTest` (scopes, combos, common rivals, categories, formatting, columns, routes), `RivalsDataTest` (URLs, 404/503, live-fallback flag, cache), `RivalsViewModelTest`, `RivalsUiTest` (Robolectric: hub → detail → rivalry → song, See All, leaderboard tab, Find Rival, deep link, no player, freeze, unresolvable list). Fixture screenshots: `android/reports/screenshots/rivals-*.png` from `tools/windows/rivals_fixture.py` (anonymized names) with `FST_DEBUG_PROFILE=fixture-player-1:Demo Player`.

## Validation (issue #107, 2026-10, live service, `SFentonX`)

Each AVD was driven with `fst_android.py device drive` (dark/light system theme: the app is dark-only per [design/android.md](../../design/android.md); font scale 1.0/2.0; animator scale 0 unless recording). After the row fix every configuration passed:

| Configuration | Layout | Finding |
|---|---|---|
| FST_Phone portrait | 1 column, `PrimaryTabRow` (scrollable at large text) | Before the fix, font 2.0 dropped every "songs behind" pill; fixed |
| FST_Phone landscape | 2 columns at 1.0; 1 column at 2.0 | At 2.0 the shared app bar + tabs leave ~⅓ of the height for cards; content still scrolls (shell, not Rivals) |
| FST_Tablet portrait / landscape | Rail + 1 column / drawer + 2 columns | Drawer labels wrap at 2.0 ("Leaderboard s", shell) |
| FST_Resizable phone / foldable / tablet / desktop | 1 / 1 / 2 / 3 columns | Desktop showed a live "Scores are updating" card (503 retry countdown) correctly |
| FST_Book_Fold folded / half / unfolded | 1 / 2 split at the hinge / 1 | At 2.0 half-open uses one column across the hinge: deliberate `rememberSingleColumn` rule ([android-accessibility](../../testing/android-accessibility.md)), deviating from M3 "never place interactive content … across the hinge" because half-pane cards wrapped names a few letters per line |
| FST_Passport_Fold folded / half / unfolded | 1 / 2 split / 1 | Font-scale change recreates the activity (fontScale is not in `configChanges`), so the hub briefly shows the spinner while the live read repeats |
| FST_TriFold folded / partial / unfolded | 1 / 1 / 2 | Folded at 2.0 wraps the section title "Lead Rivals" to two lines (no clipping) |

- **TalkBack** (`talkback_walk.py`, phone): top-bar actions → "selected. Song Rivals. Tab. 1 of 2" → "Leaderboard Rivals. Tab. 2 of 2" → per section: heading, "See All: <section>. Button", each row "<name>, you lead|ahead of you, N songs ahead, N songs behind. Button", "View All Rivals. Button".
- **Targets/contrast:** every clickable is ≥ 48 dp (tree bounds); pill text 6.2–6.7:1 on its tinted background.
- **Shell findings (not Rivals):** at font 2.0 the bell's unread badge overlaps the profile avatar in the top bar.
- **M3 review:** primary tabs for top-level content switching, scrollable at large text; 12 dp glass cards and the shared purple buttons follow the repo's design tokens (repo rules win over M3 colour roles).

## Open

- No Rank By picker (production sanitizes experimental metrics off); no pull to refresh.
- Rivals first-run slides and TalkBack pass belong to the accessibility phase.
- Book Fold half-open (`fold-[1038,…]`): re-measured 2026-09-29 (and-next): the card edges sit 27 px either side of the fold (1011 | 1038 | 1065), so the earlier ~17 px offset no longer reproduces.
- Screenshots per form factor (fixture mode): `rivals-*-{phone,bookfold-unfolded,bookfold-half,bookfold-folded,tablet}.png`, `compete-{phone,bookfold-unfolded,tablet}.png`, quantized to 256 colours to stay under 300 KB.
