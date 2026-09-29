# Notifications — iPhone notes

> **What:** iPhone implementation state and decisions for the notifications bell and sheet. **Read when:** changing this control on iPhone. Behavior: [spec.md](spec.md). Endpoint safety: [service-safety](../../platforms/service-safety.md).

Source: `FortniteFestivalWeb/src/components/notifications/MobileNotificationsModal.tsx`. Service: `FSTService/Api/ImprovementNotificationEndpoints.cs:10-31` (`/api/player/{accountId}/notifications`) — pure, keyless `GET` (single read-only `SELECT`, confirmed by reading `ImprovementNotificationService.GetPlayerNotifications`, `FSTService/Persistence/ImprovementNotificationService.cs:441-553`); never writes.

- Implemented: un-hid and wired the previously-reserved bell in `App/Shell/RootChrome.swift` (`NotificationsButton`), now showing an unread-count gold dot and opening `NotificationsSheet` (`Features/Notifications/NotificationsSheet.swift`) as a `festivalSheet(.large)`. `festivalRootChrome`'s `showsNotifications` default flipped from `false` to `true` (its only call site, `FestivalRootView.tabStack`, was unchanged). The sheet owns its own `NavigationStack` and reuses `AppRouteDestination` directly so rows can push to Song Detail or Full Rankings without needing the presenting tab's own path binding.
- `NotificationsCenter` (`App/FestivalSession+Notifications.swift`) is a per-session `@Observable` store reached via `session.notificationsCenter`, using the same weakly-keyed-registry pattern as `FestivalSession+Artwork.swift`'s `backgroundCoordinator` — added without a new stored property on `FestivalSession.swift` (Lane P's file). Seen-state (`NotificationSeenStore`) is a small `UserDefaults`-backed, per-accountId GUID list, independently testable.
- `FestivalCore` additions: `PublicEndpoint.playerHistory`/`.playerNotifications` cases (`FestivalAPI.swift`; both opt out of the snapshot cache like `.player`, and `.playerHistory` was added to the HTTP-202 allowlist alongside `.player`), plus new files `PlayerHistory.swift`, `PlayerNotification.swift`, `FestivalAPI+History.swift`, `FestivalAPI+Notifications.swift`.
- Simplified vs. web this pass — see `spec.md`'s "Native client contract": player-only feed (no bands), a finite ported subset of `notificationText.ts`'s copy templates instead of the full formatter, tap/dismiss-based seen state instead of scroll-visibility tracking, and the badge only refreshes on profile-selection change or sheet close (no live WebSocket push).
- IDs: `fst.shell.notifications` (bell, under the existing `fst.shell.*` → app-navigation family), `fst.notifications.row.<guid>`, `fst.notifications.empty`.
- Tests: `PlayerNotificationTests.swift` (Core) covers ranking-metric mapping, destination resolution and text formatting including the unknown-kind fallback. `NotificationSeenStoreTests.swift` (`FestivalUITests`) covers unread derivation, per-account isolation and idempotent marking against an isolated `UserDefaults` suite. `PlayerHistoryNotificationsRenderTests.swift` hosts the real sheet against a keyless fixture feed and writes a PNG when `FST_HISTORY_RENDER_OUT` is set.

## Operator batch 7 (Lane A3)

- Rows fade only during the first reveal (`FadeStagger` settle): List recycling while scrolling back up no longer re-fades them.
- "New" / "Older" headers are white (`FestivalText.primary`, no uppercase).
- Web trailing column: 20pt wide, chevron centred vertically (white 72%), 9pt yellow `#FACC15` unread dot with a 2pt ring, centred 24pt above the chevron.
- Close is the shared native `FestivalSheetCloseItem` (`fst.notifications.close`).
