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

## Accessibility and IDs

Announce Sort Songs, mode choices, direction, Reset, Cancel, Apply; selection and disabled Apply perceivable. IDs `fst.songs.sort{,.mode,.direction,.reset,.cancel,.apply}`, `fst.songs.sort-paused`, `fst.songs.shop-section.*`.

## Consumers

The Item Shop sort (#379) reuses this control's UI and catalogue comparator with the Title, Artist, Year and Duration modes only: [shop/spec.md](../../pages/shop/spec.md#sort-native-and-web-agent-decision-379).
