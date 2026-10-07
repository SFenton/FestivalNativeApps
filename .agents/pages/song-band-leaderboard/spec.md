# Song band leaderboard (`/songs/:songId/bands/:bandType`) — spec

> **What:** platform-neutral web behavior of one song's paginated Duos/Trios/Quads board: header, query, states, transitions, reading order and test IDs. **Read when:** changing the song band leaderboard on any platform. Platform notes: [ios.md](ios.md) · [android.md](android.md) · [windows.md](windows.md).

Source (reviewed at FortniteFestivalLeaderboardScraper `35fb5488`): `FortniteFestivalWeb/src/pages/leaderboard/band/SongBandLeaderboardPage.tsx:47-363` (page), `:369-421` (row and `isSameSongBandEntry`); `FortniteFestivalWeb/src/components/songs/headers/SongInfoHeader.tsx:66-163` (header); `FortniteFestivalWeb/src/i18n/en.json` (`songBandLeaderboard.*`, `bandList.groups.*`); route `FortniteFestivalWeb/src/App.tsx:58`. Service: `FSTService/Api/LeaderboardEndpoints.cs:98`.

Patterns: [song-leaderboard-header](../../patterns/song-leaderboard-header.md) (header, board line, bar title, backdrop), [song-header](../../patterns/song-header.md) (title marquee, heading), [leaderboard-row](../../patterns/leaderboard-row.md) (rows, selected band, board columns), [load-transition](../../patterns/load-transition.md) (reloads), [empty-error-states](../../patterns/empty-error-states.md). Rules below link to them instead of restating them.

## Inputs

