# Global search (`fst.global-search.*`) — spec

> **What:** platform-neutral web behavior and native contract for the app-wide Search button (songs, players, bands) that is present on every page, plus its states, safety and test IDs. **Read when:** adding or changing the global search entry point, its surface or its results on any platform. Platform notes: [android.md](android.md) · [windows.md](windows.md) · Apple files are owned by Lane A2 (`ios.md`/`ipados.md`/`macos.md`). Endpoint safety: [service-safety](../../platforms/service-safety.md).

Source (web, read-only): `FortniteFestivalWeb/src/components/search/SearchModal.tsx:29-597,599-935`, `src/hooks/data/useUnifiedSearch.ts:55-189`, `src/utils/songSearch.ts:1-31`, `src/types/search.ts:1-7`, `src/components/shell/HeaderActions.tsx:37-107`, `src/components/shell/mobile/MobileHeader.tsx:55-161`, `src/components/shell/desktop/DesktopNav.tsx:24-76`, `src/App.tsx:224-243,547-586,760-777,1022-1080,1402-1418`, `src/api/client.ts:314-318,452-466`, `src/i18n/en.json:346-377`, `packages/theme/src/animation.ts:7`, `packages/theme/src/breakpoints.ts:2-16`. Related: [profile-selection](../profile-selection/spec.md) (same player-search wire rules), [app-navigation](../app-navigation/spec.md) (shell).

## Web behavior

### Entry points

The global entry is a **magnifier icon button in the shell header**, not in the FAB. It is one of the shared `HeaderActions`, in the order profile → **search** → notifications (`HeaderActions.tsx:83-136`), labelled "Search" (`common.searchAction`, `HeaderActions.tsx:97-107`) with web test IDs `mobile-header-search` / `desktop-header-search`. Hover/focus preloads the lazy modal (`HeaderActions.tsx:101-102`, `App.tsx:576-580`).

| Viewport (web breakpoints) | Where the button lives | Notes |
|---|---|---|
| Mobile chrome (≤768 px, or any iOS/Android/PWA) | `MobileHeader` right action group on tab roots (with title) and on detail pages (in the `BackLink` right slot) (`MobileHeader.tsx:87-102,134,158`) | Header returns `null` on the few routes with neither a title nor a back target (`MobileHeader.tsx:161`) |
| Probable Duo outer display | Same actions stacked in the vertical rail (`layout='column'`, `MobileHeader.tsx:101,114-116,144-153`) | |
| Desktop 769–1439 px | `DesktopNav` top bar after the hamburger (`DesktopNav.tsx:67-72`) | |
| Wide desktop ≥1440 px | `DesktopNav` actions over the content column; pinned sidebar on the left (`DesktopNav.tsx:58-66`) | |

The Songs page's mobile **FAB search dock** and desktop **Songs toolbar field** are *not* global search: they filter the Songs list (see "Page-local search").

### Other openers of the same surface (scoped)

| Opener | Scopes | Tap result |
|---|---|---|
| Header Search button | songs, players, bands | Navigate (below) |
| Profile action with no profile; drawer/sidebar "Select Player" | players, bands; placeholder "Search players or bands…" (`App.tsx:224-243,581,760-773,1022,1079`) | Navigate |
| Rivals "Find Rival" | players only, `onPlayerSelect` override (`RivalsPage.tsx:473-478`) | Page-specific callback |

### Query, scopes and fetching

- Scopes, in fixed order: **Songs, Players, Bands** (`types/search.ts:1`). Placeholder names the enabled scopes, e.g. "Search songs, players, or bands…" (`SearchModal.tsx:63-82`, `en.json:348-357`).
- The query is trimmed; under **2 characters** everything clears and the hint "Enter at least two characters to search." shows (`useUnifiedSearch.ts:73-88`, `en.json:360`).
- **250 ms debounce** (`DEBOUNCE_MS`, `animation.ts:7`; `useUnifiedSearch.ts:90-99`). Each new query bumps a request sequence and aborts the previous fetches; late results are dropped (`useUnifiedSearch.ts:130-177`).
- Songs: a local filter over the loaded catalogue, **≤20** results, matching title or artist by raw substring, then by a normalized form (NFKD, diacritics and apostrophes stripped, punctuation → spaces) (`useUnifiedSearch.ts:49-53,106-119`, `songSearch.ts:3-31`).
- Players: `GET /api/account/search?q=&limit=10` (`client.ts:314-318`). Bands: `GET /api/bands/search?q=&page=1&pageSize=10` (`client.ts:452-466`) — **blocked natively**, see below.
- No recent searches, no suggestions in the field, no result persistence: the query and the scope filter reset every time the surface closes (`SearchModal.tsx:161-175,408-415`).

