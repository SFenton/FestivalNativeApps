# Settings — Android notes

> **What:** what the Android Settings page implements, where every setting lives, its reset registry and native decisions. **Read when:** changing `ui/settings/SettingsScreen.kt`, any `AppSettings` field, or adding a persisted key anywhere in the Android app. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Implementation

| Piece | Where |
|---|---|
| Model | `core/settings/AppSettings.kt` (every field, `sanitized()`, `withInstrumentVisible` last-visible guard, `withTapDiagnostics`, `resetAppSettings()`, derived `shopHighlightEnabled` / `orderedVisibleMetadata`) |
| Codecs | `core/settings/SettingsModels.kt`: `MetadataField` (web `DEFAULT_METADATA_ORDER`, web keys `seasonachieved`/`lastplayed`), `PathColumnKey`, `PathDisplayMode`, `SettingsOrder` (normalize/decode/encode/move), `ScoreLeeway` (clamp half-away-from-zero to 0.1, `+1.0%` format, web `maxScoreLeewayDesc`) |
| Registry | `core/settings/SettingsRegistry.kt`: every DataStore key with `ResetPolicy.AppSetting` (Reset removes it) or `Kept` |
| Store | `data/SettingsRepository.kt`: `update { }` (atomic decode → transform → sanitize → write), `resetAppSettings()`, `readBlob`/`writeBlob` for registered string blobs (first-run and notification seen-state) |
| Page model | `presentation/settings/SettingsViewModel.kt` (setters, Reset, service version), `presentation/settings/ServiceInfoPoller.kt` (5 s Service Info poll + progress memory) |
| Service Info | `core/serviceinfo/ServiceInfo.kt` (wire model without infrastructure fields, `ServiceProgressReducer`, `ServiceInfoText`, `ServiceInfoRows`), `data/serviceinfo/FestivalApiServiceInfo.kt` (`serviceInfo()`, `serviceVersion()`), `ui/settings/ServiceInfoSection.kt` |
| Page | `ui/settings/SettingsScreen.kt`; Licenses: [licenses/android.md](../licenses/android.md) |

**Adding a persisted key anywhere in the app:** declare it in `SettingsRegistry.entries` with its reset policy. `SettingsModelTest` fails when a key written through the repository is unregistered.

## Sections (web order) and effects

| Section (quick-link id) | Controls (`fst.settings.*`) | Notes |
|---|---|---|
| App Settings (`app-settings`) | `show-instrument-icons`, `enable-visual-order`, `song-row-order.<i>.up/down` (only visible metadata; hidden keys keep their place at the end, as on the web), `path-default-view.image/text`, `path-column-order.<i>.up/down`, `filter-invalid-scores`, `leeway` (M3 `Slider`, −5…+5, 99 steps, commits on release), `experimental-ranks` (disabled, "Not available on Android yet"; sanitized off), then `feedback.bug` / `feedback.feature` (Report an Issue / Request a Feature; shown only when `/api/features` reports `feedback: true`; see [feedback-form](../../controls/feedback-form/android.md)) | Consumers read `AppSettings`; this page only writes |
| Diagnostics (`diagnostics`, debug builds only) | `tap-diagnostics`, `tap-telemetry` (disabled until diagnostics; turning diagnostics off clears it) | No collector reads them yet |
| Item Shop (`item-shop`) | `disable-shop-highlighting` (disabled while hidden; value retained), `hide-shop` | `AppSettings.shopHighlightEnabled` is the effective flag |
| Show Instruments (`show-instruments`) | `instrument.<wireId>` | The last visible chart is disabled with a reason |
| Show Instrument Metadata (`show-metadata`) | `metadata.<field.tag>` (web toggle order) | All may be off (web); not disabled for anonymous users (web does not either) |
| Accessibility (`accessibility`, native) | `motion`, `still-artwork`, `contrast`, `transparency` | Additive only. Still artwork holds the backdrop; Reduce Transparency makes `GlassCard` opaque (`FestivalAccessibility.reduceTransparency`) |
| Version (`version`) | `app-version` (`versionName (versionCode)`), `build`, `service-version`, `service-origin` | Service Version reads `GET /api/version` once per view model: Loading → value, or Unavailable (retried on the next visit) |
| Service Info (`service-info`) | `service-info`, `service-info.state` (+ `.process`), `service-info.phase` (+ `.bar`), `service-info.freeze`, `service-info.last-published` | Live card like the web `SettingsServiceProgressCard` (batch 6, 6.15; no "Check for Updates", the web has none): polls keyless `GET /api/service-info` every 5 s only while the section is composed and the app is STARTED (`repeatOnLifecycle`). Loading/failure show only the state row (web); a failed poll after a success shows the failure. Phase title "Phase · Subphase", purple capsule bar (determinate `LinearProgressIndicator`; unknown total = M3 indeterminate sweep, still empty track under Reduce Motion), percent + units captions (Apple), freeze notice from the header or body, last publication as "Sep 28, 2026, 10:00 AM PDT" |
| First Run Guides (`first-run`) | `first-run.<pageKey>` | Replay: [first-run/android.md](../../controls/first-run/android.md) |
| Licenses (`licenses`) | `licenses` | Pushes `LicensesRoute` on the Settings stack |
| Reset (`reset`) | `reset`, dialog `reset.dialog/confirm/cancel` | M3 `AlertDialog`; removes `AppSetting` keys only (profile, Songs sort, seen-state survive) |