- `songId` and `bandType` from the route. The web accepts `Band_Duets`, `Band_Trios`, `Band_Quad` (`coerceSongBandType`) and shows "Band leaderboard not found" for anything else. **Native correction:** native routes are typed; a deep link with an unknown size opens Duos.
- `?page=` (1-based, default 1), `?navToBand=true` (reveal the selected band's row after load), `?combo=` (instrument-combo filter; web only, see Open gaps).
- Selected profile: a selected player sends `accountId`; a selected band of this size sends its team key (web only: natives have no selected band). Never as headers ([service-safety](../../platforms/service-safety.md)).

## Query

- `GET /api/leaderboard/{songId}/bands/{bandType}?top=25&offset=(page-1)×25[&accountId=][&teamKey=][&combo=]`: keyless, pure `SELECT`s. Stale time 5 min.
- Response: `entries` (rank, `bandId`, `teamKey`, members with instruments and per-song member scores, team score, accuracy, FC, stars, season, difficulty), `totalEntries`, optional `localEntries`, `showLeaderboardEntryTotals`, `selectedPlayerEntry`, `selectedBandEntry`.
- Page count = `ceil((localEntries ?? totalEntries) / 25)`, minimum 1. A loaded page beyond the last one is corrected to the last page.
- Selected entry = `selectedBandEntry ?? selectedPlayerEntry`. A row is the selected one when `bandId` matches (non-empty), or `bandType` and `teamKey` both match.

## Layout

1. **Song header** (web `SongInfoHeader collapsed hideBackground`, in `Page`'s `before` slot above the load gate): album art, song title, artist, then the **board line**: the band label ("Duos", "Trios", "Quads"; no icon) or, when `showLeaderboardEntryTotals` is true, "{type} • {count} entries". The title area is a link to Song Detail (`onTitleClick`). There is no "<Size> Scores" or "<Size> Leaderboard" page title. Rules: song-leaderboard-header R1, R2, R5.
2. **Band-size control** on the board line where the solo board switches its instrument: natives switch the size in place (page 1, scroll to top). The web reaches other sizes from Song Detail; its header action slot holds the combo filter pill on desktop.
3. **Rows**: one card per band (web `PlayerBandCard` + `SongBandScoreFooter`): rank, each member's instrument icons, name and per-song score (season, stars, accuracy and difficulty on wide layouts), then the team score with FC, accuracy and stars. The selected band's row is highlighted purple. Card gap `Gap.md`. Rules: leaderboard-row.
4. **Selected-band footer** pinned above the pager when a selected entry exists: the band's rank, member names, team score and (wide) season, accuracy and stars, styled as the solo board's selected-player footer.
5. **Pager** (first/previous/info/next/last) when there is more than one page, fixed at the bottom; rows fade out above the footer and pager.
6. **Backdrop**: the song's static, dimmed album art (`PageBackground src={song.albumArt}`), never the animated carousel (song-leaderboard-header R4).
7. **Bar title**: empty while the header is on screen; once it scrolls under the bar, the song title (single-line marquee) with small art and the band label where the platform's bar has room (song-leaderboard-header R3).

## States

| State | Shows | Header and backdrop |
|---|---|---|
| Loading (first load, size change, page change, selected-profile change, Retry) | Rows leave, centered spinner. Natives keep the pager at the last page count, usable, so a newer page tap supersedes the pending one ([load-transition](../../patterns/load-transition.md) R4) | Kept; the board line names the requested size at once and adds its total only after that size answers |
| Loaded | Rows, then footer and pager when applicable; staggered row entrance | Kept |
| Empty (`entries` empty) | "No band scores found" / "No {type} scores have been recorded for this song yet." | Kept |
| Error | Web: full-page "Failed to load band leaderboard" with the parsed API error. **Native correction:** the shared service-status view with Retry, inside the content area below the header | Kept |
| Invalid band type (web only) | "Band leaderboard not found" | None |

Natives may title-case empty-state titles to platform convention ([empty-error-states](../../patterns/empty-error-states.md) R4 precedent); subtitles keep the web copy.

## Transitions

- **Band size** (native control): new board → page 1, scroll to top with the header in view, rows reload; header and backdrop stay.
- **Page**: rows reload; the web scrolls to the top. Natives keep the header scrolled away when it was under the bar (song-leaderboard-header R3).
- **Selected footer**: on this page → opens the Band page; elsewhere → jumps to the page holding its rank with `navToBand`, then centres and highlights the row (leaderboard-row R5, R7). Song Detail's appended selected-band row opens the board the same way.
- **Row** → Band page (`getBandProfileRoute`: band ID, size, team key, names). **Header title** → Song Detail. **Back** → the previous page (usually Song Detail's band section "View full leaderboard").
- Responses for an older size, page or selected profile are discarded (latest wins).

## Accessibility order (target)

Back → bar title (only once the header has scrolled away) → bar actions → song header (one heading stop: title, artist, board line; activates Song Detail where the title is a link) → band-size control (current size, "Switch band size") → rows (one stop each: rank, members with instruments and scores, band score, full combo, accuracy, stars) → selected-band footer ("Jump to your band's position" or "Open band") → pager → tab/sidebar. Web labels: row "View band {names}", footer "Jump to your band's position, rank #{rank}" / "Open band {names}".

## Test IDs

Web: `song-band-leaderboard-list`, `song-band-leaderboard-entry-{rank}`, `song-band-leaderboard-selected-footer-jump`. Native family `fst.song-band-leaderboard.`: `screen`, `list`, `row.<bandId-or-teamKey>:<rank>`, `empty`, `error`, `band-type-menu`, `band-type.<bandType>`, `spotlight-footer`, `page-first|page-previous|page-info|page-next|page-last`; the song header is `header` (with `pinned-title` for the bar title) or `song`. Each platform file lists its exact set.

## Canonical components

| Sub-behavior | Apple | Android | Windows |
|---|---|---|---|
| Song header + board line | `SongHeaderRow` + `SongLeaderboardBoardLine` | Song Detail's `SongHeader` + `SongBoardSwitcher` | `BandsSongLeaderboardPage` header (known debt: song-leaderboard-header R1) |
| Bar title after scroll | `SongBarTitleToolbarItem` (`songHeaderScrollAway`) | `FestivalScreen(scrolled, marqueeTitle = true)` | — (window title) |
| Song backdrop | `festivalBackground(.song(albumArt))` | `SongCoverBackdrop` | `IBackdropPage.BackdropArt` |
| Reload gate | `FestivalReloadGate` | `rememberLoadSwap` / `LoadSwap` | shared load-swap gate |
| Selected band footer + pager | `SelectedScoreFooterRow` + `RankingsPagerView` | `SelectedScoreFooterRow` in `RankingsBoardLayout` | `LeaderboardsPager` (no footer yet) |
| Failure | `ServiceStatusView` | `ServiceStatusView` | `ServiceStatusView` |

The pattern docs own these rows; update them there first.

## Open gaps

- Instrument-combo filter (`?combo=`, `BandFilterPill`, `BandComboFilterModal`) is not ported natively.
- Selected band identity (`teamKey=`) is web only; natives send only `accountId`.
- TODO(orchestrator): `contracts/parity-backlog.json` still records Apple `absent` with gap text that predates #306/#307/#317; [ios.md](ios.md) records what Apple implements.

## Test matrix

Duos/Trios/Quads; first, middle, last, out-of-range and single pages; `localEntries` present/missing; totals shown/hidden; loading, loaded, empty, error and Retry; size change during a load; page change with the header on screen and under the bar; no selection / selected player with and without a band of this size / band on and off this page; `navToBand` reveal; narrow and wide rows; large text; reduced motion; backdrop is the song cover after arriving from Song Detail and after a size change.
