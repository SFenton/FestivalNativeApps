# Notifications — Android notes

> **What:** the Android top-bar bell, sheet, feed read and seen state. **Read when:** changing notifications on Android. Behavior: [spec.md](spec.md); references: [ios.md](ios.md), [windows.md](windows.md). Endpoint safety: [service-safety](../../platforms/service-safety.md).

## Implementation

| Piece | Where |
|---|---|
| Read | `data/notifications/FestivalApiNotifications.kt`: `FestivalApi.playerNotifications(accountId, limit)` → pinned keyless `GET /api/player/{id}/notifications?limit=` through the `ServiceEndpoint.Feature` seam (pure read per `FSTService/Api/ImprovementNotificationEndpoints.cs:10-31`; verified by the iPhone and Windows lanes) |
| Wire + rules | `core/notifications/Notifications.kt`: envelope/rows, `validate` (unique safe GUIDs, kinds, song IDs), `isGenerated`, `NotificationRouting` (web destination + ranking-metric tables, coalesced events), `NotificationText` (player single-event copy, `Song · Instrument` / `{Rank} Improved` titles, flags, en-US numbers, `#1,234` ranks, shop-song copy, relative time) |
| Seen | `core/notifications/NotificationSeenStore.kt`: settings DataStore key `fst.notifications.seen.v1` (registered `Kept`), per-account GUID lists pruned to the current feed, ≤400 per account, ≤20 accounts |
| Model | `presentation/notifications/NotificationsViewModel.kt`: NoPlayer/Loading/Failed/Empty(generated)/Loaded(New, Older), unread badge (99+), refresh on player change and each open (no polling), a failed refresh keeps the last feed |
| UI | `ui/notifications/NotificationsUi.kt`: `NotificationsBell` (M3 `BadgedBox`, gold badge) in the shell's `ShellActions.notifications` slot before the avatar; `NotificationsSheet` (M3 modal bottom sheet, width-capped on large windows) |

## Behavior

- Tapping a row marks it seen; a row with a destination also closes the sheet and pushes Song Detail (`SongDetailRoute`) or, for rank events, `FullRankingsRoute(instrument, rankBy)` (Leaderboards hub without an instrument). Closing the sheet marks every loaded row seen.
- No-player state offers Select Player Profile (opens the profile sheet). Never sends selected-profile headers (the gate rejects them; the UI journey asserts it).
- Debug: `FST_DEBUG_SHEET=notifications` opens the sheet at launch.

## IDs and evidence

`fst.shell.notifications` (label "Notifications, N unread"), `fst.notifications.sheet`, `.list`, `.row.<guid>`, `.empty`, `.failed`, `.loading`, `.no-player`. Tests: `notifications/NotificationsTest.kt`, `settings/SettingsUiTest.kt`. Screenshot: `android/reports/screenshots/notifications-phone.png` (mock `fixture-player-1`).

## Open

- Band feeds, multi-event coalescing copy and flag groups (as on iPhone/Windows); scroll-visibility seen marking.
- `service-safety.md`'s endpoint table has no notifications row yet (TODO(orchestrator)).
