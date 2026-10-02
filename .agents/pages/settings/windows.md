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
| App Settings (first, as on the web; no Profile section — deselect lives in the title-bar profile flyout) | `show-instrument-icons`, `enable-visual-order`, `song-row-order` (shown directly under the switch while it is on — no expander; visible metadata fields only, hidden ones keep their order after them), `path-default-view` (`RadioButtons` Image/Text under the description, `.image`/`.text`, like the web's radio rows), `path-column-order` (always shown), `filter-invalid-scores`, `leeway` (Slider −5…+5, step 0.1, thumb and header show `+1.0%`), `experimental-ranks` (disabled; sanitized to off) | Consumers: Songs/Song Detail/Paths lanes read the fields; this page only writes |
| Diagnostics (Debug build only) | `tap-diagnostics`, `tap-telemetry` (requires diagnostics; turning diagnostics off clears it) | No collector reads them yet |
| Item Shop | `shop-highlights` (web wording **Disable Item Shop Highlighting**; disabled while hidden; value retained), `hide-shop` | `AppSettings.ShopHighlightEnabled` is the effective flag; Shop nav visibility is the Songs lane's |
| Show Instruments | `instrument.<serviceId>` | Last visible chart cannot be turned off |
| Show Instrument Metadata | `metadata.<field>` (`last-played`) | Anonymous: only Intensity enabled (as on iPhone); all may be off |
| Accessibility (native) | `reduce-motion`, `disable-artwork-animation`, `more-contrast`, `less-transparency`, `save-data` | Additive only. Increase Contrast whitens secondary text and strengthens card strokes; Reduce Transparency makes cards opaque (`MainWindow.Settings.cs`, `ApplyTransparency`) |
| Version | `app-version`, `service-version` | App Version is `AppVersionInfo.SettingsText`: the stamped `YYMM.DD.NN` (`InformationalVersion` from the `windows/v*` tag; `0.1.0` for local builds) plus ` · <sha7>` from assembly metadata `FSTGitSHA` (`windows/Directory.Build.targets`: `-p:FstGitSha`, else the SDK's `SourceRevisionId`, else `git rev-parse HEAD` because the SDK reader finds no commit in a worktree whose branch ref is only packed; omitted when unknown, iPhone parity, issue #21). What's New and the User-Agent keep the plain version. Service Version reads `/api/version` once per page load ("Loading" → value, "Unavailable" on failure, retried next visit) |
| Service Info | `service-info`, `.state`, `.process`, `.phase`, `.freeze`, `.last-published` | Web `SettingsServiceProgressCard`: `SettingsServiceInfoViewModel` polls `/api/service-info` every 5 s while the page is loaded (30 s while the window is hidden, 3 s timeout), reduced by `Domain/ServiceProgress.cs` (port of the web/Apple monotonic reducer and label tables). Unknown totals show the empty track plus "In progress — total not yet known" instead of a looping shimmer. The web has no publication check, so **Check Publication was removed** (batch 6.15) |
| First Run Guides | `first-run.<pageKey>` (no slide counts; blue web `btnPrimary` Show buttons via card-scoped lightweight styling) | Replay: [first-run/windows.md](../../controls/first-run/windows.md) |
| Licenses | `licenses` | Web navigation row: the section header is the link, chevron trailing, no card. Pushes `/settings/licenses` on the Settings stack |
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

- The shell's `NavigationView` stays `PaneDisplayMode="Left"` at compact widths; settings rows get ~260 epx unless the pane is collapsed. TODO(orchestrator): shell lane should switch to `Auto` (LeftCompact/LeftMinimal) below ~1008/640 epx.
- UI automation (FlaUI) journeys for reset/relaunch persistence are not yet written; persistence is covered by `SettingsModelsTests.JsonStore_RoundTripsEveryAppSetting`.
- Screenshots: `windows/reports/screenshots/settings-{compact,medium,wide}.png`, `settings-quick-links-menu-compact.png`.