### Results and grouping

- A row of **scope toggle chips** (`aria-pressed`, `search-target-filter-{target}`) appears only when >1 scope is enabled. No chip is selected on open (= all scopes); tapping a chip filters to it, tapping it again returns to all (`SearchModal.tsx:524-544,599-626`). Chips sit **above** results on desktop and **below** them on mobile (thumb reach) (`SearchModal.tsx:576,593`).
- All-scope view: one `<section>` per scope with an `<h3>` heading, in scope order, rendering only scopes that have results **or** an error; if none, "No results found." (`SearchModal.tsx:797-829`).
- Single-scope view: that scope's list, or "No songs/players/bands found." / "Search failed. Try again." centred (`SearchModal.tsx:837-898`, `en.json:361-373`).
- Rows: Songs reuse the Songs row (art, title, artist, no instrument icons or metadata) (`SearchModal.tsx:845-865`); Players are name-only buttons (`SearchModal.tsx:867-878,900-918`); Bands are band cards with member names and appearance count (`SearchModal.tsx:880-897`).

### States and motion

| State | Web |
|---|---|
| Open, short query | Hint centred |
| Debouncing / loading | One spinner for the whole panel; in the all-scope view it waits until **every** enabled scope finishes (`SearchModal.tsx:646-651,740-743`) |
| Loaded | Spinner fades out, then rows fade up with a stagger (first 8 rows) (`SearchModal.tsx:703-738,783-787`) |
| Empty | Scope-specific or "No results found.", centred (`hintCenter`); All hides empty sections |
| Error | Per scope; other scopes still show (`useUnifiedSearch.ts:146-150,166-170`) |