## Decisions

- Rows: whole-row `toggleable(role = Switch)` with title + description; a disabled row appends its reason so TalkBack reads why.
- Reorder (`ui/settings/ReorderList.kt`, batch 6.11) looks like the web's dnd-kit list: one bordered block of subtle rows with a ⋮⋮ handle and a semibold label, no numbers or arrow buttons. Drag the handle, or long-press anywhere on a row (the web's 150 ms touch activation) with a haptic tick; TalkBack/Switch Access use the rows' Move up / Move down custom actions. Song Row Visual Order shows directly under its toggle when enabled (no dropdown). Also used by the Songs sort sheet.
- Labels follow the web: metadata "Difficulty" (not "Game Difficulty", batch 6.13); First Run Guides rows show only the page name and a blue "Show" button (no slide counts, batch 6.16).
- Licenses entry (batch 6.17) is the web's navigation row: a section header (title + description) on the page with a trailing chevron, not a card. Settings and Licenses centre their column at 840 dp on wide windows.
- Service Info: labels, units and the monotonic reducer port the web/Apple tables verbatim; the body's `postgresConnectionTarget`/`serviceInstance` have no model fields, so they are never decoded or logged. The live summary is a polite live region; the phase row speaks its title with the percent/units as state and exposes `ProgressBarRangeInfo` when determinate.
- Not ported: profile-name refresh (POST), ZIP export (not allowlisted), light trails / mobile header buttons (no cursor or FAB chrome on Android), default search target (global search has no tabs to default).
- Book posture (separating vertical hinge): list on the start side, Quick Links pane beyond the hinge.
- Quick Links: see [quick-links/android.md](../../controls/quick-links/android.md).

## Tests and evidence

- `settings/SettingsModelTest.kt` (defaults vs web, guards, codecs, leeway, every-field round trip, registry, Reset), `settings/SettingsUiTest.kt` (every control persists, Reset cancel/confirm, Quick Links sheet jumps to the live Service Info card and the service version, expanded pane), `settings/ServiceInfoTest.kt` (keyless unpinned read + freeze header, malformed bodies/versions, reducer monotonicity/stale/restart/indeterminate rules, labels, rows, 5 s poll/stop).
- Screenshots: `android/reports/screenshots/settings-*.png` (fixture mode).

## Open

- Consumers still owed by other lanes: Songs (icons, metadata order/visibility, Shop hide/highlight, leeway on leaderboard reads), Paths (default view, column order, warning dismissal).
