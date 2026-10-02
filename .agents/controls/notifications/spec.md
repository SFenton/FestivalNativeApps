# Notifications (`fst.notifications.*`) — spec

> **What:** platform-neutral web behavior of the notifications bell/feed. **Read when:** changing the bell, unread badge or notification rows on any platform. Platform notes: [ios.md](ios.md). Endpoint safety: [service-safety](../../platforms/service-safety.md).

Source: `FortniteFestivalWeb/src/components/notifications/MobileNotificationsModal.tsx:86-214`, `notificationText.ts` (975 lines — full copy engine, not ported natively; see below), `notificationSeenState.ts`, `notificationDestination.ts`, `notificationRanking.ts`, `useProfileNotificationsFeed.tsx`. Wire types: `packages/core/src/api/serverTypes.ts:318-381`.

## Wire

- `GET /api/player/{accountId}/notifications?limit=` — pure, keyless read: a single `SELECT` over `player_improvement_events` (this account only) `UNION ALL service_notifications` (a global, account-independent shop feed), never a write (`FSTService/Api/ImprovementNotificationEndpoints.cs:10-31`, `FSTService/Persistence/ImprovementNotificationService.cs:441-553`). An unregistered/unknown account simply gets an empty envelope, unlike `/history`'s 404.
- Envelope: `{generatedAt, expiresAfterHours, sourceRunId?, sourceCompletedAt?, notificationsGenerated?, items: ImprovementNotificationDto[]}`. "Generated" (had a detection run) is distinct from "generated but currently empty" — the empty state's copy differs (`notifications.empty.generatedBody` vs `notGeneratedBody`).
- Each `ImprovementNotificationDto` carries `eventKind`, optional `songId`/`instrument`/`metric`/`oldRank`/`newRank`/`oldNumeric`/`newNumeric`, and an optional `payload` object (coalesced sub-events, old/new stars/FC, or — for `service_new_shop_song` — the song's own `songTitle`/`artist`/`albumArt` since that kind has no `accountId`).

## Destination mapping

- Song-scoped kinds (`service_new_shop_song`, `player_first_score`, `player_score_pb`, `player_song_rank_improved`, `player_stars_improved`, `player_gold_stars_achieved`, `player_fc_achieved`, `player_difficulty_bumped`) navigate to that song.
- Rank kinds map `eventKind` (preferred) or `metric` to a `RankingMetric` (`notificationRanking.ts`); with an instrument, that is a full-rankings destination, otherwise the leaderboards hub.
- Other kinds (aggregate total-score/FC-count improvements) have no tap destination — the row still displays, just without a chevron.

## Seen state

- Web: `notificationSeenState.ts` keys seen IDs per profile feed (`player:<accountId>` / `band:<bandId>`), prunes to the currently-loaded IDs plus a retention window, and marks a row seen once ≥90% visible in the scrolling list for a beat.
- The unread badge count is `current IDs − seen IDs`; a "New" section groups unread rows above "Older".

## Native client contract (all platforms)

- One player-scoped feed only this wave (no band notifications — the app has no band selection surface yet). Never send the selected-profile header; this is an ordinary keyless GET.
- Text formatting ports only the player-scoped `copy.primary` templates and `badges` from `en.json` verbatim (first score, PB, rank/stars/gold-stars/FC/difficulty, the five rank-improvement kinds, total-score/FC-count improvements, and the shop-song kind). The single flag pill uses the web `FLAG_COLORS` per flag kind, the sentence bolds the web's emphasized values, and rows touching several charts (`coalescedInstruments`) show art above an instrument grid (Android, Windows; issue #76). Band copy, multi-event coalescing/grouping, flag pills beyond a single badge, and the media-cycle animation are **not** ported — an unrecognized `eventKind` falls back to a generic "New improvement detected." sentence rather than crashing or showing raw keys.
- Seen state is simplified to one per-account list of seen GUIDs (no cross-feed staleness pruning, since the app tracks at most one selected player at a time) and is marked seen on row tap and on sheet dismissal, not by scroll-visibility.

## States

| State | Native acceptance |
|---|---|
| No profile selected | Explicit "choose a profile" message, no request |
| Loading | Spinner |
| Failed | Retry |
| Empty, feed generated | `notifications.empty.generatedBody` copy |
| Empty, feed never generated | `notifications.empty.notGeneratedBody` copy |
| Loaded, has unread | "New" section, gold unread dot, badge count on the bell |
| Row tap, has destination | Marks seen, dismisses the sheet and opens the page on the main app's current navigation stack (web `App.tsx` `handleNotificationOpen`); Back returns to the page under the sheet |
| Row tap, no destination | Marks seen; the sheet stays open, no navigation |

## Test matrix

No profile; loading; failed + retry; both empty variants; all-read vs. some-unread; song destination vs. rankings destination vs. no destination; unknown `eventKind` fallback; badge count updates after seeing.
