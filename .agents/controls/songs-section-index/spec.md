# Songs Section Index — spec

> **What:** platform-neutral behavior for a right-edge "drag to jump" index over the Songs list. **Read when:** changing how Songs groups or jumps between sections on any platform. Platform notes: [ios.md](ios.md).

No web equivalent exists to source line numbers from: the web app has no section-jump control, so this is a native-only addition layered on the existing [Sort](../songs-sort/spec.md) order rather than a ported behavior.

## When it appears

- Only for sort modes with a meaningful, stable section key: **Title** and **Artist** (first letter) and **Year** (exact year). Duration, Item Shop and any score/band-based sort have no section key and show no index.
- Only once the current, already filtered and sorted row list produces **more than one** section; a single-section result (e.g. a narrow search match) hides it.
- Must animate in and out as the active sort mode or the result set changes, never appear/disappear abruptly.

## Sectioning rules

- Sections are computed from the **already sorted** row list; the control never re-sorts or re-filters.
- A section is a maximal **run of consecutive** rows sharing the same key (first letter, or exact year); it is not a merge of every row that shares a key anywhere in the list. A title sorted by raw string can land far from other titles that would share its derived key (for example, a numeral-led title's first letter, once digits are skipped), so runs of the same key that are not adjacent in the sorted list must stay separate sections, never merge into one displayed group. Merging by key alone silently pulls a later, unrelated run out of its sorted position.
- Missing year sorts and sections as its own explicit bucket, not folded into an adjacent year.
- A title or artist that does not begin with a letter (after trimming whitespace, skipping past leading punctuation to the first actual letter) sections under a single non-letter marker; it does not attempt further script- or locale-specific classification.

## Interaction

- Dragging along the index jumps the list to the start of the section under the touch point; releasing leaves the list at that position (no snap-back).
- Every section is reachable by both direct manipulation and a sequential (assistive-technology) traversal that does not depend on the drag gesture.
- Selecting a section is a bounded, in-memory scroll to already-loaded rows; it never triggers a network request or changes the applied Sort/Filter state.

## Accessibility

- The control is a single accessible element, not one per label, so it does not multiply a screen reader's traversal order of the page.
- Its announced value names the section currently under interaction (or the topmost section when idle), and it exposes a sequential increment/decrement action equivalent to dragging one section at a time.
