# Notifications — Windows notes

> **What:** the Windows title-bar bell, flyout, feed read and seen state. **Read when:** changing notifications on Windows. Behavior: [spec.md](spec.md). Endpoint safety: [service-safety](../../platforms/service-safety.md).

## Implementation

| Piece | Where |
|---|---|
| Read | `Data/NotificationsApi.cs`: `client.GetPlayerNotificationsAsync(accountId, limit)` → pinned keyless `GET /api/player/{id}/notifications?limit=` (the service classifies it publication-bound). Kept as an extension with a sync `Decode` |
| Wire + rules | `Data/NotificationModels.cs`: envelope/row records, `Validate` (unique safe GUIDs, kinds, song IDs), `IsGenerated`, `NotificationRouting` (destination + ranking metric, `notificationDestination.ts`/`notificationRanking.ts`), `NotificationMediaRules.SurfaceInstruments` (payload `coalescedInstruments` + coalesced events + the row's chart, canonical order), `NotificationText` (the web player copy engine: `payload.coalescedEvents` with lenient web value decoding, derived score FC/gold events, redundant star events dropped, priority order, titles `Song` / `Song · Instrument` / `{Rank} Improved` / `Rank Updates · {scope}` / `{scope} · Improvements`, sentence vs. per-chart paragraph clauses, flags plus per-instrument `NotificationFlagGroup`s for multi-chart rows, `Emphasize` web bold runs, en-US `toLocaleString` numbers, `#1,234` ranks, shop-song title/message with payload art fallback), `NotificationFlagKinds.Argb` (web `FLAG_COLORS`) |
| Row visuals | `Controls/NotificationRowVisuals.cs`: attached `Parts` (bold `Run`s in the message `TextBlock`), `IconFiles` (2-column 18 epx instrument grid, Raw), `Flags` (one wrapping pill line, or one line per chart: 20 epx Raw instrument icon plus its pills, 2 epx gaps, web `notifFlagGroup`) and `FlagBrush` |
| Seen | `Data/NotificationSeenStore.cs`: `notifications-seen.json`, per-account GUID lists pruned to the current feed, ≤400 per account, ≤20 accounts |
| Model | `ViewModels/NotificationsViewModel.cs`: states NoPlayer/Loading/Failed/Empty/Loaded, New/Older, unread badge (99+), refresh on launch, player change and each open (no polling), failed refresh keeps the last feed |
| UI | `Controls/NotificationsBell.xaml`: bell before the avatar in `TitleBar.RightHeader`, `InfoBadge` count inside the bell's 36×32 box (never negative margins: the button clips them), light-dismiss flyout |

## Behavior

- Rows follow the web `NotificationRow` (operator batch 6.34/7.20, issues #76, #272). Each row is a card. Its `ListViewItem` (`RowContainerStyle`) draws the web `surfaceSubtle` fill (`FSTNotificationRowSurfaceBrush`) with 8 epx between cards, so hover (web `surfaceElevated`), press and the focus rectangle follow the card. The default `ListViewItemPresenter` template ignores the item's `BorderBrush`, `BorderThickness` and `CornerRadius`. So each `ListView.Resources` overrides `ListViewItemCornerRadius` (10 epx). `RowTemplate`'s root `Border` draws the 1 epx `borderSubtle` stroke and the 10 epx padding, with a 4,2 epx margin matching the presenter's inset rounded fill. A 4 epx item margin leaves the web's 8 epx between cards (issue #272: the contrast-theme stroke never drew). Inside the card:
  - a 64 epx leading media rail (`NotificationPresentation.MediaKind`): 54 epx album art via `SongArt`; 44 epx art above a two-column grid of 18 epx instrument icons when the row touches several charts; otherwise the row's 36 epx instrument icon, Lead when it names none;
  - a one-line `MarqueeText` title (`FSTMarqueeTitleStyle`; ellipsis when motion is off);
  - the message with the web's bold values (scores, ranks, instrument, song, "Full Combo", "gold stars", "x to y stars"; fallback wording is never bold): one sentence, or for multi-chart, aggregate and multi-rank rows one clause per chart separated by a blank line (web `pre-line`);
  - colour-coded flag pills (one per flag kind; multi-chart rows group them per chart behind that chart's 20 epx instrument icon, like the web flag groups): web `FLAG_COLORS`, white SemiBold label, 4,2 epx padding, 8 epx radius and a 2 epx 18%-white border. Under a contrast theme it becomes an outlined ButtonFace/ButtonText system pill;
  - a 20 epx trailing column with the centred chevron. The 9 epx gold `#FACC15` unread dot (`FSTNotificationUnreadDotBrush`) sits 24 epx above the chevron's centre.

  The relative time isn't drawn; the web shows none, and Android and iOS only speak it. Under a contrast theme the card is Window with a WindowText stroke and a WindowText dot. Hover and press are Highlight, so the row's text (no explicit foreground) inherits HighlightText. The cards are flat opaque fills inside the flyout's own material ([surface-materials](../../patterns/surface-materials.md) R6). The chevron keeps the theme foreground (white, like Android) instead of the web's 72% white, so contrast-theme hover still recolours it.

  "New"/"Older" headers use `FSTSectionHeaderBrush` (white; WindowText under a contrast theme). Media, dot and chevron are decorative (Raw). The row's `ListViewItem` carries the row ID (`ContainerContentChanging`) and the Narrator name "Unread. Title. Message [Affected instruments: A, B.] Flags. Time" (flags read "A: Flag, Flag. B: Flag" on multi-chart rows, like the web group `aria-label`s; paragraph breaks read as spaces). Multi-chart rows name their charts like the web grid's `aria-label`. Narrator reads one item (not an item plus a nested group), and the flags never rely on colour. A tapped row without a destination drops "Unread." at once. The two lists don't scroll or virtualize themselves inside the flyout's scroller (rows used to vanish and reappear when scrolling back up). This deliberately deviates from winui-design's "`ScrollViewer` wrapped around a `ListView`" rule, bounded by the 50-row read limit.

- Row activation marks it seen; a song destination opens Song Detail (with chart) on the Songs stack; a rank destination saves `LeaderboardRankBy` and shows Leaderboards (web `/leaderboards?rankBy=`). Closing the flyout marks every loaded row seen.
- While loading, empty or not generated the flyout has nothing focusable, so WinUI focuses its `Popup`; `OnOpened` names that popup "Notifications" (UIA otherwise reports an unnamed "Popup" window, and `Flyout`'s own name only reaches the presenter).
- Never sends selected-profile headers (the gate rejects them).

## IDs and evidence

`fst.shell.notifications` (bell; hidden without a selected profile), `fst.notifications.sheet` (the flyout's heading), `.row.<guid>` (the row's `ListViewItem`), `.empty` (empty title), `.failed` (error text), `.retry`, `.loading` (ring), `.no-player` (text; unreachable while the bell is hidden), `.list` (scroller). Panels have no UIA peer, so state IDs sit on text elements. Screenshot: `windows/reports/screenshots/notifications-medium.png` (fixture `fixture-player-1` via `FST_DEBUG_PROFILE`).

## Validation (issue #229, 2026-10-04)

Every reachable contract state runs in `python tools/windows/notifications_journey.py [--only NAME] [--sizes compact,medium,wide] [--shots DIR]`. `tools/windows/notifications_fixture.py` serves per-player feeds (`fixture-player-1` rich, `fixture-feed-empty`, `fixture-feed-new` not generated, `fixture-feed-error` 503, `fixture-feed-media` media rail and flag kinds, issue #272) and switches them between phases through `GET /__notifications__/mode?feed=…`, which also returns the read count. The accessibility pages are in `journeys/a11y-notifications.json`. How each state shows on Windows:

| State | Windows evidence |
|---|---|
| no-profile | the bell is hidden and the app sends no notifications read (fixture read count 0). `.no-player` is unreachable while the bell is hidden |
| empty-generated / empty-not-generated | `.empty` "No notifications available" with the web body; focus rests on the popup, named "Notifications" |
| loaded / unread-section | "New" heading (level 3), then rows named "Unread. Title. Message Flags. Time"; the bell reads "Notifications, N unread" |
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
| Desert, Night sky | fixed: flag pills kept their web colours and white text, and the "New"/"Older" headers stayed white. Pills are now outlined ButtonFace/ButtonText and the headers use WindowText; 0 Axe errors. Issue #253 (Aquatic, Desert): the unread count drew a clipped text backplate inside the Highlight circle; the `InfoBadge` now opts out (`OnBadgeLayout`), so it reads HighlightText on Highlight |
| Text 200% | titles and sentences wrap and rows grow; the last row is reachable by scrolling (`notifications-loaded-end`); 0 Axe errors at compact and medium. Fixed: the unread count spilled out of the 16 epx badge and hid the bell, so the `InfoBadge` ignores text scaling (its count is a glanceable indicator; the bell's UIA name carries the number) |
| Display 100% / 150% | layout identical in epx; 0 Axe errors |
| Keyboard | Enter on the bell opens the flyout with focus on the first row (visible focus rectangle), arrows move between rows, Enter opens Song Detail, and Esc closes it and returns focus to the bell. Each list is one Tab stop, so with only unread rows Tab stays on the list; Retry is the only stop when the read fails (`kb-notifications-rows`, `kb-notifications-esc` at C/M/W) |

Narrator: the heading "Notifications" (level 2), the "New"/"Older" headings (level 3), then one item per row. Fixed: each row read as an unnamed list item followed by a nested group, and the row IDs were missing from UIA, so the name and ID now sit on the `ListViewItem`. The empty-state popup also used to read "Popup", and the state IDs sat on panels, which have no UIA peer.

Deliberate deviations from the winui-design/code-review skills: the dark-only theme; the `ScrollViewer` around the two non-scrolling `ListView`s (see Behavior); English literals (no `.resw` yet); a fixed 380 epx flyout width and raw icon sizes (web `NotificationRow` parity).

## Validation (issue #272, 2026-10-06)

Re-check of #76 against the web `NotificationRow` with the winui plugin. Media rail, bold values and colour-coded pills already matched. Fixed: rows were flat list items (no `surfaceSubtle` card, stroke or radius), and the gold unread dot sat beside the chevron instead of 24 epx above it. A visible relative time was shown that the web doesn't have. Multi-chart rows didn't name their charts to Narrator. Then, during this pass, the card stroke never drew, because `ListViewItemPresenter` ignores the item's border (see [windows.md](../../platforms/windows.md) Gotchas). `media-rows` (fixture `fixture-feed-media`) covers the grid row and five flag kinds; the live SFentonX feed has no multi-chart row.

| Configuration | Findings |
|---|---|
| Compact, medium, wide, maximized, snap-left | cards fill the flyout width; the grid row keeps art above its two-column grid; the journey's 11 scenarios pass at medium, and the 8 size-sensitive ones (including `media-rows`) also pass at compact and wide; 0 Axe errors on all 7 fixture pages at all 5 sizes |
| Light / dark system theme | dark brand surface unchanged; 0 Axe errors |
| Desert, Night sky | cards are Window with a WindowText stroke, the dot is WindowText, pills are outlined ButtonFace; hover/press are Highlight with HighlightText; 0 Axe errors |
| Text 200% | the title stays one marquee line, the sentence wraps and the card grows; the dot stays above the chevron; the last row scrolls into view; 0 Axe errors |
| Display 100% / 150% | identical epx geometry (stroke on the fill edge, 8 epx gaps); 0 Axe errors |
| Keyboard | unchanged: Enter opens with focus on the first card (focus rectangle around the card), arrows move, Enter activates, Esc returns to the bell (`kb-notifications-*` at C/M/W) |

Narrator: one item per card, named "Unread. Title. Message [Affected instruments: Lead, Bass, Drums.] Flags. Time". The time is spoken but not drawn, like Android and iOS. Deliberate deviations: the chevron uses the theme foreground (not the web's 72% white) so contrast-theme hover recolours it; the title/message/pill keep the Fluent type ramp (BodyStrong/Body/Caption) rather than web pixel sizes; the card radius and padding are web constants (10/10 epx), not `ControlCornerRadius` or the 4 epx grid: an agent decision recorded as an approved Windows variant in [surface-materials](../../patterns/surface-materials.md#agent-decision-windows-notification-row-cards-272) (the owner may override).

Visual regression (#272 review): the art, grid, bold runs, pill colours, card stroke/gap and unread dot are Raw or paint-only, so the row's UIA name can't catch their loss. `media-rows` (`notifications_journey.py` `media_paint`) asserts them at compact, medium and wide for all six rows: `assertpaint` probes the window pixels at epx offsets from each row (fill #162133, 1 epx #1E2A3A stroke at 4 epx, a non-card gap below, art in the rail, white instrument icons only under the grid row's art, each row's last flag colour (on the grid row, the Drums group icon and then its First Play pill), the gold dot 24 epx above the chevron), and `assertbold` reads each message's bold runs from its TextPattern. Each probe was checked to fail with its visual removed (stroke, gap, pill colour, dot offset, grid, art, bold). The matrix runs the same probes per configuration (`a11y-notifications.json` `paint-notifications-media*`, run with `--fixture tools/windows/notifications_fixture.py`): exact colours in light, dark and display 150%; the grid row's top-edge fill and bold runs plus the First Play row's rail, pill and dot at text 200% (the grid card is taller than the flyout there); and theme-relative probes in `hc-night-sky` and `hc-desert` (art and dot differ from the card's own fill, the pill's 2 epx `ButtonText` outline at L88, L110 behind the grid row's group icon), because contrast themes replace the web colours.

## Coalesced events (#324 review, 2026-10-07)

The design review found that multi-chart rows showed their grid but read only the top-level event: one sentence and one chip. `NotificationText` now ports the web player path (`notificationText.ts` at web 7401560e): every `payload.coalescedEvents` entry with its own values, derived FC/gold results, priority order, per-chart clauses and flag groups. The media fixture's grid row carries five coalesced events on three charts, and the Orbit personal best derives a Full Combo chip from its payload. `media-rows` checks the title, the full bold-run list, every flag group (Drums icon, then its pill colour) and the Narrator name; `NotificationsTests` `Coalesced_*` mirror the web unit tests and the fixture rows.

- At text 200% the five-event grid card is taller than the flyout, so `paint-notifications-media-text` probes only its top-edge fill (`T` offsets) plus its full bold runs, and runs the rail, pill and dot probes on the single-chart First Play row after `scrollinto`. Probes anchored to `M`/`B` of a card taller than its viewport land off screen.
- A WinUI `LineBreak` is one TextPattern character unit but `\r\n` in `GetText`: FstUia `BoldRuns` maps units to text offsets locally (`NextTextIndex`) and advances one unit per step. Re-moving from the document start per unit is quadratic.
- Live SFentonX (2026-10-06): coalesced rows are single-chart (a personal best plus song rank; a first play with its rank events; 4-event total-score aggregates). They read every event in one sentence with one chip per flag kind. There is still no live multi-chart row, so the grouped-flag layout is fixture-only evidence.
- `a11y_matrix` timeouts (`Operation timed out`, no driver log line) happen while attaching to a freshly launched app under desktop-lock contention; a rerun passes. They are not row failures.

## Open

Band feeds and the media-cycle animation (Apple and Android lack them too); scroll-visibility seen marking.
