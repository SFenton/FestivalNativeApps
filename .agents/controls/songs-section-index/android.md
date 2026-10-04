# Songs section index — Android notes

> **What:** the Android right-edge section index. **Read when:** changing `SectionIndexScrubber`, `SectionPosition` or `SongSectionIndex`. Behavior: [spec.md](spec.md).

## Behavior

- Shown for Title and Artist with ≥2 sections. Year sort hides it (operator decision 2026-09-28, [Songs page spec](../../pages/songs/spec.md#operator-decisions-all-platforms)): decade headers (`fst.songs.section.year.<decade>`) and Quick Links take its place. An active search or a one-section result also hides it.
- `AnimatedVisibility` fades and slides it in and out. With Reduce Motion (in-app setting or Remove animations) it appears and disappears at once.
- Tap or drag jumps the list (`scrollToItem`, no network). One `awaitEachGesture` loop handles both press and drag. Separate tap and drag detectors cleared the active section as soon as a drag began, so the highlight flickered (#138). While a finger is down:
  - The rail shows a circular frosted pill, opaque (`cardBackground`) under Increase contrast or Reduce transparency.
  - The touched label turns `tertiary` (gold); idle labels use `onSurfaceVariant`.
  - A **value indicator** (`fst.songs.section-index.indicator`, 56 dp minimum circle, `headlineSmall` `tertiary` text on `surface`) sits 8 dp left of the rail at the touch height, clamped to the rail. It names the section the touch opens, including sections that sampling leaves undrawn. TalkBack ignores it; the rail's state already says the same.
- `onJump` fires only when the touched section changes.
- When the labels don't fit (large text, landscape), every `SongSectionIndex.stride()`-th label is drawn in an equal slot. A touch on a drawn label opens that label's section, and the gaps between labels reach the skipped sections (`SongSectionIndex.sectionAt`). Before #48 the touch was mapped evenly over all sections, so at font scale 2 # opened A and B opened C.
- `SectionPosition` makes the current section the one containing the first visible row, with one exception: after a jump to a section the list can't bring to the top (the list is at its end), that section stays current until the list scrolls back or the user drags it. Without this, Next section stopped at the section at the top of the last screen, and TalkBack could never reach the last sections (#138).
- Missing or zero year is its own "—" section.

## Accessibility

- One node (`fst.songs.section-index`) with description "Section index". Its state is the current section, with "#" spoken as "Numbers and symbols" (`SongSectionIndex.spokenLabel`). It has **Next section** / **Previous section** custom actions, offered only where such a section exists.
- Reading order: after the visible rows, before the bottom toolbar (real TalkBack walk, #138).
- **Deliberate 48 dp deviation:** the rail is 24 dp wide (the Contacts-style index the spec asks for). Material 3 says *"Touch targets remain 48dp minimum even on large screens"*, but a 48 dp rail would cover the rows' trailing content (Shop badge, chips) and take their taps. TalkBack's equivalent is the single node with section actions. ATF doesn't flag it because the node isn't clickable.
- Theme: the app is dark-only (`festivalScheme`), so the system light theme renders identically.

## Tests

- Robolectric `SongsSectionIndexUiTest` (fixture `SectionIndexFixtures`) covers each state:
  - `title`: one element, actions, the last section reachable.
  - `artist`.
  - `year`: hidden; decade header and Quick Links.
  - `hidden`: by search.
  - `scrubbing`: indicator shown, then cleared on release.
  - Reduce Motion vs default slide-in.
  - The far jump (#48).
- `SongSectionIndexHitTest` covers `sectionAt`, `stride` and `spokenLabel`.
- Connected `SongsSectionIndexDeviceTest` runs the same states with ATF checks, 2.0 font scale and TalkBack-path custom actions.
  - It runs actions through UiAutomation `AccessibilityNodeInfo.performAction`. Compose's `performCustomAccessibilityActionWithLabel` crashes on a device ("performMeasureAndLayout called during measure layout").
  - It reads the rail node after `refresh()`, because without a screen reader UiAutomation's cached node keeps the old state.

## Validation (#138, live service)

| Configuration | Result |
| --- | --- |
| FST_Phone portrait, font 1.0 / 2.0, light and dark | Title and Artist show the rail (Artist has no X); Year hides it. At 2.0 every other label is drawn and the indicator names skipped letters (e.g. O). |
| FST_Phone landscape, font 1.0 / 2.0 | At 1.0, two-pane: the rail sits in the list pane with sampled labels. At 2.0, one pane: a short rail draws 3 labels and the indicator still names the exact section. |
| FST_Tablet landscape / portrait, font 2.0 | Rail beside the list pane in the two-pane layout. All letters fit, including at 2.0. |
| FST_Resizable compact / medium (609 dp) / expanded, font 2.0 | Compact and medium show every letter. Expanded at 2.0 samples labels and the indicator names the skipped ones. |
| FST_Book_Fold folded / half-open / unfolded, font 2.0 | Half-open: the rail stays in the list pane, left of the hinge. Unfolded at 2.0: sampled labels, indicator correct. |
| FST_Passport_Fold folded / unfolded, font 2.0 | Folded: sampled labels at 1.0 (narrow height per label), indicator names O. Unfolded at 2.0: correct. |
| FST_TriFold folded / partial / unfolded, font 2.0 | Partial: a single wide pane with all letters. Unfolded: two-pane, with the rail in the list pane. |
| Reduce Motion / animator scale 0 | The rail appears without sliding (Robolectric `reduceMotion_showsTheRailWithoutSliding`). |

Connected tests passed on FST_Phone and FST_Tablet. JaCoCo after the change: logic 98.0%, UI 95.6%.
