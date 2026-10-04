# Notifications — Windows notes

> **What:** the Windows title-bar bell, flyout, feed read and seen state. **Read when:** changing notifications on Windows. Behavior: [spec.md](spec.md). Endpoint safety: [service-safety](../../platforms/service-safety.md).

## Implementation

| Piece | Where |
|---|---|
| Read | `Data/NotificationsApi.cs`: `client.GetPlayerNotificationsAsync(accountId, limit)` → pinned keyless `GET /api/player/{id}/notifications?limit=` (the service classifies it publication-bound). Kept as an extension with a sync `Decode` |
| Wire + rules | `Data/NotificationModels.cs`: envelope/row records, `Validate` (unique safe GUIDs, kinds, song IDs), `IsGenerated`, `NotificationRouting` (destination + ranking metric, `notificationDestination.ts`/`notificationRanking.ts`), `NotificationMediaRules.SurfaceInstruments` (payload `coalescedInstruments` + coalesced events + the row's chart, canonical order), `NotificationText` (player single-event copy, titles `Song · Instrument` / `{Rank} Improved`, `FlagKind` + web labels, `Emphasize` web bold runs, en-US `toLocaleString` numbers, `#1,234` ranks, shop-song title/message with payload art fallback), `NotificationFlagKinds.Argb` (web `FLAG_COLORS`) |
| Row visuals | `Controls/NotificationRowVisuals.cs`: attached `Parts` (bold `Run`s in the message `TextBlock`), `IconFiles` (2-column 18 epx instrument grid, Raw) and `FlagBrush` |
| Seen | `Data/NotificationSeenStore.cs`: `notifications-seen.json`, per-account GUID lists pruned to the current feed, ≤400 per account, ≤20 accounts |
| Model | `ViewModels/NotificationsViewModel.cs`: states NoPlayer/Loading/Failed/Empty/Loaded, New/Older, unread badge (99+), refresh on launch, player change and each open (no polling), failed refresh keeps the last feed |
| UI | `Controls/NotificationsBell.xaml`: bell before the avatar in `TitleBar.RightHeader`, `InfoBadge` count inside the bell's 36×32 box (never negative margins: the button clips them), light-dismiss flyout |

## Behavior

- Rows follow the web `NotificationRow` (operator batch 6.34/7.20, issue #76): a 64 epx leading media rail (`NotificationPresentation.MediaKind`: 54 epx album art via `SongArt`; 44 epx art above a two-column grid of 18 epx instrument icons when the row touches several charts; else the row's 36 epx instrument icon, Lead when it names none), bold title, sentence with the web's bold values (scores, ranks, instrument, song, "Full Combo", "gold stars", "x to y stars"; fallback wording never bold), a colour-coded flag pill (web `FLAG_COLORS`, white SemiBold label, 2 epx 18%-white border; under a contrast theme an outlined ButtonFace/ButtonText system pill) + time, and on the trailing edge the unread dot beside the chevron. "New"/"Older" headers use `FSTSectionHeaderBrush` (white; WindowText under a contrast theme). Media is decorative (Raw); the row's `ListViewItem` carries the Narrator name "Unread. Title. Message Flag. Time" and the row ID (`ContainerContentChanging`), so Narrator reads one item (not an item plus a nested group) and the flag never relies on colour. A tapped row without a destination drops "Unread." at once. The two lists don't scroll or virtualize themselves inside the flyout's scroller (rows used to vanish and reappear when scrolling back up); this is a deliberate deviation from winui-design's "`ScrollViewer` wrapped around a `ListView`" rule, bounded by the 50-row read limit.

- Row activation marks it seen; a song destination opens Song Detail (with chart) on the Songs stack; a rank destination saves `LeaderboardRankBy` and shows Leaderboards (web `/leaderboards?rankBy=`). Closing the flyout marks every loaded row seen.
- While loading, empty or not generated the flyout has nothing focusable, so WinUI focuses its `Popup`; `OnOpened` names that popup "Notifications" (UIA otherwise reports an unnamed "Popup" window, and `Flyout`'s own name only reaches the presenter).
- Never sends selected-profile headers (the gate rejects them).

## IDs and evidence

`fst.shell.notifications` (bell; hidden without a selected profile), `fst.notifications.sheet` (the flyout's heading), `.row.<guid>` (the row's `ListViewItem`), `.empty` (empty title), `.failed` (error text), `.retry`, `.loading` (ring), `.no-player` (text; unreachable while the bell is hidden), `.list` (scroller). Panels have no UIA peer, so state IDs sit on text elements. Screenshot: `windows/reports/screenshots/notifications-medium.png` (fixture `fixture-player-1` via `FST_DEBUG_PROFILE`).

## Validation (issue #229, 2026-10-04)

Every reachable contract state runs in `python tools/windows/notifications_journey.py [--only NAME] [--sizes compact,medium,wide] [--shots DIR]`. `tools/windows/notifications_fixture.py` serves per-player feeds (`fixture-player-1` rich, `fixture-feed-empty`, `fixture-feed-new` not generated, `fixture-feed-error` 503) and switches them between phases through `GET /__notifications__/mode?feed=…`, which also returns the read count. The accessibility pages are in `journeys/a11y-notifications.json`. How each state shows on Windows:

| State | Windows evidence |
|---|---|
| no-profile | the bell is hidden and the app sends no notifications read (fixture read count 0). `.no-player` is unreachable while the bell is hidden |
| empty-generated / empty-not-generated | `.empty` "No notifications available" with the web body; focus rests on the popup, named "Notifications" |
| loaded / unread-section | "New" heading (level 3), then rows named "Unread. Title. Message Flag. Time"; the bell reads "Notifications, N unread" |
| older-section | after Esc (which marks every row seen) and reopening, rows sit under "Older" without "Unread." and the bell reads "Notifications" |
| tap-navigate-song | a song row closes the flyout and opens Song Detail on that song and chart |
| tap-navigate-rankings | a rank row closes the flyout and opens Leaderboards with the matching Rank By |
| tap-no-destination, failed + retry, loading | the flyout stays open and the row drops "Unread."; 503 shows `.failed` and Retry, which reloads the rows; `.loading` ring |

Per configuration (fixture runs use `notifications_journey` and `a11y_matrix --scan`; live runs use the public service with SFentonX):

| Configuration | Findings |
|---|---|
| Compact (500 epx), snap-left | flyout fills the width under the bell; the journey's 8 contract scenarios pass; 0 Axe errors |
| Medium, wide, maximized | the flyout keeps a 380 epx width under the bell; all 10 scenarios pass at medium and the 8 contract ones at compact and wide; 0 Axe errors |
| Light / dark system theme | the app keeps its dark brand surface ([design/windows.md](../../design/windows.md)); 0 Axe errors |
| Desert, Night sky | fixed: flag pills kept their web colours and white text, and the "New"/"Older" headers stayed white. Pills are now outlined ButtonFace/ButtonText and the headers use WindowText; 0 Axe errors |
| Text 200% | titles and sentences wrap and rows grow; the last row is reachable by scrolling (`notifications-loaded-end`); 0 Axe errors at compact and medium |
| Display 100% / 150% | layout identical in epx; 0 Axe errors |
| Keyboard | Enter on the bell opens the flyout with focus on the first row (visible focus rectangle), arrows move between rows, Enter opens Song Detail, and Esc closes it and returns focus to the bell. Each list is one Tab stop, so with only unread rows Tab stays on the list; Retry is the only stop when the read fails (`kb-notifications-rows`, `kb-notifications-esc` at C/M/W) |

Narrator: the heading "Notifications" (level 2), the "New"/"Older" headings (level 3), then one item per row. Fixed: each row read as an unnamed list item followed by a nested group, and the row IDs were missing from UIA, so the name and ID now sit on the `ListViewItem`. The empty-state popup also used to read "Popup", and the state IDs sat on panels, which have no UIA peer.

Deliberate deviations from the winui-design/code-review skills: the dark-only theme; the `ScrollViewer` around the two non-scrolling `ListView`s (see Behavior); English literals (no `.resw` yet); a fixed 380 epx flyout width and raw icon sizes (web `NotificationRow` parity).

## Open

Band feeds, multi-event coalescing copy and flag groups (Android lacks them too; Apple ports them, issue #76); scroll-visibility seen marking.
