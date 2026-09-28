# Settings — Android notes

> **What:** what the Android Settings page implements, where every setting lives, its reset registry and native decisions. **Read when:** changing `ui/settings/SettingsScreen.kt`, any `AppSettings` field, or adding a persisted key anywhere in the Android app. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md).

## Implementation

| Piece | Where |
|---|---|
| Model | `core/settings/AppSettings.kt` (every field, `sanitized()`, `withInstrumentVisible` last-visible guard, `withTapDiagnostics`, `resetAppSettings()`, derived `shopHighlightEnabled` / `orderedVisibleMetadata`) |
| Codecs | `core/settings/SettingsModels.kt`: `MetadataField` (web `DEFAULT_METADATA_ORDER`, web keys `seasonachieved`/`lastplayed`), `PathColumnKey`, `PathDisplayMode`, `SettingsOrder` (normalize/decode/encode/move), `ScoreLeeway` (clamp half-away-from-zero to 0.1, `+1.0%` format, web `maxScoreLeewayDesc`) |
| Registry | `core/settings/SettingsRegistry.kt`: every DataStore key with `ResetPolicy.AppSetting` (Reset removes it) or `Kept` |
| Store | `data/SettingsRepository.kt`: `update { }` (atomic decode → transform → sanitize → write), `resetAppSettings()`, `readBlob`/`writeBlob` for registered string blobs (first-run and notification seen-state) |
| Page model | `presentation/settings/SettingsViewModel.kt` (setters, Reset, Service check) |
| Page | `ui/settings/SettingsScreen.kt`; Licenses: [licenses/android.md](../licenses/android.md) |

**Adding a persisted key anywhere in the app:** declare it in `SettingsRegistry.entries` with its reset policy. `SettingsModelTest` fails when a key written through the repository is unregistered.

## Sections (web order) and effects

| Section (quick-link id) | Controls (`fst.settings.*`) | Notes |
|---|---|---|
| App Settings (`app-settings`) | `show-instrument-icons`, `enable-visual-order`, `song-row-order.<i>.up/down` (only visible metadata; hidden keys keep their place at the end, as on the web), `path-default-view.image/text`, `path-column-order.<i>.up/down`, `filter-invalid-scores`, `leeway` (M3 `Slider`, −5…+5, 99 steps, commits on release), `experimental-ranks` (disabled, "Not available on Android yet"; sanitized off) | Consumers read `AppSettings`; this page only writes |
| Diagnostics (`diagnostics`, debug builds only) | `tap-diagnostics`, `tap-telemetry` (disabled until diagnostics; turning diagnostics off clears it) | No collector reads them yet |
| Item Shop (`item-shop`) | `disable-shop-highlighting` (disabled while hidden; value retained), `hide-shop` | `AppSettings.shopHighlightEnabled` is the effective flag |
| Show Instruments (`show-instruments`) | `instrument.<wireId>` | The last visible chart is disabled with a reason |
| Show Instrument Metadata (`show-metadata`) | `metadata.<field.tag>` (web toggle order) | All may be off (web); not disabled for anonymous users (web does not either) |
| Accessibility (`accessibility`, native) | `motion`, `still-artwork`, `contrast`, `transparency` | Additive only. Still artwork holds the backdrop; Reduce Transparency makes `GlassCard` opaque (`FestivalAccessibility.reduceTransparency`) |
| Version (`version`) | `app-version` (`versionName (versionCode)`), `build`, `service-version`, `service-origin` | Service Version is a disclosed "Not available": `/api/version` is not allowlisted |
| Service Info (`service-info`) | `check-publication`, `publication-status` | Forced `/api/songs` + `/api/publication` re-read (keyless public GETs). The web's live Service Progress uses `/api/service-info`, which is not allowlisted |
| First Run Guides (`first-run`) | `first-run.<pageKey>` | Replay: [first-run/android.md](../../controls/first-run/android.md) |
| Licenses (`licenses`) | `licenses` | Pushes `LicensesRoute` on the Settings stack |
| Reset (`reset`) | `reset`, dialog `reset.dialog/confirm/cancel` | M3 `AlertDialog`; removes `AppSetting` keys only (profile, Songs sort, seen-state survive) |

## Decisions

- Rows: whole-row `toggleable(role = Switch)` with title + description; a disabled row appends its reason so TalkBack reads why.
- Reorder uses numbered rows with Move up/Move down buttons plus TalkBack custom actions, not drag-only lists (keyboard/switch-access friendly, as on Windows).
- Not ported: Service Progress (not allowlisted), profile-name refresh (POST), ZIP export (not allowlisted), light trails / mobile header buttons (no cursor or FAB chrome on Android), default search target (global search has no tabs to default).
- Quick Links: see [quick-links/android.md](../../controls/quick-links/android.md).

## Tests and evidence

- `settings/SettingsModelTest.kt` (defaults vs web, guards, codecs, leeway, every-field round trip, registry, Reset), `settings/SettingsUiTest.kt` (every control persists, Reset cancel/confirm, Quick Links sheet jumps, Service check, expanded pane).
- Screenshots: `android/reports/screenshots/settings-*.png` (fixture mode).

## Open

- Consumers still owed by other lanes: Songs (icons, metadata order/visibility, Shop hide/highlight, leeway on leaderboard reads), Paths (default view, column order, warning dismissal).
- Drag-to-reorder (in addition to the buttons) is not built.
