# Settings — iPhone notes

> **What:** what the iPhone Settings page implements, native decisions and open gaps. **Read when:** changing Settings on iPhone (Lane A owns `Features/Settings`). Behavior: [spec.md](spec.md).

## Implemented propagation

| Setting | Effect on iPhone |
|---|---|
| Instrument visibility | Hides Songs chart choice, Detail cards and Paths choices; charted Intensity stays |
| Invalid-score leeway | Reaches Solo/preview requests. **Filter Invalid Scores** pauses selected-player score display with a visible pending message until `ml`/`vs`/`rt` fallback selection is ported |
| Paths default view | Announced Image/Text selection; initializes the Paths sheet. Reset also restores the Karaoke warning |
| Hide Item Shop / highlights | Removes the Shop action/route with a notice; highlights toggle Shop cards, Songs red/gold rows and the Detail badge without hiding the valid outbound action |
| Show Instrument Icons | Enabled even without a player; chips for a selected, unfiltered player; off → first-visible-chart metadata |
| Metadata (8) | Selected player: all enabled (7 change row text; Intensity gates the filtered meter). Anonymous: only Intensity enabled; others disabled with a reason |
| Accessibility section | Reduce Motion / Disable Animated Artwork hold a static cover; Increase Contrast strengthens accents and dims art more; Reduce Transparency removes decorative imagery/dim layers and makes the Solo pager opaque. System Low Data / Low Power also stop background work |
| Publication check | Refetches catalogue/art before reporting success; a failed Songs read is reported separately |

## Decisions and gotchas

- Section headers use `textSecondary` (not system gray) over translucent artwork gaps; three visible headers pass rendered-pixel ≥4.5:1 on `art-white`.
- Last Played switch still shows a date under Title (temporary native deviation until Last Played sort); experimental ranks stay disabled.
- The Form keeps its scroll position across tab switches: UI tests must try the reverse swipe for an earlier toggle.
- Every persisted setting is registered and has cold-start round-trip and reset coverage (Lane A, 2026-09-27). Groups render as `FestivalGlassSection` cards ([liquid-glass.md](../../design/apple/liquid-glass.md)).

## Open (iPhone)

Full-page audit (offscreen heading / compact title contrast — [accessibility](../../testing/apple/accessibility.md)); Service Progress, exports, first-run replay, metadata ordering, draggable path columns, only-Karaoke-visible Paths guard, band profiles and most remaining web settings.