**Native empty state (issue #99):** never an inline left-aligned row. In All, an empty Players section is hidden while Songs has rows (web `shouldRenderGlobalSection`). When the shown scope(s) are all empty, the results area shows a title + subtitle centred horizontally and vertically, like the Songs page's empty state: All "No results found" / "Check the spelling or try a different song, artist or player."; Songs "No songs found" / "Check the spelling or try a different song or artist."; Players "No players found" / "Check the spelling or try a different player name." Issue #299 removed their **Retry** (the field's Search/Enter re-runs the query). At large text sizes the block scrolls. Apple titles use title-style capitalization ("No Players Found"), as Apple's own empty states do; the subtitles are this exact copy.

### Tapping a result

The surface closes, then navigates (`SearchModal.tsx:490-522`):

| Result | Destination |
|---|---|
| Song | `/songs/{songId}` Song Detail (Songs row link, `SongRow.tsx:204`) |
| Player | `/player/{accountId}`; the **currently selected** player goes to Statistics instead |
| Band | `/bands/{bandId}?bandType&teamKey&names`; the selected band goes to Statistics |

Opening a result **views** it; selecting a profile is a separate action on the destination page ([profile-selection](../profile-selection/spec.md)).

### Surface, keyboard and accessibility

- Desktop: centred modal 520×640 (≤90 vh), titled "Search"; the field is focused when the open animation completes (`SearchModal.tsx:29,452-455,547-557`). Mobile: bottom sheet; the panel (not the field) gets focus, so the keyboard does not auto-raise; Enter dismisses the keyboard (`SearchModal.tsx:402-406,553`).
- `ModalShell`: `aria-modal`, Escape closes, Tab/Shift+Tab trapped, focus returns to the opener (`ModalShell.tsx:205,258-285,324`).
- Results region: `role="region"`, "Search results", `aria-live="polite"` (`SearchModal.tsx:577`); scope sections are labelled by their headings.
- **Web gaps:** no global keyboard shortcut; no arrow-key result navigation; Enter does not open a result; the input has only a placeholder (no accessible label); no clear button.

### Page-local search (Songs) is separate

- Songs keeps its own filter text in `SearchQueryContext` (mobile FAB dock field, desktop toolbar field, 250 ms debounce) (`SongsPage.tsx:504-524,1154-1160,1365-1375`; `FloatingActionButton.tsx:110-160`). Global search never reads or writes it, and vice versa; switching profile clears the Songs text (`PlayerContent.tsx:350-362`).
- On mobile Songs both exist at once: header magnifier (global) and FAB dock field (filter).

## Native contract (all platforms)

- **Entry point everywhere.** Every page in every layout exposes one Search action in persistent shell chrome (never inside scrolling content), reachable without leaving the page. On pages that also have a page-local field (Songs), the two must be visually and semantically distinct: global = "Search" (songs, players, bands); local = "Search Songs"/"Filter songs" in the page.
- **One engine per platform** (`GlobalSearchModel` or equivalent in the UI-free core), shared by every opener: query, scope, debounce, cancellation, per-scope results/errors. The profile picker and Find Rival may reuse it with narrowed scopes (players only), but their surfaces stay as their own specs define.
- **Query:** trim; <2 chars → hint, no request; 250 ms debounce; cancel superseded work; drop late results. Player requests follow [profile-selection](../profile-selection/spec.md#native-client-contract-all-platforms) exactly (2–200 chars, `+` → `%2B`, ≤10, keyless, no selected-profile header, reject malformed rows).
- **Songs:** local match over the current catalogue with the Songs page's own text matcher (port of `songMatchesSearch`), ≤20 rows, catalogue order. No network.
- **Loading (issue #299, replaces the earlier "native correction"):** one spinner for the whole surface, centred horizontally and vertically in the area between the scope chips and the bottom nav/keyboard (web `SearchModal` parity). All waits until Songs and Players have both settled; the Songs scope never waits for Players. No inline Players progress.
- **No section titles (issue #299):** the scope chips already name the scope, so results carry no "Songs"/"Players"/"Bands" titles; rows keep their own accessible names.
- **Hint (issue #299):** under two characters the hint names the scope: "Enter at least two characters to search for songs, players, or bands." (All), "… to search for songs." (Songs), "… to search for players." (Players), "… to search for bands." (Bands, before the band explanation).
- **Errors:** per scope, with **no Retry button** (issue #299; the web has none). An empty envelope may mean a server timeout ([service-safety](../../platforms/service-safety.md#endpoint-allowlist)), so submitting the same text again (keyboard Search/Enter) re-runs a failed or empty search; editing the query also re-runs it. The empty state is the centred title + subtitle in [States and motion](#states-and-motion). A public-read freeze 503 shows the [service-status](../service-status/spec.md) "Scores are updating" message in the Players section, never "no players".
- **Navigation:** close the surface, then push the destination on the **current section's** stack (the user's place is kept for Back). Selected player/band → the Statistics section. The query is not restored on Back (web parity).
- **No recent searches, no history persistence** (web parity; also avoids storing account names). See open questions.
- **Accessibility:** the field has a real accessible name ("Search songs, players and bands"); scope chips expose selected state; announce result counts politely once per settled query ("3 songs, 10 players"); no section headings (issue #299); focus returns to the Search button on close; the surface is dismissible by the platform's back/escape gesture.

## Band scope (blocked)

Band search is **not called** by native apps: when its projection is missing, the service's band search GET deletes, rebuilds and upserts band membership rows ([service-safety](../../platforms/service-safety.md#hard-rules)). The Bands scope is therefore **shown but unavailable**:

- The Bands chip is present (so the surface matches the web's shape) and selectable; selecting it performs **no request** and shows, in the results area: "Band search isn't available in the app yet. The service's band search can change stored band data, so the app won't call it until a read-only version exists. Browse bands in Leaderboards → Band Rankings, or from a player's Bands." with a button to Band Rankings (`fst.global-search.bands-unavailable`).
- The all-scope view never shows a Bands section. The placeholder names only live scopes: "Search songs or players…" (web key `search.placeholders.songsPlayers`).
- Lift this only when [service-safety](../../platforms/service-safety.md) lists a mutation-free band search.

## States

| State (`product.json`) | Native acceptance |
|---|---|
| `closed` | Search action visible in every layout's chrome; nothing loaded |
| `open-hint` | Surface open, field focused (keyboard raised on phone only when opened by the user), <2 chars → hint |
| `loading` | One centred spinner below the scope chips; All waits for every live scope; superseded queries cancelled |
| `results-all` | Songs rows then Players rows, no section titles; count announced |
| `results-scoped` | One scope via chip; toggling again returns to all |
| `empty` | Centred scope-specific title + subtitle, no Retry; All hides an empty Players section next to song rows |
| `error` | Per-scope failure message without Retry; other scopes still shown; freeze → "Scores are updating" |
| `bands-unavailable` | Bands chip shows the explanation and Band Rankings link; no request |
| `navigated` | Surface closed, destination pushed on the current section; Back returns to the prior page |

## Test IDs

| ID | Element |
|---|---|
| `fst.global-search.open` | Shell Search action (one per window/scene). Apple iPhone/iPad use a system Search tab or sidebar row instead (issue #92, [ios.md](ios.md)), which has no settable ID |
| `fst.global-search.surface` | The open surface (sheet, expanded search view, flyout or dialog) |
| `fst.global-search.field` | Text field |
| `fst.global-search.clear` | Clear-text control, when the platform field has one |
| `fst.global-search.close` | Explicit close/cancel control, when the surface has one |
| `fst.global-search.scope.{songs,players,bands}` | Scope chips |
| `fst.global-search.hint` | Short-query / empty / error message |
| `fst.global-search.empty` | Centred empty state (Android/Windows; title `.empty.title`, subtitle `.empty.subtitle` on Windows) |
| `fst.global-search.section.{songs,players}` | Section containers (headings inside); removed on Android by issue #299 |
| `fst.global-search.result.song`, `fst.global-search.result.player` | Each result row (repeated; accessible name = title/artist or display name) |
| `fst.global-search.loading` | The one centred search spinner (Android) |
| `fst.global-search.players-loading` | Players inline progress; removed on Android by issue #299 |
| `fst.global-search.players-error` | Players failure / freeze message (Android, Windows) |
| `fst.global-search.retry` | Players / empty-state Retry; on Apple the whole centred empty state of Players and All is this one element (title, subtitle, Retry); removed on Android by issue #299 |
| `fst.global-search.bands-unavailable` | Band explanation block and its Band Rankings button |

## Test matrix

Open from a tab root and from a detail page in every layout · <2 chars · debounce (fast typing = one request) · songs-only match, players-only match, both · diacritics/punctuation song match · players empty envelope + centred Retry empty state (Players scope; hidden section in All when songs match) · all-empty centred title + subtitle · players 503 freeze · players transport error with songs still shown · scope toggle on/off · Bands chip explanation (assert no `/api/bands/search` request in the fixture log) · tap song/player/selected player → destination and Back · close by Escape/back gesture restores focus to the opener · screen-reader names, headings and count announcement · Songs filter text untouched by global search and vice versa.

## Open questions (operator)

- Recent searches: web has none. Add a per-device, clearable recent list (songs and players) or keep parity? Default: parity (none).
- Should native global search also include pages/settings entries ("Go to Rivals")? Default: no, web scopes only.

## Operator decisions (2026-09-28)

- **No recent searches** — web parity; nothing about queries is persisted.
- **Content only** — songs, players, bands (bands shown but blocked with explanation); no pages/settings in results.
- **Android shortcut:** Ctrl+K and the Search key open global search; Ctrl+F remains find-in-page. (Windows: Ctrl+E; Apple iPad/Mac: ⌘F/⌘K per the Apple design.)
