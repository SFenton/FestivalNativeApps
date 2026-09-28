# Notifications — Windows notes

> **What:** the Windows title-bar bell, flyout, feed read and seen state. **Read when:** changing notifications on Windows. Behavior: [spec.md](spec.md). Endpoint safety: [service-safety](../../platforms/service-safety.md).

## Implementation

| Piece | Where |
|---|---|
| Read | `Data/NotificationsApi.cs`: `client.GetPlayerNotificationsAsync(accountId, limit)` → pinned keyless `GET /api/player/{id}/notifications?limit=` (the service classifies it publication-bound). Kept as an extension with a sync `Decode` |
| Wire + rules | `Data/NotificationModels.cs`: envelope/row records, `Validate` (unique safe GUIDs, kinds, song IDs), `IsGenerated`, `NotificationRouting` (destination + ranking metric, `notificationDestination.ts`/`notificationRanking.ts`), `NotificationText` (player single-event copy, titles `Song · Instrument` / `{Rank} Improved`, web flag labels, en-US `toLocaleString` numbers, `#1,234` ranks, shop-song title/message) |
| Seen | `Data/NotificationSeenStore.cs`: `notifications-seen.json`, per-account GUID lists pruned to the current feed, ≤400 per account, ≤20 accounts |
| Model | `ViewModels/NotificationsViewModel.cs`: states NoPlayer/Loading/Failed/Empty/Loaded, New/Older, unread badge (99+), refresh on launch, player change and each open (no polling), failed refresh keeps the last feed |
| UI | `Controls/NotificationsBell.xaml`: bell before the avatar in `TitleBar.RightHeader`, `InfoBadge` count, light-dismiss flyout |

## Behavior

- Row activation marks it seen; a song destination opens Song Detail (with chart) on the Songs stack; a rank destination saves `LeaderboardRankBy` and shows Leaderboards (web `/leaderboards?rankBy=`). Closing the flyout marks every loaded row seen.
- Never sends selected-profile headers (the gate rejects them).

## IDs and evidence

`fst.shell.notifications`, `fst.notifications.sheet`, `.row.<guid>`, `.empty`, `.failed`, `.retry`, `.no-player`, `.list`. Screenshot: `windows/reports/screenshots/notifications-medium.png` (fixture `fixture-player-1` via `FST_DEBUG_PROFILE`).

## Open

Band feeds, multi-event coalescing copy and flag groups (as on iPhone); scroll-visibility seen marking.
