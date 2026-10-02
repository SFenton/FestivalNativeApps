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

- Rows follow the web `NotificationRow` (operator batch 6.34/7.20, issue #76): a 64 epx leading media rail (`NotificationPresentation.MediaKind`: 54 epx album art via `SongArt`; 44 epx art above a two-column grid of 18 epx instrument icons when the row touches several charts; else the row's 36 epx instrument icon, Lead when it names none), bold title, sentence with the web's bold values (scores, ranks, instrument, song, "Full Combo", "gold stars", "x to y stars"; fallback wording never bold), a colour-coded flag pill (web `FLAG_COLORS`, white SemiBold label, 2 epx 18%-white border) + time, and on the trailing edge the unread dot beside the chevron. "New"/"Older" headers are white. Media is decorative (Raw); the row's Narrator name is "Unread. Title. Message Flag. Time" so the flag never relies on colour. The two lists don't scroll or virtualize themselves inside the flyout's scroller (rows used to vanish and reappear when scrolling back up).

- Row activation marks it seen; a song destination opens Song Detail (with chart) on the Songs stack; a rank destination saves `LeaderboardRankBy` and shows Leaderboards (web `/leaderboards?rankBy=`). Closing the flyout marks every loaded row seen.
- Never sends selected-profile headers (the gate rejects them).

## IDs and evidence

`fst.shell.notifications`, `fst.notifications.sheet`, `.row.<guid>`, `.empty`, `.failed`, `.retry`, `.no-player`, `.list`. Screenshot: `windows/reports/screenshots/notifications-medium.png` (fixture `fixture-player-1` via `FST_DEBUG_PROFILE`).

## Open

Band feeds, multi-event coalescing copy and flag groups (Android lacks them too; Apple ports them, issue #76); scroll-visibility seen marking.
