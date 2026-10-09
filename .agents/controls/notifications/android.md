# Notifications — Android notes

> **What:** the Android top-bar bell, sheet, feed read and seen state. **Read when:** changing notifications on Android. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md). Endpoint safety: [service-safety](../../platforms/service-safety.md).

## Implementation

| Piece | Where |
|---|---|
| Read | `data/notifications/FestivalApiNotifications.kt`: `FestivalApi.playerNotifications(accountId, limit)` → pinned keyless `GET /api/player/{id}/notifications?limit=` through the `ServiceEndpoint.Feature` seam (pure read per `FSTService/Api/ImprovementNotificationEndpoints.cs:10-31`; verified by the iPhone and Windows lanes) |
| Wire + rules | `core/notifications/Notifications.kt`: envelope/rows, `validate` (unique safe GUIDs, kinds, song IDs), `isGenerated`, `NotificationRouting` (web destination + ranking-metric tables, coalesced events), `NotificationText` (delegates to `core/notifications/NotificationTextEngine.kt`, the full player-scoped port of web `notificationText.ts`, issue #180: coalesced events, derived Full Combo/gold-star results, redundant star events dropped, priority order, `Song · Instrument` / `{Rank} Improved` / `Rank Updates · {scope}` / `{scope} · Improvements` titles, statement paragraphs, emphasis, every flag plus per-chart flag groups; en-US numbers, `#1,234` ranks, shop-song copy, relative time), `NotificationMediaRules` (web media rail: art, art over an instrument grid for multi-chart rows, else the chart icon; Lead when none), `NotificationFlagKind`/`NotificationFlagGroup`, lenient payload decoders (web `numberValue`/`booleanValue`/`stringValue`) |
| Seen | `core/notifications/NotificationSeenStore.kt`: settings DataStore key `fst.notifications.seen.v1` (registered `Kept`), per-account GUID lists pruned to the current feed, ≤400 per account, ≤20 accounts |
| Model | `presentation/notifications/NotificationsViewModel.kt`: NoPlayer/Loading/Failed/Empty(generated)/Loaded(New, Older), unread badge (99+), refresh on player change and each open (no polling), a failed refresh keeps the last feed; row art via the shell's `artwork` lookup (catalogue art, else the shop payload's, through `FestivalApi.artworkUrl`) |
| UI | `ui/notifications/NotificationsUi.kt`: `NotificationsBell` (M3 `BadgedBox`, gold badge) in the shell's `ShellActions.notifications` slot before the avatar; `NotificationsSheet` (M3 modal bottom sheet, width-capped on large windows) |

## Row design (web `MobileNotificationsModal`, operator batch 6, 6.34)

- Upper-case 74%-white section headings (`NEW` / `OLDER`, spoken as written); each row is its own `surfaceSubtle` card (10 dp radius, `#1E2A3A` hairline, 4 dp apart, 24 dp side margins).
- 64 dp media rail: 54 dp album art, 44 dp art above an 18 dp two-column instrument grid when the row touches several charts, else a 36 dp instrument icon. Decorative; the shared in-process Coil loader like other rows. Combo media and its icon/art cycle need band/combo feeds (not read natively).
- Bold marquee title, 12 sp white message with the web's bold values (scores, ranks, instrument, song, "Full Combo", "gold stars", "x to y stars"); several statements are separate paragraphs (web `pre-line`). Flags: a wrapping row of colour-coded pills (web `FLAG_COLORS`, 12 sp semibold white, 8 dp radius = M3 chip `small` shape, 2 dp 18%-white border, 2 dp gaps), one per flag; multi-chart song rows show one line per chart, a 20 dp decorative instrument icon before that chart's pills (web flag groups). Pills are non-interactive status labels inside the one clickable row, not M3 `AssistChip`s, and keep the web's 12 sp (Label Medium) rather than the chip's Label Large; white text on every flag colour is ≥ 4.5:1 (`NotificationsSheetUiTest.flagColoursMatchTheWeb`).
- Trailing: gold `#FACC15` unread dot above a 72%-white chevron (chevron only when the row navigates). No visible time (the web row shows none); TalkBack reads "Unread. Title. Message. Flags. Time" (every flag in words, per chart for flag groups, e.g. "Lead: New High Score. Bass: Full Combo", so meaning never depends on colour; the time in full words, "5 minutes ago", "1 hour ago", "September 28"), and navigable rows add "Open notification."
- Empty state: bell-off glyph, "No notifications available", generated/not-generated body.

## Behavior

