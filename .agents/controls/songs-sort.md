# Songs Sort (`fst.songs.sort`) - partial Apple implementation

Source: `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx:554-584,1112-1150`,
`src/pages/songs/modals/SortModal.tsx:44-213`,
`src/components/modals/Modal.tsx:29-68`,
`src/hooks/data/useFilteredSongs.ts:209-323`, and
`src/utils/songSettings.ts:16-50`. The source checkout is independently
dirty; check `contracts/source-snapshot.json` before a parity claim.

**Data:** Title and artist come from the public Songs catalogue; year and
`durationSeconds` may be absent and then sort numerically as zero. Ascending
is the default. Sorting happens after query matching and instrument filtering.
Tie-break by title in both directions; native adds `songId` to stabilize
identical titles. Do not display a profile, band, score, FC or Item Shop sort
until its underlying data is actually available and validated. The PWA's
anonymous modal *does* show Item Shop and Has FC; those are real outstanding
choices, not a parity pass for this four-mode native slice.

| State / action | PWA behavior | Apple slice and remaining gate |
|---|---|---|
| Open/default | Sort in mobile Search/Sort dock, Title ascending, disabled Apply | Native toolbar Sort opens a SwiftUI sheet; four catalogue modes, segmented direction, disabled Apply |
| Choose mode or direction | Draft changes, Apply enabled; list unchanged | Draft in `SongsSortSheet` changes, then explicit Apply updates visible rows and `@AppStorage` mode/direction |
| Cancel unchanged / changed | Close directly / ask before discarding | Cancel closes or confirms Continue Editing vs Discard Changes; interactive gesture dismissal disabled |
| Reset | Restore sort mode, direction and metadata priority to defaults *in the draft* | Reset changes only the four-mode native draft; Apply is still required; iPad Form may need scrolling to expose Reset above the fixed footer |
| Relaunch | Saved sort/direction restored | Persistent native mode/direction restore, independently of process-only network/artwork caches |
| Contextual modes | Instrument, visibility, shop, player and band change mode/priority choices | Pending service access, song cards, metadata controls, and full Songs actions |

**Native interaction and visual boundary:** On iOS 26 the bottom-toolbar
Sort action collided with the system tab bar during a device test, so keep it
in the native top toolbar until the shell has a proven safe lower dock.
The iPhone presents a full-height native sheet and the iPad a centered sheet;
neither is a pixel copy of the PWA phone bottom sheet or tablet dialog.
The PWA has six anonymous radio rows, direction arrows and hint, a red Reset
button and one Apply footer. Native has four inline system choices, a
segmented direction control, an in-Form Reset and a fixed Cancel/Apply
footer. Compare fixture-backed PWA captures from
`tools/visual/pages.spec.ts` (`anonymous Sort modal`) with the named
XCUITest Sort captures. Do not call this visual or feature parity.

**Accessibility order and tests:** Announce Sort Songs, mode choices, direction,
Reset, Cancel and Apply; selection and disabled Apply must be perceivable.
IDs `fst.songs.sort{,.mode,.direction,.reset,.cancel,.apply}` are registered in
`contracts/product.json`. On iPhone 26.5 the default and changed sheets pass
an unwaived `.all` audit. The tablet test scrolls the actual Form until Reset
is above the pinned footer and proves it changes/applies row order. It checks
rendered header/action contrast, but iPadOS 26.5's full `.all` audit still
reports **"Potentially inaccessible text" with no named element**. Keep that
failure pending; do not waive it or extend the iPhone result to iPad, macOS,
large text, landscape or VoiceOver focus. `SongCatalogSortTests` covers all
four modes, both directions, missing numeric fields and stable ties;
`testAnonymousSongsSortDraftApplyDiscardAndRelaunch` covers iPhone/iPad
draft, discard, Apply, scroll-reachable Reset and relaunch.
