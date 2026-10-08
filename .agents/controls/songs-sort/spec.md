# Songs Sort (`fst.songs.sort`) — spec

> **What:** platform-neutral Sort modes, ordering, Shop sections and draft semantics. **Read when:** changing Songs sorting on any platform. Platform notes: [ios.md](ios.md) · [ipados.md](ipados.md).

Source: `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx:554-584,1112-1150`, `src/pages/songs/modals/SortModal.tsx:44-213`, `src/components/modals/Modal.tsx:29-68`, `src/hooks/data/useFilteredSongs.ts:209-323`, `src/pages/songs/songQuickLinks.ts:55-115,205-218`, `src/utils/songSettings.ts:16-50`.

## Ordering

- Sort runs after query matching and instrument filtering. Ascending default.
- Title/Artist from the catalogue; missing `year` / `durationSeconds` sort as zero. Catalogue-mode ties use title in both directions (natives add a stable `songId`).
- Item Shop: requires a validated feed from the **same observed publication** (including a known-empty feed). Ascending puts members first, descending last; ties title → artist → year → `songId`. Never infer empty membership from a failed feed.
- Web anonymous modes: Title, Artist, Year, Duration, Item Shop, **Has FC**. Contextual modes add score/percentage/season/FC/difficulty/player/band with a metadata priority order.

## Shop sections

Sorted rows group by first-seen bucket: **Leaving Tomorrow**, **In Shop**, **Not In Shop** (a Leaving offer is never also In Shop). Headings only when ≥2 buckets are non-empty; within-bucket order preserved. Mirrors `buildSongQuickLinkSections` without the quick-link rail.

## Draft semantics

| Action | Behavior |
|---|---|
| Open | Current applied mode/direction; Apply disabled |
| Choose mode/direction | Draft changes; list unchanged until Apply |
| Cancel | Unchanged → close; changed → confirm discard |
| Reset | Restore defaults **in the draft**; Apply still required |
| Relaunch | Applied mode/direction restored |
| Shop hidden / feed unavailable | Hide removes the Shop choice; saved Shop sort **pauses** (Title order in the saved direction, visible notice) and resumes when valid membership returns; a failed refresh with retained matching data keeps sorting with an error notice |

## Item Shop consumer (#379)

The Item Shop page reuses this control; it is not a second sort mechanism. The rules both consumers share (one sort UI, one comparator, Reset and trigger state, separate persistence, one order for every layout, the Duration pause) and the #379 web decision are the [catalogue-sort](../../patterns/catalogue-sort.md) pattern; this section is the control-level summary. Modes are the four catalogue sorts only: **Title, Artist, Year, Duration** (no Item Shop, Has FC, Last Played or instrument modes: the page lists only Shop songs and has no player context). Ordering, missing-value and tie rules are the Songs ones above (Duration comes from a catalogue of the feed's publication; a catalogued offer without one sorts as zero, and a failed or older catalogue pauses Duration to title order with `fst.shop.sort-paused`, catalogue-sort R7). Grid and list share the order; filters apply before the sort. The choice applies live like Songs, Reset restores Title ↑, and it persists on its own (independent of the Songs sort, and kept when the player is cleared, since none of its modes need a player). The button shows the applied summary (`Duration ↓`) and is marked when it differs from Title ↑. IDs `fst.shop.sort{,.mode,.direction,.reset}`, `fst.shop.sort-paused`, page notes per platform. Web: title-only on master; the #379 agent decision (option B, owner may override; [catalogue-sort](../../patterns/catalogue-sort.md#decision-item-shop-sorts-on-native-and-web-379)) gives the web Shop the same four modes through its `SortModal` (SFenton/FortniteFestivalLeaderboardScraper#175).

## Accessibility and IDs

Announce Sort Songs, mode choices, direction, Reset, Cancel, Apply; selection and disabled Apply perceivable. IDs `fst.songs.sort{,.mode,.direction,.reset,.cancel,.apply}`, `fst.songs.sort-paused`, `fst.songs.shop-section.*`.

## Consumers

The Item Shop sort (#379) reuses this control's UI and catalogue comparator with the Title, Artist, Year and Duration modes only: [shop/spec.md](../../pages/shop/spec.md#sort-native-and-web-agent-decision-379). Rules shared by both consumers (one sort UI, one comparator, direction section, Reset, saved per page): the [catalogue-sort](../../patterns/catalogue-sort.md) pattern.