- Tapping a row marks it seen; a row with a destination also closes the sheet and pushes Song Detail (`SongDetailRoute`) or, for rank events, `FullRankingsRoute(instrument, rankBy)` (Leaderboards hub without an instrument). Live coalesced rank events carry no instrument, so routing falls back to the row's `instrument` (issue #136). Closing the sheet marks every loaded row seen.
- Settings → Experimental Ranks ([experimental-ranks](../../patterns/experimental-ranks.md) R4, #541): while it is off, `NotificationRouting.projectExperimentalRanks` (web `projectExperimentalRankNotification`) hides rows whose rank events are all experimental and reduces a mixed coalesced row to its other events; the view model re-projects when the setting changes, and Mark All Read marks only the shown rows.
- No-player state offers Select Player Profile (opens the profile sheet). Never sends selected-profile headers (the gate rejects them; the UI journey asserts it).
- Debug: `FST_DEBUG_SHEET=notifications` opens the sheet at launch.

## IDs and evidence

`fst.shell.notifications` (label "Notifications, N unread"), `fst.notifications.sheet`, `.list`, `.row.<guid>` (test-only semantics `NotificationMediaKind` and `NotificationFlags`, e.g. `FirstPlay,FullCombo,GoldStars` or `Lead:NewHighScore|Bass:FullCombo`), `.empty`, `.failed`, `.loading`, `.no-player`. Tests: `notifications/NotificationsTest.kt`, `notifications/NotificationTextEngineTest.kt` (live coalesced shapes, derived results, priority, flag groups, aggregate/rank variants, lenient decoding), `ui/notifications/NotificationsSheetUiTest.kt`, `ui/notifications/NotificationsStatesUiTest.kt` (Robolectric, one test per reachable state), `journeys/NotificationsDeviceTest.kt` (connected: ATF, reading order, 48 dp, hinge, navigation), `settings/SettingsUiTest.kt`. Screenshot: `android/reports/screenshots/notifications-phone.png` (mock `fixture-player-1`).

## Validation (issue #136, 2026-10-04)

Emulator API 37, debug build, live public service (keyless `GET /api/player/{id}/notifications` only; no selected-profile headers), public player SFentonX (12 live rows: rank, total-score, personal-best and first-play events). Dark scheme only by repo rule: with the system light theme the app stays dark. `pm clear` before each run makes every row unread.

| Configuration | Result |
|---|---|
| FST_Phone portrait, font 1.0 and 2.0; system light and dark | OK: `NEW` rows with gold dots, chevrons only on navigable rows, flag pills. At 2.0 titles wrap (the marquee title wraps at large text), the message and pills grow and nothing clips; the list scrolls. Closing marks every row seen; reopening shows `OLDER` only. |
| FST_Phone landscape, font 1.0 and 2.0 | OK; the sheet opens partially expanded and the drag handle expands it. |
| FST_Phone navigation | Personal-best row → Song Detail (Night Terror, Drums); back; Karaoke weighted-rank row → **Karaoke full rankings** with SFentonX pinned (was the Leaderboards hub, fixed below). |
| FST_Phone no profile (`FST_DEBUG_ANONYMOUS`) | OK: "Select a player profile…" with Select Player Profile; no feed request. |
| FST_Phone reduced motion (animator scales 0) | The sheet opens and closes without animation; long titles end in an ellipsis instead of scrolling (`FestivalMarqueeText`). |
| FST_Tablet landscape ⇄ portrait, font 1.0 and 2.0 | OK; centred sheet (640 dp max) opens partially expanded; rank row opens full rankings. |
| FST_Resizable phone / foldable / tablet / desktop, desktop font 2.0 | OK; bottom bar at compact, rail at medium and expanded, centred sheet. |
| FST_Book_Fold folded / unfolded / half-open, half at font 2.0 | OK. Half-open: the sheet sits in the start pane beside the vertical hinge (`festivalSheetHingeSide`). Long titles stay on one line at 1.0 (marquee, or an ellipsis with animations off; TalkBack reads the full title) and wrap at 2.0. |
| FST_Passport_Fold folded / unfolded / half-open, half at font 2.0 | OK; same hinge behaviour. |
| FST_TriFold folded / partial / unfolded | OK with `am start --display 0` (this AVD otherwise launches on display 2); flat hinges, so the sheet stays centred. |

- **Fixed:**
  - Live coalesced rank events carry no `instrument`, so rank rows opened the Leaderboards hub. Routing now falls back to the row's instrument (`NotificationsTest.liveCoalescedRankEventsOpenTheRowsChartRankings`). The web always opens the hub with `?rankBy=`; Android follows this spec's "with an instrument, full-rankings destination".
  - TalkBack row labels now include the flag in words (spec: "native screen-reader labels append flag names") and read the time in full ("5 minutes ago" rather than "5m").
- Accessibility:
  - `NotificationsDeviceTest` (ATF on every step, reading order, 48 dp targets, hinge) passes on FST_Phone and FST_Book_Fold half-open. Asserted order: sheet title → `NEW` → unread rows (song row before rank row) → after closing and reopening, `OLDER` → seen rows with no "Unread"; the empty title reads before its body and the no-profile message before Select Player Profile (which sends no feed request). Every request is keyless with no selected-profile header.
  - Touch targets: Close and every row are asserted at least 48 dp; the bell and Select Player Profile are M3 icon/filled buttons with 48 dp touch bounds.
  - Colour is never the only signal: unread is spoken ("Unread.") and flags are named.
- Material 3 deviations, deliberate:
  - The bell badge is brand gold rather than the error colour.
  - A bottom sheet rather than a side sheet on expanded widths (web/Apple parity, centred 640 dp max).
  - Dark scheme only.
  - Web `FLAG_COLORS` pills with white text.
  - 74%-white upper-case section headings.
  - The sheet is kept beside a separating hinge ("Never place interactive content or critical information across the hinge area").
- States → tests (Robolectric `ui/notifications/NotificationsStatesUiTest.kt`):

| State | Test |
|---|---|
| empty-generated | `emptyGeneratedFeedSaysNotificationsWillAppear` |
| empty-not-generated | `emptyNotGeneratedFeedSaysAfterTheNextUpdate` |
| loaded | `loadedFeedListsEveryRowNewestFirstWithDestinationsSpoken` |
| unread-section | `unreadRowsSitUnderNewAndTheBellCountsThem` |
| older-section | `seenRowsSitUnderOlderAfterTheUnreadOnes` |
| tap-navigate-song | `songRowMarksSeenClosesAndOpensSongDetail` |
| tap-navigate-rankings | `rankRowsOpenFullRankingsOrTheLeaderboardsHub` (+ `NotificationsTest.liveCoalescedRankEventsOpenTheRowsChartRankings`) |
| no-profile | `noProfileAsksForAPlayerWithoutReading` |
| (extras) | `rowWithoutADestinationOnlyMarksItSeen`, `failedReadOffersRetry`; connected `NotificationsDeviceTest` |

## Validation (issue #180, 2026-10-06)

Re-checks the #76 web row design (media rail, bold values, colour-coded flags) with the same setup as #136: emulator API 37, debug build, live public service, SFentonX (11 live rows). **Found:** Android ported only web's single-event copy and one pill per row. Live coalesced rows (`player_first_score` carrying `player_fc_achieved` and `player_gold_stars_achieved`, personal bests with rank climbs) dropped the Full Combo, gold-star and rank clauses and chips. Aggregate and multi-rank statements and per-chart flag groups were also missing. **Fixed:** `NotificationTextEngine.kt` ports the whole web `notificationText.ts`. Live rows now read e.g. "You set a new personal best on **Lead** for **Take Me Higher** with **171,030** points, got a **Full Combo**, earned **gold stars**, and climbed from **#4,223** to **#97**." with New High Score / Full Combo / Gold Stars / Rank Up pills.

| Configuration | Result |
|---|---|
| FST_Phone portrait and landscape, font 1.0 and 2.0 | OK: album art rail, bold values, every coalesced pill. At 2.0 the text and pills wrap with no clipping. |
| FST_Tablet portrait and landscape, font 1.0 and 2.0 | OK: centred 640 dp sheet; at 2.0 four pills wrap to two lines. |
| FST_Resizable medium / expanded / desktop (desktop also at font 2.0) | OK: rail at medium and expanded, centred sheet. Compact width is covered by FST_Phone. |
| FST_Book_Fold folded / unfolded / half-open (half also at font 2.0) | OK: half-open puts the sheet in the start pane beside the hinge. |
| FST_Passport_Fold folded / unfolded / half-open at font 2.0 | OK. |
| FST_TriFold folded / partial / unfolded (`--display 0`) | OK. |

- Accessibility:
  - TalkBack reads "Unread. Title. Message. Flags. Time", naming every pill in words (per chart for flag groups). Album art is decorative.
  - White text on every flag colour is at least 4.5:1 (`flagColoursMatchTheWeb`).
  - Connected `NotificationsDeviceTest` passes 3/3 on FST_Phone and on FST_Book_Fold half-open: ATF checks, reading order, 48 dp targets and the hinge.
- The AVDs are shared: other lanes install their own builds, and one older build showed the pre-fix rows. Always drive evidence with `device.py drive --apk …`. A higher installed `versionCode` no longer needs a manual uninstall: `device.py` replaces it ([android.md](../../platforms/android.md), issue #190).
- M3 deviations (deliberate; web parity): Label Medium pills instead of the chip's Label Large; non-interactive pills instead of `AssistChip`. Otherwise as in #136.

## Open

- Band feeds and combo copy (not read natively); scroll-visibility seen marking.
- A rank row without an instrument opens the Leaderboards hub without its Rank By (`LeaderboardsRoute` takes none; the web passes `?rankBy=`). Live player rank rows always name an instrument.
