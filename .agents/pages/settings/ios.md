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
| Song Row Visual Order | Persisted field order (`fst.settings.songRowVisualOrder`) via a native drag-handle `SettingsReorderSheet`; Songs cards do not yet read the order (Lane S consumer change, below) |
| CHOpt Path Column Order | Same reorder sheet over `PathColumnKey` (note/beat/time/od/score, `FestivalCore/SettingsModels.swift`); the Paths text table does not yet read it (Lane S consumer change, below) |
| Diagnostics (debug-only) | Tap Diagnostics / Tap Telemetry toggles persist behind `#if DEBUG`; no collector reads them yet — wiring only |
| Version | App Version/build (`Bundle.main`) and Build Configuration are live; Service Version is a disclosed placeholder because `/api/version` is not yet on the verified-read allowlist ([service-safety.md](../../platforms/service-safety.md)) |

## Decisions and gotchas

- Section headers use `textSecondary` (not system gray) over translucent artwork gaps; three visible headers pass rendered-pixel ≥4.5:1 on `art-white`.
- Last Played switch still shows a date under Title (temporary native deviation until Last Played sort); experimental ranks stay disabled.
- The Form keeps its scroll position across tab switches: UI tests must try the reverse swipe for an earlier toggle.
- Every persisted setting is registered and has cold-start round-trip and reset coverage (Lane A, 2026-09-27). Groups render as `FestivalGlassSection` cards ([liquid-glass.md](../../design/apple/liquid-glass.md)).

## Open (iPhone)

Full-page audit (offscreen heading / compact title contrast — [accessibility](../../testing/apple/accessibility.md)); Service Progress (live `/api/service-info` is not on the verified-read allowlist, so it stays unported), ZIP export, only-Karaoke-visible Paths guard, band profiles, search target and light-trails/header-button settings (native chrome has no mouse-cursor or floating-action-button equivalent, so these are treated N/A rather than ported), selected-profile name refresh (a POST — fixtures only, deferred). First-run replay rows are owned by a dedicated FRE lane, which may add a small additive section to `SettingsScreen.swift`.

**Consumer changes owed to other lanes:** Songs (Lane S) should read `fst.settings.songRowVisualOrder` (`SettingsOrder.decode` in `FestivalCore/SettingsModels.swift`) for the lead metadata field on cards, and the Paths text table (`SongPathsSheet`) should read `fst.settings.pathColumnOrder` (`PathColumnKey`) for column order.
