# Songs Section Index — spec

> **What:** platform-neutral behavior for a right-edge "drag to jump" index over the Songs list. **Read when:** changing how Songs groups or jumps between sections on any platform. Platform notes: [ios.md](ios.md).

The web app has Quick Links but no drag index. The native index uses the existing [Sort](../songs-sort/spec.md) order.

## When it appears

- Only for **Title** and **Artist**, indexed by first letter. Duration, Item Shop and score/band-based sorts do not expose an index.
- **Year** uses decade headers and Quick Links instead of an index, per the [Songs page decision](../../pages/songs/spec.md#operator-decisions-all-platforms).
- Only once the current, already filtered, sorted and grouped row list produces **more than one** section; a single-section result (e.g. a narrow search match) hides it.
- Must animate in and out as the active sort mode or the result set changes, never appear/disappear abruptly.

## Sectioning rules

- Sections are computed from the Songs list **after** its web-aligned first-seen bucket grouping ([section-headers](../../patterns/section-headers.md) R13; web `songQuickLinks.ts` `buildSongQuickLinkSections`, which groups the sorted rows by bucket in order of first appearance). The index consumes that supplied row order and its buckets; it never re-sorts, re-filters or regroups them itself.
- Title/Artist therefore have exactly **one** `#`/A–Z section per supplied bucket, matching the list's section titles 1:1, so a jump to a label always lands on that label's title. Where a platform collator interleaves non-letter titles among letter-led ones, the page's grouping (not the index) gathers them into the single `#` bucket at its first-seen position. A platform whose sort already keeps every key contiguous (Apple's raw-string sort, `SongSectionIndex` chunking consecutive keys) yields the same sections.
- Title/Artist labeling follows the native Contacts convention: the label is the diacritic-folded first character (after trimming leading whitespace) only when that character is a letter A–Z; every other leading character — punctuation, a digit, a symbol, a non-Latin script — shares one non-letter marker. It never skips past a non-letter prefix to reach "a real letter" deeper in the string: every non-letter-leading title stays in the one `#` section (contiguous in a raw-string sort, gathered by the first-seen grouping where a collator interleaves them), rather than scattering under unrelated, out-of-order labels.

## Fit

- The index is never taller than the space it is given and never makes the page taller than its window. Where every label does not fit (a short landscape display or window), it shows the first and last labels with evenly spaced labels between them and a bullet for each skipped run, as the system table index does; every section stays reachable by dragging and by sequential traversal.

## Interaction

- Dragging along the index jumps the list to the start of the section under the touch point; releasing leaves the list at that position (no snap-back).
- Every section is reachable by both direct manipulation and a sequential (assistive-technology) traversal that does not depend on the drag gesture.
- Selecting a section is a bounded, in-memory scroll to already-loaded rows; it never triggers a network request or changes the applied Sort/Filter state.

## Accessibility

- The control is a single accessible element, not one per label, so it does not multiply a screen reader's traversal order of the page.
- Its announced value names the section currently under interaction (or the topmost section when idle), and it exposes a sequential increment/decrement action equivalent to dragging one section at a time.
