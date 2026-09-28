# Settings — iPhone notes

> **What:** what the iPhone Settings page implements, native decisions and open gaps. **Read when:** changing Settings on iPhone (Lane A owns `Features/Settings`). Behavior: [spec.md](spec.md).

## Implemented propagation

| Setting | Effect on iPhone |
|---|---|
| Instrument visibility | Hides Songs chart choice, Detail cards and Paths choices; charted Intensity stays |
| Invalid-score leeway | Reaches Solo/preview requests. **Filter Invalid Scores** pauses selected-player score display with a visible pending message until `ml`/`vs`/`rt` fallback selection is ported |
| Paths default view | `SettingsChoiceRow`: title, current value and chevron pushing a checkmark list (iOS Settings style, not a `Menu` dropdown); initializes the Paths sheet. Reset also restores the Karaoke warning. Use the same row for any future single-choice setting |
| Hide Item Shop / highlights | Removes the Shop action/route with a notice; highlights toggle Shop cards, Songs red/gold rows and the Detail badge without hiding the valid outbound action |
| Show Instrument Icons | Enabled even without a player; chips for a selected, unfiltered player; off → first-visible-chart metadata |
| Metadata (8) | Selected player: all enabled (7 change row text; Intensity gates the filtered meter). Anonymous: only Intensity enabled; others disabled with a reason |
| Accessibility section | Reduce Motion / Disable Animated Artwork hold a static cover; Increase Contrast strengthens accents and dims art more; Reduce Transparency removes decorative imagery/dim layers and makes the Solo pager opaque. System Low Data / Low Power also stop background work |
| Service Info | `SettingsServiceInfoSection`: polls keyless `/api/service-info` every 5 s only while Settings is visible (web cadence); rows Leaderboard Service State (+ Loading/Updating/Idle/Stopped), phase · subphase with a monotonic capsule bar and units line, **Public Reads** freeze notice (native addition, header first then body, `ServiceFreezeReason` vocabulary), Last Successful Publication. Reducer/labels ported in `FestivalCore/ServiceInfo.swift` |
| Publication check | Last row of Service Info (kept for Songs journeys); refetches catalogue/art before reporting success; a failed Songs read is reported separately |
| First Run Guides | Web title, web row order (Statistics and Suggestions before **Score History**), "Show" replays every slide (`FirstRunSettingsSection`) |
| Song Row Visual Order | Persisted field order (`fst.settings.songRowVisualOrder`) via a native drag-handle `SettingsReorderSheet`; Songs cards do not yet read the order (Lane S consumer change, below) |
| CHOpt Path Column Order | Same reorder sheet over `PathColumnKey` (note/beat/time/od/score, `FestivalCore/SettingsModels.swift`); the Paths text table does not yet read it (Lane S consumer change, below) |
| Diagnostics (debug-only) | Tap Diagnostics / Tap Telemetry toggles persist behind `#if DEBUG`; no collector reads them yet — wiring only |
| Version | App Version/build (`Bundle.main`), Build Configuration and Service Version (keyless `/api/version`, read once per visible session; "Unavailable" on failure). **What's New · Show** replays the changelog ([whats-new](../../controls/whats-new/ios.md)) |

## Decisions and gotchas

- Section order follows the web: … Version · Service Info · First Run Guides · Licenses · Reset.
- Row labels: title in primary white, detail in `.subheadline` `textSecondary` with 4 pt spacing (HIG list-row subtitle; operator 2026-09-28).
- Indeterminate progress is a static empty track plus "In progress — total not yet known", not the web's looping shimmer (a `repeatForever` animation stalls XCUITest idling and adds no information).

- Section headers use `textSecondary` (not system gray) over translucent artwork gaps; three visible headers pass rendered-pixel ≥4.5:1 on `art-white`.
- Last Played switch still shows a date under Title (temporary native deviation until Last Played sort); experimental ranks stay disabled.
- The Form keeps its scroll position across tab switches: UI tests must try the reverse swipe for an earlier toggle.
- Every persisted setting is registered and has cold-start round-trip and reset coverage (Lane A, 2026-09-27). Groups render as `FestivalGlassSection` cards ([liquid-glass.md](../../design/apple/liquid-glass.md)).
- **Quick Links adopted** (Lane P follow-up, 2026-09-28): `app-settings`, `diagnostics` (DEBUG only — tagged inside that `#if DEBUG` block so Release never registers a link to nothing), `item-shop`, `show-instruments`, `show-metadata`, `version`, `service-info` (the `service` section), `first-run` (tags `FirstRunSettingsSection` from the call site, no edit to that FRE-lane file), `licenses` (the `about` section) and `reset`, matching the spec order/icons. `refresh-profile-name`/`export` are left out — this screen has no such rows yet (see Open below) — rather than pointing a quick link at nothing. Tab root with its own page action, so it now ends its single `.toolbar` with `FestivalRootTrailingItems(session:)` and calls `.festivalProvidesRootTrailingItems()`, per the toolbar-order rule.
- **Hosted + XCUITest coverage landed** (Lane U4, 2026-09-28): `SettingsRenderTests.swift` (anonymous/selected-player defaults, expanded leeway+visual-order row, Item Shop hidden, single-visible-instrument disables its own toggle, diagnostics on, accessibility overrides on, both `SettingsReorderSheet` item lists, `SettingsServiceSummary`'s four publication-message branches); `SettingsJourneyTests.swift` (an accessibility toggle survives a cold relaunch, the Song Row Order reorder sheet opens/lists fields/closes, Reset App Settings restores a changed toggle). SwiftPM UX coverage: `SettingsScreen.swift` 94.7%, `SettingsReorderSheet.swift` 95.7%, `SettingsRegistry.swift` 90.9%.
- **`SettingsRegistry.SettingDefault` gained a `.data(Data)` case** (Lane P, 2026-09-28) so Suggestions' own `SuggestionFilterSettings.storageKey` (a Codable-JSON `@AppStorage(Data)`, default `Data()`) is included in "Reset App Settings" and the persistence round-trip test, without SettingsScreen needing to understand that type's contents — it only resets the key to empty `Data()`, matching `SuggestionFilterSettings`'s own "absent/empty means defaults" contract.

## Open (iPhone)

Full-page audit (offscreen heading / compact title contrast — [accessibility](../../testing/apple/accessibility.md)); ZIP export, only-Karaoke-visible Paths guard, band profiles, search target and light-trails/header-button settings (native chrome has no mouse-cursor or floating-action-button equivalent, so these are treated N/A rather than ported), selected-profile name refresh (a POST — fixtures only, deferred).

**Consumer changes owed to other lanes:** Songs (Lane S) should read `fst.settings.songRowVisualOrder` (`SettingsOrder.decode` in `FestivalCore/SettingsModels.swift`) for the lead metadata field on cards, and the Paths text table (`SongPathsSheet`) should read `fst.settings.pathColumnOrder` (`PathColumnKey`) for column order.
