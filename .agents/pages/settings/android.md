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
| Version (`version`) | `app-version` (`versionName (versionCode)`, plus ` · <sha7>` from `BuildConfig.GIT_SHA` when the build is stamped with `-PfstGitSha`/`FST_GIT_SHA`; omitted when missing, empty, `dev` or non-hex; `core/settings/AppBuildInfo.kt`, issues #21/#43), `build`, `service-version`, `service-origin` | App Version: release builds take `YYMM.DD.NN` from the `android/v*` tag that `version-bump.yml` creates on each app-changing merge (`-PfstVersionName/-PfstVersionCode`); local builds show `0.2.0 (1)`. Service Version reads `GET /api/version` once per view model: Loading → value, or Unavailable (retried on the next visit) |
| Service Info (`service-info`) | `service-info`, `service-info.state` (+ `.process`), `service-info.phase` (+ `.bar`, `.attempt`), `service-info.last-published` | Live card like the web `SettingsServiceProgressCard` (batch 6, 6.15; no "Check for Updates", the web has none): polls keyless `GET /api/service-info` every 5 s only while the section is composed and the app is STARTED (`repeatOnLifecycle`). Loading/failure show only the state row (web); a failed poll after a success shows the failure. Phase title "Phase · Subphase", purple capsule bar (determinate `LinearProgressIndicator`; unknown total = M3 indeterminate sweep, still empty track under Reduce Motion), the web card's rows only (issue #81, port of iOS #22): title, bar and the registered-band discovery line 4 dp apart ("1,310 attempted this pass · 70 temporarily unavailable · 1,240 of 5,000 completed", web `attemptProgress`: schema 1 only, finite whole counts, unavailable ≤ attempted, monotonic within a phase attempt); percent/units are spoken as the phase row's state description, not printed; the native freeze row was dropped (web has none; `ServiceInfoRows.freezeNotice` kept, unused); at large text (`isLargeText`, font scale ≥ 1.5) the process state stacks under the label instead of squeezing it; last publication as "Sep 28, 2026, 10:00 AM PDT" |
| First Run Guides (`first-run`) | `first-run.<pageKey>` | Replay: [first-run/android.md](../../controls/first-run/android.md) |
| Licenses (`licenses`) | `licenses` | Pushes `LicensesRoute` on the Settings stack |
| Privacy Policy (`privacy-policy`) | `privacy-policy`; modal `fst.privacy-policy.*` ([control notes](../../controls/privacy-policy/android.md)) | Same navigation row as Licenses (issue #98). Opens `ui/settings/PrivacyPolicySheet.kt`: the shared `FestivalModalSheet` (compact widths; swipe down, Back or Close) or `FestivalModalDialog` (regular widths, ≤ 640 dp tall). Text comes from `assets/privacy-policy.json`, a byte-for-byte copy of `contracts/privacy-policy.json` parsed by `core/privacy/PrivacyPolicy.kt`; section titles are TalkBack headings, the bullet glyph is hidden, and HTTPS addresses are `LinkAnnotation.Url` links |
| Reset (`reset`) | `reset`, dialog `reset.dialog/confirm/cancel` | M3 `AlertDialog`; removes `AppSetting` keys only (profile, Songs sort, seen-state survive) |

## Decisions

- Rows: whole-row `toggleable(role = Switch)` with title + description; a disabled row appends its reason so TalkBack reads why.
- Reorder (`ui/settings/ReorderList.kt`, batch 6.11) looks like the web's dnd-kit list: one bordered block of subtle rows with a ⋮⋮ handle and a semibold label, no numbers or arrow buttons. Drag the handle, or long-press anywhere on a row (the web's 150 ms touch activation) with a haptic tick; TalkBack/Switch Access use the rows' Move up / Move down custom actions. Song Row Visual Order shows directly under its toggle when enabled (no dropdown). Also used by the Songs sort sheet.
- Labels follow the web: metadata "Difficulty" (not "Game Difficulty", batch 6.13); First Run Guides rows show only the page name and a blue "Show" button (no slide counts, batch 6.16).
- Licenses entry (batch 6.17) is the web's navigation row: a section header (title + description) on the page with a trailing chevron, not a card. Settings and Licenses centre their column at 840 dp on wide windows (M3 expanded-width body cap). The modifier order is `widthIn(max = 840.dp).fillMaxWidth()`: `fillMaxWidth()` first pins the minimum width to the parent and the cap is then ignored (issue #121, 958–968 dp on tablets).
- Version value rows (`ValueRow`) are adaptive (issue #121): title and value sit side by side when both fit at their intrinsic widths plus a 12 dp gap, otherwise the value stacks 4 dp under the title. A fixed `Row` with a `weight` value crushed "Service" into a one-letter column beside the long origin at font scale 2.0 and on 360 dp folded covers.
- Service Info: labels, units and the monotonic reducer port the web/Apple tables verbatim; the body's `postgresConnectionTarget`/`serviceInstance` have no model fields, so they are never decoded or logged. The card is **not** a live region (issue #121, deliberate deviation from the web's `aria-live`): on a real emulator a polite live region announced when TalkBack scrolled the card into view (the 5 s poll starting) and TalkBack then spoke nothing for the next five focus moves; without it all 99 items read in order. Focusing the state row reads the current state; the phase row speaks its title with the percent, units and discovery attempts as state and exposes `ProgressBarRangeInfo` when determinate.
- Not ported: profile-name refresh (POST), ZIP export (not allowlisted), light trails / mobile header buttons (no cursor or FAB chrome on Android), default search target (global search has no tabs to default).
- Book posture (separating vertical hinge): list on the start side, Quick Links pane beyond the hinge.
- Quick Links: see [quick-links/android.md](../../controls/quick-links/android.md).

## Tests and evidence

- `settings/SettingsModelTest.kt` (defaults vs web, guards, codecs, leeway, every-field round trip, registry, Reset), `core/AppBuildInfoTest.kt` (App Version text, short-commit rules, Gradle's stamped `GIT_SHA`), `settings/SettingsUiTest.kt` (every control persists, Reset cancel/confirm, Quick Links sheet jumps to the live Service Info card and the service version, expanded pane, Privacy Policy sheet on phones and dialog on expanded windows), `privacy/PrivacyPolicyTest.kt` (the bundled asset equals `contracts/privacy-policy.json` byte for byte, so re-copy it after editing the contract; section order, malformed/schema/invalid-block handling, link ranges), `settings/ServiceInfoTest.kt` (keyless unpinned read + freeze header, malformed bodies/versions, reducer monotonicity/stale/restart/indeterminate rules, attempt-progress validation/monotonicity/text, labels, rows, 5 s poll/stop; `ServiceInfoSectionUiTest`: no printed captions or freeze row, spoken values, 4 dp gaps, state row side by side at 1× and stacked at 2×, no live region).
- Issue #121 regressions in `settings/SettingsUiTest.kt` (native graphics mode, since legacy Robolectric text measurement hides the overlap): `SettingsValueRowUiTest` (short values stay inline at 1×), `LargeTextSettingsValueRowUiTest` (the Service origin stacks under its title at 2×, title never narrower than its text), `WideSettingsColumnUiTest` (`w1280dp` landscape: every section is 840 dp wide and centred).
- Issue #151: `settings/AppVersionRowUiTest.kt` (`AppVersionRow`, the App Version row on its own: stamped text read as one non-interactive item "App Version, <version> (<build>) · <sha7>", unstamped text with no separator, the default equals this build's `BuildConfig` identity, and at font scale 2.0 on a 360 dp window the title and value stay inside the row without overlapping, stamped and unstamped).
- Connected: `journeys/BandsSettingsJourneyTest#settingsTogglesResetAndLicenses` runs the Accessibility Test Framework on every interaction (errors fail the test); it passes on FST_Phone and FST_Tablet. Since issue #151 it also scrolls to `fst.settings.app-version`, checks its text against `AppBuildInfo` (suffix present only when `GIT_SHA` is a stamped hex SHA) and that the reading order holds it as one item. Run it with `FST_GIT_SHA=$(git rev-parse HEAD)` to exercise the stamped state. UiAutomation caches nodes and Compose sends it no invalidation after a programmatic scroll, so the test calls `UiAutomation.clearCache()` (API 34+) before reading the window again.
- Screenshots: `android/reports/screenshots/settings-*.png` (fixture mode).

## Validation (issue #121, 2026-10-03)

Live public service (keyless `https://festivalscoretracker.com/`, no profile selected), debug APK, `tools/android/device.py drive` with `FST_DEBUG_STILL_BACKGROUND=1` (the "Disable Animated Artwork" state; the moving backdrop keeps uiautomator from going idle), animator scale 0 unless noted. Each run walked the page top to bottom, opened Quick Links and jumped to Version, opened the Privacy Policy and the Reset dialog where listed, and checked font scale 1.0 and 2.0.

| Configuration | Found | Result |
|---|---|---|
| FST_Phone portrait, fs 1.0 | Nothing | Pass |
| FST_Phone portrait, fs 2.0 | Version "Service" title crushed to a one-letter column beside the origin | Fixed (adaptive `ValueRow`); Quick Links sheet, Privacy sheet, Reset dialog pass |
| FST_Phone landscape, fs 1.0 / 2.0 | At 2.0 the shell top and bottom bars leave a short content viewport (shell-level, not Settings) | Pass; recorded, not changed here |
| FST_Phone system light theme | App stays dark | Pass (dark-only brand theme, deliberate) |
| FST_Tablet landscape / portrait, fs 1.0 / 2.0 | Sections 958–968 dp wide instead of the 840 dp cap | Fixed (modifier order); Quick Links menu, Privacy dialog, Reset dialog pass |
| FST_Resizable phone / foldable / tablet / desktop, fs 1.0 / 2.0 | Nothing beyond the two fixes | Pass; desktop column 840 dp and centred |
| FST_Book_Fold folded / half-open / unfolded, fs 1.0 / 2.0 | Nothing | Pass; half-open keeps the list before the hinge with Quick Links beyond it; at fs 2.0 the hinge split is off by design and the Service row stacks |
| FST_Passport_Fold folded / half-open / unfolded, fs 1.0 / 2.0 | Mid-scroll the floating Quick Links button briefly covers the end of a row | Pass (standard floating-button overlap; the row scrolls clear) |
| FST_TriFold folded (360 dp) / partial / unfolded, fs 1.0 / 2.0 | Folded: same Service-row crush as the phone | Fixed by the same `ValueRow`; partial and unfolded inline |
| TalkBack, FST_Phone fs 1.0 and 2.0 (`tools/android/talkback_walk.py`) | Silent after the Service Info live region announced (focus kept moving to Build) | Fixed (no live region); 99 items read in web order: top bar, sections, tabs, Quick Links |
| Reduced motion | Animator scale 0 (tool default) and in-app Reduce Motion: still track, no sweep | Pass |
| Motion (`--animations`, FST_Phone fs 2.0) | Quick Links sheet opens, expands and scrolls to Version | Pass |

Material 3 review (`material-3` skill, Compose guidance): switch rows are whole-row `toggleable(role = Switch)` list items with 48 dp minimum targets; Quick Links is a modal bottom sheet at compact width and a menu at medium/expanded; Reset is an M3 `AlertDialog`; the body column is capped at 840 dp on expanded windows; content stays on one side of a separating hinge. Deliberate deviations: the dark-only brand theme and translucent `GlassCard` surfaces over album art (product tokens, [android.md](../../platforms/android.md)); Service Info is not a live region (above). Contrast of every Settings text pair passes 4.5:1 (lowest 4.87:1, secondary text on a glass card).

## Validation: App Version build commit (issue #151, 2026-10-04)

Live public service, debug APK stamped with `FST_GIT_SHA=d12dbe5b…` (expected row "0.2.0 (1) · d12dbe5"), `device.py drive` with `FST_DEBUG_STILL_BACKGROUND=1`, animator scale 0. Each configuration jumped to Version through Quick Links (sheet below 600 dp, menu above) after the change, since rotation, resizing and font scale move the list.

| Configuration | Result |
|---|---|
| Unstamped build (FST_Phone, fs 1.0) | "0.2.0 (1)", no separator or suffix: pass |
| FST_Phone portrait, fs 1.0 / 2.0 | Inline at 1.0; at 2.0 the value stacks under "App Version" on one line: pass |
| FST_Phone landscape, fs 1.0 / 2.0 | Inline: pass |
| FST_Phone system light theme | App stays dark (dark-only brand theme, deliberate): pass |
| FST_Tablet landscape / portrait, fs 1.0 / 2.0 | Inline in the 840 dp column: pass |
| FST_Resizable compact / medium (1680×2400) / expanded, fs 1.0 / 2.0 | Compact 2.0 stacks; medium and expanded inline: pass |
| FST_Book_Fold folded / unfolded, fs 1.0 / 2.0 | Folded 2.0 stacks; otherwise inline: pass |
| FST_Passport_Fold folded / unfolded, fs 1.0 / 2.0 | Folded 2.0 stacks; otherwise inline: pass |
| FST_TriFold folded / partial / unfolded, fs 1.0 / 2.0 | Folded 2.0 stacks; partial and unfolded inline: pass |
| TalkBack (`talkback_walk.py`, FST_Phone) | "App Version. 0.2.0 (1) · d12dbe5" as one item after the section description, no role or action: pass |
| Connected `BandsSettingsJourneyTest#settingsTogglesResetAndLicenses` (stamped, FST_Phone) | Text, suffix and reading order assertions plus ATF: pass |

Material 3 (`material-3` skill, `references/component-catalog.md` § Lists): a read-only list item with a headline and supporting value, no touch target (not interactive), `onSurface`/`onSurfaceVariant` text roles. The " · " separator and 7-character commit match iOS. No user-visible change was needed (the row moved into `internal fun AppVersionRow` only so tests can render it with any text); the row never wraps mid-suffix in any configuration because `ValueRow` stacks the whole value under the title when it does not fit beside it.

## Open

- Consumers still owed by other lanes: Songs (icons, metadata order/visibility, Shop hide/highlight, leeway on leaderboard reads), Paths (default view, column order, warning dismissal).
