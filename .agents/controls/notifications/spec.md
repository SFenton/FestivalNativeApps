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
- Row text ports the web's player-scoped `formatNotificationPresentation` (`notificationText.ts` with `en.json` copy): coalesced `payload.coalescedEvents` (score result events derived from top-level FC/gold-star payload fields, redundant star events dropped, priority order), the `Song · Instrument`, `{Rank} Improved`, `Rank Updates · {scope}`, `{scope} · Improvements` and bare song titles, sentence vs. paragraph joining, the emphasis terms (bold scores, ranks, instrument, song, "Full Combo", "gold stars", star/difficulty changes; never the fallback words), and the flag kinds with their `notifications.flags.*` labels plus per-instrument flag groups for multi-chart rows. An unrecognized `eventKind` reads "New improvement detected." with an "Improvement" flag. Apple (issue #76) and Android (`NotificationTextEngine.kt`, issue #180) port all of this. Windows ports single-event copy with the web's bold values and one `FLAG_COLORS` pill per row, without multi-event coalescing copy or flag groups. Event payload fields decode leniently (the web's `numberValue`/`booleanValue`/`stringValue`), so a malformed value drops that value rather than the feed. An unresolved song reads "this song" and never shows the raw song ID. Band/combo copy and the media-cycle animation are **not** ported.
- Row media follows the web `NotificationMediaRail`: album art (catalogue art, else the shop payload's); art above a two-column instrument icon grid when the row touched several charts (`coalescedInstruments` plus event instruments, canonical instrument order); else the row's instrument icon (Lead when none). Artwork is decorative. Flag chips use the web `FLAG_COLORS` fills with white text; native screen-reader labels append the flag names so meaning never depends on colour alone.
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

No profile; loading; failed + retry; both empty variants; all-read vs. some-unread; song destination vs. rankings destination vs. no destination; unknown `eventKind` fallback; badge count updates after seeing; single vs. coalesced vs. multi-chart vs. aggregate vs. shop rows (title, bold runs, flags, flag groups, media rail).
