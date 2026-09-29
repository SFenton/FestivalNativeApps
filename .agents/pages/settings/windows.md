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
| App Settings (first, as on the web; no Profile section — deselect lives in the title-bar profile flyout) | `show-instrument-icons`, `enable-visual-order`, `song-row-order` (Expander with Move up/down rows), `path-default-view` (`RadioButtons` Image/Text under the description, `.image`/`.text`, like the web's radio rows), `path-column-order`, `filter-invalid-scores`, `leeway` (Slider −5…+5, step 0.1, thumb and header show `+1.0%`), `experimental-ranks` (disabled; sanitized to off) | Consumers: Songs/Song Detail/Paths lanes read the fields; this page only writes |
| Diagnostics (Debug build only) | `tap-diagnostics`, `tap-telemetry` (requires diagnostics; turning diagnostics off clears it) | No collector reads them yet |
| Item Shop | `shop-highlights` (web wording **Disable Item Shop Highlighting**; disabled while hidden; value retained), `hide-shop` | `AppSettings.ShopHighlightEnabled` is the effective flag; Shop nav visibility is the Songs lane's |
| Show Instruments | `instrument.<serviceId>` | Last visible chart cannot be turned off |
| Show Instrument Metadata | `metadata.<field>` (`last-played`) | Anonymous: only Intensity enabled (as on iPhone); all may be off |
| Accessibility (native) | `reduce-motion`, `disable-artwork-animation`, `more-contrast`, `less-transparency`, `save-data` | Additive only. Increase Contrast whitens secondary text and strengthens card strokes; Reduce Transparency makes cards opaque (`MainWindow.Settings.cs`, `ApplyTransparency`) |
| Version | `app-version` | Service Version is a disclosed placeholder (`/api/version` not allowlisted) |
| Service | `check-publication`, `publication-status` | Forced publication + catalogue re-read (keyless public GETs) |
| First Run Guides | `first-run.<pageKey>` | Replay: [first-run/windows.md](../../controls/first-run/windows.md) |
| Licenses | `licenses` | Pushes `/settings/licenses` on the Settings stack |
| Reset | `reset` | ContentDialog confirm; restores app settings only (starts from `this`, so the player, Songs sort/filter and other Songs-owned fields survive). `LeaderboardRankBy` is navigation state and is kept |

## Decisions

- Windows 11 Settings-card layout: title + description left (4 epx apart), bare right-aligned control. Bare `ToggleSwitch`es need a **local** `MinWidth="0" Width="52"`; the default style's 154-epx `MinWidth` otherwise reserves On/Off text space.
- Reorder uses Expanders with numbered rows and Move up/Move down buttons (keyboard/Narrator friendly) instead of drag-only lists.
- Quick Links: header menu or wide pane, see [quick-links/windows.md](../../controls/quick-links/windows.md).
- Not ported: Service Progress (`/api/service-info` not allowlisted), profile name refresh (POST), ZIP export, mouse light trails / mobile header buttons (no equivalent chrome).

## Open

- The shell's `NavigationView` stays `PaneDisplayMode="Left"` at compact widths; settings rows get ~260 epx unless the pane is collapsed. TODO(orchestrator): shell lane should switch to `Auto` (LeftCompact/LeftMinimal) below ~1008/640 epx.
- UI automation (FlaUI) journeys for reset/relaunch persistence are not yet written; persistence is covered by `SettingsModelsTests.JsonStore_RoundTripsEveryAppSetting`.
- Screenshots: `windows/reports/screenshots/settings-{compact,medium,wide}.png`, `settings-quick-links-menu-compact.png`.
