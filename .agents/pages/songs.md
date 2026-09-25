# Songs (`/songs`) - not yet certified

Source: `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx:340-1380`, `src/hooks/data/useFilteredSongs.ts:66-313`, `src/pages/songs/modals/{SortModal,FilterModal}.tsx`, `src/pages/songs/components/{SongRow,InvalidScoreIcon}.tsx`. This spec reflects a dirty source worktree; see the source snapshot before asserting parity.

**Input and flow:** `GET /api/publication`, then conditional `GET /api/songs` (ETag/304 accepted only within that publication). A selected player adds profile scores/FC/valid-score substitutions; a selected band adds band song rows, member intersections and band-combo assignments. Shop data, nine visible instruments, eight metadata toggles and a saved song-filter state affect rows and sort/filter options. Search debounces 250 ms. A row goes to `/songs/:songId`, appending `?instrument=` when filtered. Its invalid-score warning is a *different accessible action* that explains fallback/over-threshold status and can navigate to Settings.

**Mobile navigation:** no profile means Songs, Leaderboards, Settings; a player or band enables Suggestions and Statistics, with Compete/Rivals rules described in `BottomNav.tsx:45-100`. Re-tapping Songs returns to the tab root; switching away/back restores its prior nested route. On iPad and Duo let native size classes and safe areas place bars instead of copying the web's uncommitted viewport detector.

**Controls and state transitions:**

| Control | Reachable states and dependent effects |
|---|---|
| Catalog/list | loading, error, no results, populated, warm offline/stale, publication changed; sections, virtual rows (web estimates 122/68, overscan 8), quick-link scroll and restored position |
| Search | empty, typing (250 ms debounce), matching, punctuation/diacritics, no results; query changes list and quick-link groups |
| Instrument | all / one of nine visible charts; changes score validity, row chips, sort/filter modes and Detail's initial instrument |
| Sort | title and conditional score/percentage/season/FC/difficulty/shop/band modes, direction, priority reorder; modal draft unchanged/changed/discard-confirmed/applied/reset |
| Filter | instrument and member/FC/score/shop/difficulty/season/percentile/stars; band conflicts block Apply, shop-hidden removes choices; no profile has Sort but no Filter dock action |
| Score warning | valid / valid fallback / no valid fallback / over threshold; modal action distinct from row navigation |
| Artwork | randomized animated, reduced motion, Save-Data, invisible/paused, no art; see `../controls/artwork-background.md` |

**Intentional source corrections:** keep missing scores last in both sort directions; normalize expanded accuracy by 10,000 before 90–100% quick-link buckets. The PWA currently reverses missing-score placement and compares raw accuracy with percent thresholds (`src/utils/songSort.ts:4-9`, `src/pages/songs/songQuickLinks.ts:269-283`). Do not call these bug fixes pixel-parity evidence. Hiding Shop disables effective highlighting/filters and a stale saved shop sort but preserves the preference for re-enabling.

**Accessibility/test order:** header profile, search, notifications; page title; search, Sort, conditional Filter; section headers and rows with separate warning buttons; quick-link index; tab navigation. Test control-to-control propagation, modal draft confirm/focus restore, filtered row deep link, VoiceOver/TalkBack/Narrator labels, visual states at narrow/regular widths and actual simulator motion. All profile POSTs are fixture-only pending separate service authorization. The current Apple slice implements a fixture-backed, title-ordered Songs list, search, a scene-owned instrument filter retained across iPad/macOS section switches, native Detail/solo navigation, and an accessible notice when a changed publication or hidden instrument clears a route/filter. A headerless response is labeled **live but unverified**; it has no offline fallback yet. Profile rows, Sort/Filter modals, quick links, persistent cold-launch filter state and most page states remain `pending`.
