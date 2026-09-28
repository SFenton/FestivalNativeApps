# Songs (`/songs`) — spec

> **What:** platform-neutral web behavior of the Songs catalogue page: inputs, states, controls, nav edges, test matrix. **Read when:** changing Songs on any platform. Platform notes: [ios.md](ios.md) · [ipados.md](ipados.md).

Source: `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx:340-1380`, `src/hooks/data/useFilteredSongs.ts:66-313`, `src/pages/songs/modals/{SortModal,FilterModal}.tsx`, `src/pages/songs/components/{SongRow,InvalidScoreIcon}.tsx`. Reflects a dirty source worktree; check the [source snapshot](../../workflow/source-of-truth.md) before asserting parity.

## Inputs and flow

- `GET /api/publication`, then conditional `GET /api/songs` (ETag/304 accepted only within that publication).
- A selected **player** adds profile scores / FC / valid-score substitutions; a selected **band** adds band song rows, member intersections and band-combo assignments (band reads are blocked: [service safety](../../platforms/service-safety.md)).
- Shop data, nine visible instruments, eight metadata toggles and saved song-filter state affect rows and the Sort/Filter options.
- Search debounces 250 ms. A row opens `/songs/:songId`, appending `?instrument=` when filtered. The invalid-score warning is a **separate accessible action** that explains fallback/over-threshold status and can navigate to Settings.

## Navigation

- No profile: Songs, Leaderboards, Settings tabs. A player or band adds Suggestions and Statistics; Compete/Rivals rules in `BottomNav.tsx:45-100` ([app-navigation](../../controls/app-navigation/spec.md)).
- Re-tapping Songs returns to the tab root; leaving and returning restores the prior nested route.
- Web mobile layout: the header owns profile/add and global search; Search/Sort (and Filter when a player or band is selected) live in a lower dock (`FortniteFestivalWeb/src/App.tsx:1011-1107`, `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx:1112-1150`, `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx:1122-1136`). A page-specific "Filter Songs" first-run carousel appears over selected Songs.

## Controls and states

| Control | Reachable states and dependent effects |
|---|---|
| Catalogue/list | loading, error, no results, populated, publication changed; sections, virtual rows (web estimates 122/68, overscan 8), quick-link scroll, restored position |
| Search | empty, typing (250 ms), matching, punctuation/diacritics, no results; changes list and quick-link groups |
| Instrument | all / one of nine visible charts; changes score validity, row chips, Sort/Filter modes and Detail's initial instrument |
| Sort | [songs-sort](../../controls/songs-sort/spec.md): title and conditional score/percentage/season/FC/difficulty/shop/band modes, direction, priority reorder; draft/discard/apply/reset |
| Filter | [songs-filter](../../controls/songs-filter/spec.md): instrument and member/FC/score/shop/difficulty/season/percentile/stars; band conflicts block Apply; no-profile mobile has no Filter action |
| Row (selected player) | icons on + unfiltered → [instrument status chips](../../controls/songs-instrument-status-chips/spec.md); icons off or one chart → [score metadata](../../controls/song-score-metadata/spec.md) |
| Shop accents | [shop-offers](../../controls/shop-offers/spec.md): New/Leaving red/gold row borders |
| Score warning | valid / valid fallback / no valid fallback / over threshold; modal action distinct from row navigation |
| Artwork | [artwork-background](../../controls/artwork-background/spec.md) |

Row content details: SongInfo appends a positive formatted duration after artist/year (`FortniteFestivalWeb/src/components/songs/metadata/SongInfo.tsx:21-35`, `FortniteFestivalWeb/src/utils/formatters.ts:18-27`); missing/non-positive duration shows nothing. Icons-off selected cards show score right, a skewed gold accuracy badge, a Top-N% bucket and stars/season/intensity/difficulty (`FortniteFestivalWeb/src/pages/songs/components/SongRow.tsx:49-90,173-269`, `FortniteFestivalWeb/src/components/songs/metadata/ScorePill.tsx:17-35`); icons-on unfiltered rows suppress per-chart metadata for status chips (`FortniteFestivalWeb/src/pages/songs/components/SongRow.tsx:191-200,264-271`, `FortniteFestivalWeb/src/components/display/InstrumentIcons.tsx:110-122`). Percentile derives from `rank/totalEntries` using the Songs buckets (`packages/core/src/app/formatters.ts:74-83`).

## Intentional native corrections (all platforms)

- Keep missing scores last in **both** sort directions; normalize expanded accuracy by 10,000 before 90–100% quick-link buckets. The PWA reverses missing-score placement and compares raw accuracy with percent thresholds (`src/utils/songSort.ts:4-9`, `src/pages/songs/songQuickLinks.ts:269-283`). Not pixel-parity evidence.
- Hiding Shop disables effective highlighting/filters and a stale saved Shop sort but preserves the preference.
- Never project a newer Shop feed or selected-player score index onto retained older rows; show a readable paused state ([AGENTS.md invariants](../../../AGENTS.md)).
- Zero score = "no score", never "Score 0". HTTP 200 does not prove an account is registered.

## Accessibility order (target)

Header profile, search, notifications → page title → search, Sort, conditional Filter → section headers and rows (warning buttons separate) → quick-link index → tab navigation.

## Test matrix

Control-to-control propagation; modal draft confirm and focus restore; filtered-row deep link; screen-reader labels; narrow/regular widths; actual motion; publication change clearing routes/filters; retry of a failed list when the tab becomes visible again. Profile POSTs are fixture-only.

## Open gaps (all platforms)

Band rows and assignments; invalid-score fallback variants (`ml`/`vs`/`rt`) and the warning action; metadata order editing; profile/FC/band Sort modes; remaining Filter sections; quick-link rail; first-run carousel; conditional profile tabs. Per-route gap text: `python3 tools/parity_backlog.py --list`.
