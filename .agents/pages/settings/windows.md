# Settings — Windows notes

> **What:** what the Windows Settings page implements, its persistence and native decisions, and open gaps. **Read when:** changing Settings or any `AppSettings` field on Windows. Behavior: [spec.md](spec.md).

## Implementation

| Piece | Where |
|---|---|
| Persisted model | `Festival.Core/Domain/AppSettings.cs` (all fields, `Sanitized`, list-aware `Equals`, `ResetAppSettings`), enums/codecs in `Domain/SettingsModels.cs` (`MetadataField`, `PathColumnKey`, `PathDisplayMode`, `SettingsOrder`, `ScoreLeeway`) |
| Page model | `ViewModels/SettingsViewModel.cs` (+ `InstrumentToggle`, `MetadataToggle`, `ReorderItemViewModel`, `FirstRunReplayItem`) |
| Page | `Festival.App/Pages/SettingsPage.xaml(.cs)`; Licenses: [licenses/windows.md](../licenses/windows.md) |
| Storage | `%LOCALAPPDATA%\FestivalScoreTracker\settings.json` (atomic replace; corrupt → defaults). Shared by every lane's Debug run on the host: restore anything you toggle while testing |

## Sections (web order) and effects

| Section | Controls (`fst.settings.*`) | Notes |
|---|---|---|
| App Settings (first, as on the web; no Profile section — deselect lives in the title-bar profile flyout) | `show-instrument-icons`, `enable-visual-order`, `song-row-order` (shown directly under the switch while it is on — no expander; visible metadata fields only, hidden ones keep their order after them), `path-default-view` (`RadioButtons` Image/Text under the description, `.image`/`.text`, like the web's radio rows), `path-column-order` (always shown), `filter-invalid-scores`, `leeway` (Slider −5…+5, step 0.1, thumb and header show `+1.0%`), `experimental-ranks` (disabled; sanitized to off), then `feedback.bug` / `feedback.feature` (Report an Issue / Request a Feature; shown only when `/api/features` reports `feedback: true`; see [feedback-form](../../controls/feedback-form/windows.md)) | Consumers: Songs/Song Detail/Paths lanes read the fields; this page only writes |
| Diagnostics (Debug build only) | `tap-diagnostics`, `tap-telemetry` (requires diagnostics; turning diagnostics off clears it) | No collector reads them yet |
| Item Shop | `shop-highlights` (web wording **Disable Item Shop Highlighting**; disabled while hidden; value retained), `hide-shop` | `AppSettings.ShopHighlightEnabled` is the effective flag; Shop nav visibility is the Songs lane's |
| Show Instruments | `instrument.<serviceId>` | Last visible chart cannot be turned off |
| Show Instrument Metadata | `metadata.<field>` (`last-played`) | Anonymous: only Intensity enabled (as on iPhone); all may be off |
| Accessibility (native) | `reduce-motion`, `disable-artwork-animation`, `more-contrast`, `less-transparency`, `save-data` | Additive only. Increase Contrast whitens secondary text and strengthens card strokes; Reduce Transparency makes cards opaque (`MainWindow.Settings.cs`, `ApplyTransparency`) |
| Version | `app-version`, `service-version` | App Version is `AppVersionInfo.SettingsText`: the display version (the stamped `YYMM.DD.NN` `InformationalVersion` from the `windows/v*` tag; `0.1.0` for local builds) plus ` · <sha7>` from `AssemblyMetadata("FstGitSha")`, which `Festival.App.csproj` stamps from `-p:FstGitSha=`, else SourceLink's `SourceRevisionId`, else `git rev-parse HEAD` (the SDK reader finds no commit in a worktree whose branch ref is only packed; issue #21); omitted when missing, empty, `dev` or non-hex (issue #43). What's New and the User-Agent keep the plain `Display` version. The card body is `Controls/SettingValueGrid` (issue #243): values share a right column while every label + 12 epx + value fits at natural width, else every value stacks 4 epx under its label (`SettingValueLayout.ShouldStack`; Fluent "reposition side details below main", Android `ValueRow` #121). Before, a release-length `2610.04.01 · <sha7>` at 200% text in a compact window clipped `Build Configurati`. Labels and values wrap; UIA order stays label → value. Validated live (#243): compact/medium/wide/maximized/snap-left, light/dark/HC Night sky/HC Desert, text 200%, display 100/150%, keyboard, 0 Axe errors (`tools/windows/journeys/a11y-settings-version.json`, journey `version`). Service Version reads `/api/version` once per page load ("Loading" → value, "Unavailable" on failure, retried next visit) |
| Service Info | `service-info.state` (state description text), `.process`, `.phase`, `.attempt`, `.last-published` (date text) | Test IDs sit on the text or named elements. A `Border`, `Grid` or `StackPanel` without a name has no UIA element, so an ID on one is unreachable; the card-level `service-info` ID was removed (#275). Web `SettingsServiceProgressCard`: `SettingsServiceInfoViewModel` polls `/api/service-info` every 5 s while the page is loaded (30 s while the window is hidden, 3 s timeout), reduced by `Domain/ServiceProgress.cs` (port of the web/Apple monotonic reducer and label tables). Unknown totals show the empty track instead of a looping shimmer. Web rows only (issue #81, port of iOS #22): title, bar and the registered-band discovery attempt line (`attemptProgress`, schema 1, validated and monotonic within a phase attempt) at the web's 4 px gap; percent, units and attempts are the phase row's Narrator name, not printed captions. That name follows the web bar's `aria-valuetext`: phase, subphase, percent or "Total not yet known", units and attempts as separate sentences (`SpokenPhaseTitle`, `ServiceProgress.ProgressUnknownTotal`; #275). The visible title keeps "Phase · Subphase". The card makes no announcement on each poll; the state text is a polite live region (as on Android, #121); the native freeze row was dropped; Last Successful Publication hides while loading or failed ("Failed to load data", web); at Windows text size ≥ 150% (`ServiceInfoText.StacksStateRow`, applied in `SettingsPage.xaml.cs`, live on `TextScaleFactorChanged`) the process state stacks under the label. The web has no publication check, so **Check Publication was removed** (batch 6.15) |
| First Run Guides | `first-run.<pageKey>` (no slide counts; blue web `btnPrimary` Show buttons via card-scoped lightweight styling, `Themes/FirstRunButtonResources.xaml`) | Replay: [first-run/windows.md](../../controls/first-run/windows.md) |
| Licenses | `licenses` | Web navigation row: the section header is the link, chevron trailing, no card. Pushes `/settings/licenses` on the Settings stack |
| Privacy Policy | `privacy-policy`; dialog `fst.privacy-policy.*` ([control notes](../../controls/privacy-policy/windows.md)) | Same navigation row as Licenses (issue #98). Opens `Festival.App/Controls/PrivacyPolicyDialog.cs` in the shared `FestivalDialog` (title "Privacy Policy", spanning Close; Esc and an outside click also close). The csproj links `contracts/privacy-policy.json` as `Assets\privacy-policy.json`; `Festival.Core/Domain/PrivacyPolicy.cs` parses it (1 MB cap, schema 1, invalid blocks dropped, unreadable → "could not be loaded"). Selectable `TextBlock`s follow the Windows text size, section titles are Narrator level-2 headings, bullets are Raw, HTTPS addresses are `Hyperlink`s. The scroller is a tab stop, so the dialog opens focused on the text (arrow/Page keys scroll); focus returns to the row on close. Tests: `PrivacyPolicyTests` (real contract via a linked fixture) |
| Reset | `reset` | Web `resetRow`: header left, red (`#C62828`) Reset All Settings right. ContentDialog confirm; restores app settings only (starts from `this`, so the player, Songs sort/filter and other Songs-owned fields survive). `LeaderboardRankBy` is navigation state and is kept |

## Decisions

- Windows 11 Settings-card layout: title + description left (4 epx apart), bare right-aligned control. Bare `ToggleSwitch`es need a **local** `MinWidth="0" Width="52"`; the default style's 154-epx `MinWidth` otherwise reserves On/Off text space.
- Reorder lists (batch 6.11) are `ListView`s with `CanReorderItems` (native drag to reorder, like the web's dnd-kit list) over `ObservableCollection<ReorderItemViewModel>`; `DragItemsCompleted` → `SettingsViewModel.CommitDrag`. Rows copy the web look (grip dots, semibold label, subtle surface, row separators). Move up/Move down buttons stay for keyboard and Narrator users.
- Settings polling starts/stops on the page's `Loaded`/`Unloaded`: section switches swap frames without navigation events.
- Label "Difficulty" (web), not "Game Difficulty" (batch 6.13).
- Filter Invalid Scores (batch 6.12) is applied by the service through the leaderboard `leeway` query. Pages that pass it must re-read when the effective leeway (0.1 steps) changes, including when returning to a cached page: the song leaderboard does (`FilterInvalidScoresTests`). Live read-only check: `python tools/windows/tests/live_filter_invalid_scores.py` (Winterfest Wish Lead: 10,009 local entries unfiltered, 7 at +1.0%, 2026-09-28).
- Quick Links: header menu or wide pane, see [quick-links/windows.md](../../controls/quick-links/windows.md).
- Not ported: profile name refresh (POST), ZIP export, mouse light trails / mobile header buttons (no equivalent chrome).

## Open

- `LicensesPage.xaml` (a separate page) still has hard-coded translucent-white hover literals; other pages' destructive buttons alias `FSTDanger*` with `StaticResource`, so a contrast theme switched on while they are open keeps the brand red until the page reloads (Settings merges `Themes/DangerButtonResources.xaml` instead).
- One Debug journey run (2026-10-03, shared desktop) crashed with a stowed `COMException` E_FAIL from a managed `MeasureOverride` forwarding to native measure after Feedback opened; four replays (same sequence, live Desert and live 200% text with Feedback open) did not reproduce it. Watch `diagnostics.log` for a repeat.
- Screenshots: `windows/reports/screenshots/settings-{compact,medium,wide}.png`, `settings-quick-links-menu-compact.png`.

## Validation (issue #214, 2026-10-03)

Fixture matrix (`a11y_matrix.py --scan --tabs 60` with `journeys/settings-states.json`: Visual Order, Filter Invalid Scores and Hide Shop seeded on, a shot at each section) plus the live public service. Axe 0 errors and no focus leaving the window or repeating in every run:

| Configuration | Result |
|---|---|
| Compact, medium, wide, snapped right, maximized | Pass: 53 stops (compact/snap) / 55 (wide/maximized) expanded; Quick Links menu below 1150 epx, pane above |
| Light and dark system theme | Pass, unchanged (dark-only app, documented deviation; contrast themes are followed) |
| Desert, Night sky (cold launch) | Fixed: reorder-list outline and separators were invisible, First Run "Show" chips stayed brand blue, link-row hover was translucent white, progress bar brand purple. Now Window/WindowText rows, ButtonFace/ButtonText chips (Highlight on hover), Highlight outline on link-row hover, Highlight/GrayText progress |
| Contrast theme switched on while Settings is open | Fixed: `StaticResource` aliases kept the old brushes; scoped button styling now merges `Themes/{NavRow,FirstRun,Danger}ButtonResources.xaml` theme dictionaries |
| Text 200% | Pass: rows wrap, switches stay right-aligned, nothing clipped |
| Display 100% and 150% | Pass |
| Keyboard | Pass (`settings-keyboard` page): Space toggles Visual Order with focus kept, Enter on Move Score down → "Score, position 2 of 8", Enter opens Reset with Cancel default, Esc closes and returns focus to Reset All Settings |

Journeys (`tools/windows/journeys/settings.py`): visual order persists across relaunch, Filter Invalid Scores reveals Leeway, Hide Shop disables Shop highlighting, the last visible chart cannot be hidden, telemetry needs diagnostics, Reset Cancel keeps and Reset restores app settings (Songs sort kept), Licenses/Back, Privacy Policy, What's New, Feedback cancel and First Run replay. `SettingsContrastMarkupTests` guards the markup.

Deliberate deviations from `winui-design`: dark-only theme (web parity; light/dark system setting does not change it); hand-built Settings-card rows instead of the Community Toolkit `SettingsCard` (no extra package; one card per web section); reorder lists keep web grip/row look with Fluent `ListView` drag and Move buttons.

## Validation: CHOpt Path Default View (issue #256, 2026-10-05)

No app change needed. `path-default-view` is an inline Fluent `RadioButtons` group with Image and Text options. `winui-design` maps "pick one of 2–3 options" to `RadioButtons` (WinUI Gallery `gallery-radiobutton-2`). `winapp find-api` confirmed `Header`, `SelectedIndex` and `MaxColumns` on the app's references. There is no expander, so there is no expanded/collapsed state to announce. UIA reports:

- a level-3 heading "CHOpt Path Default View" and the description;
- a Group named "CHOpt Path Default View" (`RadioButtons`);
- Image and Text `RadioButton`s with the SelectionItem pattern, so Narrator reads the name and the selected option;
- then the Column Order heading.

Fixture matrix: `a11y_matrix.py --scan --pages journeys/a11y-settings-path-view.json` runs Image selected, Text seeded and the keyboard page `kb-settings-path-view`. Axe found 0 errors in every configuration below.

| Configuration | Result |
|---|---|
| Compact, medium, wide, maximized, snap-left, snap-right | Pass: the group stays under its description in one column at every width |
| Light and dark system theme | Pass, unchanged (dark-only app) |
| Desert, Night sky | Pass: selected dot and focus rectangle use contrast colours |
| Text 200% | Pass: title, description and options wrap with nothing clipped. The stock radio glyph stays top-aligned to the taller label |
| Display 100%, 150%, 150% + text 200% | Pass |
| Keyboard | Pass: Tab from Visual Order lands on the selected option. Down/Up move focus and selection together. Tab leaves the group and Shift+Tab returns to the selected option |
| Live public service | Pass: Settings and Song Detail Paths open in the saved view for a real song (`/api/songs`, `/api/paths` only) |

Journey `path-default-view` (`journeys/settings.py`, `Journey.relaunch_to`):

1. Select Text: Settings stays open and saves `"pathDefaultView": "Text"`.
2. Relaunch: Text is still selected.
3. Relaunch to a song: Paths opens the table.
4. Close Paths, return to Settings and select Image: saves `"Image"`.
5. Paths now opens the image.

## Validation: Service Info (issue #275, 2026-10-06)

The #81 card already shows the web rows: the state, then the phase title, bar and band-discovery attempt line 4 epx apart, then Last Successful Publication. Attempt counts never go backwards, and the state stacks at text ≥ 150%. `winui-design`: a determinate `ProgressBar` for known-total progress (WinUI Gallery `gallery-progressbar-2`) and Settings-card label/description rows; `winapp find-api` confirmed `AutomationProperties.LiveSetting` on WinAppSDK 2.3.9.

Fixed:

- **Unreachable test IDs.** `fst.settings.service-info`, `.state` and `.last-published` were on a `Border`, `Grid` and `StackPanel`, which have no UIA element. `.state` and `.last-published` now sit on their text, and the card ID is gone (the "Service Info" heading identifies it).
- **Spoken text differed from the web.** The phase row's Narrator name now matches the web bar's `aria-valuetext`: "Phase. Subphase. 24.8%. …" and "Total not yet known". Before, it said "Phase · Subphase" and "In progress — total not yet known".

Fixture matrix: `a11y_matrix.py --scan --pages journeys/a11y-settings-service-info.json`. Every state has a page (`service_info_fixture.py`). Axe found 0 errors in every run:

| Configuration | Result |
|---|---|
| Compact, medium, wide, maximized, snap-left, snap-right | Pass: idle, band discovery, unknown total, failed, stopped, never published and service unavailable. The bar spans the card and the attempt line wraps under it |
| Attempt progress (compact) | Pass: served 1,310/70, then 1,200/60 twice, then 1,400/80. The line stays at 1,310 until 1,400 arrives, and the Narrator name follows |
| Light and dark system theme | Pass, unchanged (dark-only app) |
| Desert, Night sky | Pass: Highlight fill on a GrayText track, card outlines in WindowText, spinner visible |
| Text 150/200/225% | Pass: Updating/Idle stacks under its label; the attempt line wraps. Text 200% with display 100% passes too |
| Display 100% and 150% | Pass |
| Keyboard | Pass: the card has no tab stops, so Tab goes from What's New to First Run Songs and Shift+Tab returns. Focus is visible in every mode |
| Live public service | Pass: live update phases (Band Maintenance with known and unknown totals, Computing Rankings) at every size, Desert, text 200% and display 100%, 0 Axe errors; a 16 s recording shows the card following the 5 s polls (`settings-service-info-live`, `-live-film`) |

Narrator: the "Service Info" heading, then the state label and description (a polite live region), the process state, the phase group (name = spoken progress), the attempt line and the publication row. Kept deliberately:

- The card makes no announcement on each poll; Android made the same choice in #121.
- A failed poll after a success shows "Failed to load data" (Android rule; the web keeps the old data).
- The `ProgressRing` reports as a "Busy" progress bar even with `AccessibilityView="Raw"`, which Axe accepts.
- Loading lasts at most the 3 s timeout, so unit tests cover it rather than the matrix.
