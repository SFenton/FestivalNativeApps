# App navigation (`fst.nav.*`) — spec

> **What:** platform-neutral web tab/shell rules and the cross-cutting shell controls. **Read when:** changing tabs, sidebars, drawers, deep links or shell chrome on any platform. Platform notes: [ios.md](ios.md) · [ipados.md](ipados.md) · [windows.md](windows.md). Per-platform chrome: [design/](../../design/README.md).

Source: `FortniteFestivalWeb/src/components/shell/mobile/BottomNav.tsx:45-100`, `src/hooks/ui/useTabNavigation.ts:12-35,151-179`. Audit refs: `BottomNav.tsx:41-100`, `MobileHeader.tsx:53-131`, `App.tsx:1011-1107`; header/sidebar profile actions `FortniteFestivalWeb/src/components/shell/HeaderActions.tsx:59-105`, `FortniteFestivalWeb/src/components/shell/desktop/PinnedSidebar.tsx:85-113`.

## Tab rules (web)

| Selection | Tabs |
|---|---|
| None | Songs, Leaderboards (aggregate), Settings |
| Player or band | + Suggestions, Statistics |
| Player | Compete may substitute; wider player layouts show Rivals separately |

- Re-tapping the current tab returns to its root; returning to another tab restores its prior nested route (except Statistics).
- A player page reached from search is not itself a tab. The wide-sidebar selected name links to Statistics.

## Native rules (all platforms)

- System navigation owns chrome and safe areas; keep accessible tab names, selected state, keyboard focus and per-tab path history.
- Never port the web's Duo pixel detector or guess fold/camera positions.
- A publication change keeps every route where it is and refreshes it in place, like the web `PublicationBoundary` (issue #304): fade the page out, show the spinner, fade the rebuilt page in (instant swap under Reduce Motion). Never pop to a root or show a "returned to …" notice for it. Routes that carry a song re-resolve it by ID against the new catalogue; a song that left shows a not-found state on that page. An identity switch must still not leave routes pointing at stale data.
- Pick up new publications without user action: Apple opens the anonymous `/api/ws` socket the web uses ([service safety](../../platforms/service-safety.md)).
- The `fst.nav.*` family reserves each semantic section (the source scanner requires every literal ID family to be registered).

## Cross-cutting shell controls (no own route)

Global search, notices, FAB actions, quick-link rail/sheet, filters, confirmation/draft dismissal, reduced motion, high contrast and screen-reader focus in all layouts (`App.tsx:1405-1474`, `pages/Page.tsx:330-353`, `components/modals/Modal.tsx`, `components/firstRun/FirstRunCarousel.tsx`).

## States

`songs`, `leaderboards`, `settings`, `player`, `band`, `reselect` (see `contracts/product.json`). Pending everywhere: guarded profile tabs, reselect, deep links, nested-route profile actions, orientation matrix, reading order.
