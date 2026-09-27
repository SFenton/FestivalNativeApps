# Songs Sort (`fst.songs.sort`) - partial Apple implementation

Source: `FortniteFestivalWeb/src/pages/songs/SongsPage.tsx:554-584,1112-1150`,
`src/pages/songs/modals/SortModal.tsx:44-213`,
`src/components/modals/Modal.tsx:29-68`,
`src/hooks/data/useFilteredSongs.ts:209-323`, and
`src/pages/songs/songQuickLinks.ts:55-115,205-218`, plus
`src/utils/songSettings.ts:16-50`. The source checkout is independently
dirty; check `contracts/source-snapshot.json` before a parity claim.

**Data:** Title and artist come from the public Songs catalogue; year and
`durationSeconds` may be absent and then sort numerically as zero. Ascending
is the default. Sorting happens after query matching and instrument filtering.
The five native anonymous modes are Title, Artist, Year, Duration and
**conditional Item Shop**. A validated public Shop feed is required even when
it is empty: ascending puts Shop members first, descending last; ties use
title, artist, year, then a native stable `songId`. For catalogue-only modes,
title remains the tie-break in both directions. Never infer empty membership
from a missing/failed feed or display score, FC, player or band choices
without validated data. PWA also offers anonymous Has FC, which is **not**
implemented by this native slice.

The Shop mode groups *sorted* rows by their first-seen Shop bucket:
**Leaving Tomorrow**, **In Shop**, **Not In Shop**. A Leaving offer is
never also an In Shop group row. Render labeled accessible headings
only if at least two nonempty buckets occur; a genuinely empty feed
puts every song in one unheaded Not In Shop bucket. Keep within-bucket
relative sort order, including reversed title/artist/year ties.
This mirrors source `buildSongQuickLinkSections` without claiming
its quick-link rail, other modes' buckets or scroll restoration.

| State / action | PWA behavior | Apple slice and remaining gate |
|---|---|---|
| Open/default | Sort in mobile Search/Sort dock, Title ascending, disabled Apply | Native toolbar Sort opens a SwiftUI sheet; four catalogue modes, plus Item Shop when visible, segmented direction, disabled Apply |
| Choose mode or direction | Draft changes, Apply enabled; list unchanged | Draft in `SongsSortSheet` changes, then explicit Apply updates visible rows and `@AppStorage` mode/direction |
| Cancel unchanged / changed | Close directly / ask before discarding | Cancel closes or confirms Continue Editing vs Discard Changes; interactive gesture dismissal disabled |
| Reset | Restore sort mode, direction and metadata priority to defaults *in the draft* | Reset changes the native draft only, including a paused Shop choice; Apply is still required; iPad Form may need scrolling to expose Reset above the fixed footer |
| Relaunch | Saved sort/direction restored | Persistent native mode/direction restore, independently of process-only network/artwork caches |
| Item Shop | Source presents Item Shop even anonymously; ascending prioritizes actual membership, descending reverses it | Native offers Item Shop if Settings shows Shop, enabled only with a validated public feed (including known empty). Hide removes the choice and pauses any saved Shop sort; if **no validated feed is retained**, an absent/failed feed disables it and pauses with an explicit notice and Retry. A failed refresh with already validated membership keeps sorting, disclosing the update error. Display Title order in the saved direction only while paused. |
| Shop sections | Source puts a header before each of at least two nonempty first-seen Leaving/In/Not buckets and exposes quick links | Native List uses the same three first-seen buckets and skips headings for one bucket; quick-link rail/jump drawer, other sort-mode buckets and exact row/layout geometry remain pending |
| Contextual modes | Instrument, visibility, shop, player and band change mode/priority choices | Score/Has FC/player/band modes, metadata priorities, Shop filter, and full Songs actions remain pending |

**Native interaction and visual boundary:** On iOS 26 the bottom-toolbar
Sort action collided with the system tab bar during a device test, so keep it
in the native top toolbar until the shell has a proven safe lower dock.
The iPhone presents a full-height native sheet and the iPad a centered sheet;
neither is a pixel copy of the PWA phone bottom sheet or tablet dialog.
The PWA has six anonymous radio rows, direction arrows and hint, a red Reset
button and one Apply footer. Native has five choices *only when Shop is shown*,
a disabled fifth choice until the feed validates, a
segmented direction control, an in-Form Reset and a fixed Cancel/Apply
footer. Compare fixture-backed PWA captures from
`tools/visual/pages.spec.ts` (`anonymous Sort modal` and `anonymous Item Shop
sort reorders Songs`) with the named XCUITest Sort captures. Do not call
this visual or feature parity.

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
five modes, both directions, missing numeric fields, empty/error distinction
and stable ties;
`testAnonymousSongsSortDraftApplyDiscardAndRelaunch` covers iPhone/iPad
draft, discard, Apply, scroll-reachable Reset and relaunch. The selected
`testAnonymousItemShopSortRestoresAfterHideAndFeedFailure` checks
membership-driven row order in both directions, hiding/restoring the
choice and preference, a failed versus known-empty feed, and cold
relaunch without a success-shaped fallback on both devices. The
`shop-section.*` IDs name visible headers; the selected device case
checks ascending/descending section order, Leaving Tomorrow, hiding/
failure, one-bucket omission and a grouped Song Detail/back route. A
selected WebKit source case verifies the two-bucket order. The iPhone
new-option sheet passes an unwaived `.all` audit; the grouped Songs
screen passed one such audit but failed another with an **unnamed
Dynamic Type issue** on the same runtime, so its full audit remains
open. The selected iPhone/iPad headers meet a rendered ≥4.5:1 check;
iPad's Shop choice also meets that bar. On iPad
the native accessibility query currently reports a grouped header
frame spanning **both split-view panes** even though the screenshot
shows the label only in the detail pane. Measure the visible text
at the native search field's detail-pane X origin and the header Y
for a genuine ≥4.5:1 screenshot check; this does **not** certify
the VoiceOver focus rectangle or the separately failing full iPad
Sort-sheet audit. Revisit both before a full accessibility claim.

Mac-hosted **test-only content** snapshots now exercise six real
Title/Artist/Shop saved and conditional-feed variants at 390/820pt
plus AX5; a mid-content opaque-surface assertion rejects a black
headless Form with falsely readable radio dots. A bare
`NSHostingView` with the app's dark surface paints selected blue
native controls; attaching an offscreen window for *this Form*
made them inactive-looking, unlike the lazy Shop List. This
proves only the content and independent labels, not a presented
system-sheet frame or Apply/Cancel tap; device XCTest owns the
real draft/discard/navigation actions and the iPad full `.all`
audit remains open. See
[native hosted snapshots](../testing/native-hosted-snapshots.md).
