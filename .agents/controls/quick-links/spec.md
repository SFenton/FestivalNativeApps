# Quick Links (`fst.quick-links.*`) — spec

> **What:** platform-neutral behavior of per-page "Quick Links" (jump-to-section navigation): per-page items, visibility, active-section tracking, presentation by width, accessibility and related settings. **Read when:** adding section navigation to any page on any platform. Platform notes: [ios.md](ios.md).

Source: `FortniteFestivalWeb/src/hooks/ui/usePageQuickLinks.ts:18-503`, `src/components/page/PageQuickLinks.tsx:39-189`, `src/contexts/PageQuickLinksContext.tsx:1-61`, `src/pages/Page.tsx:252-357`, `src/App.tsx:287-340,930-961,1122-1401`, `packages/theme/src/breakpoints.ts:2-17`.

## Model

- A page supplies an ordered list of items `{id, label, landmarkLabel, icon?, depth?}` plus a scroll container; each item's anchor element registers itself (`registerSectionRef`) or, for virtualized lists, is located by `getItemTop` (Songs only).
- A page registers `{title, open}` with a shell-wide context so the shell FAB can open the page's list without knowing its contents.
- Test IDs (web): `${prefix}-quick-link-${id lowercased, non-alphanumerics → '-'}`, `${prefix}-quick-links-rail`, `${prefix}-quick-links-modal-list`. Native: `fst.quick-links.open`, `fst.quick-links.item.<id>`.

## Presentation by width

| Width | Web presentation | Entry point |
|---|---|---|
| ≥1440 px, not mobile chrome | Persistent right **rail** (240 px) in a shell portal, fades in after the page's stagger (`desktopRailRevealDelayMs`); selecting scrolls without closing | Always visible |
| 769–1439 px | Centered **modal** (420×520, ≤70 vh) | "Quick Links" ActionPill (IoCompass) in the page header, on Songs, Player/Statistics, Compete and Rivals only |
| ≤768 px or iOS/Android/PWA | Bottom-sheet **modal** | Mobile FAB: direct action on most pages, merged into an action group on History, Shop and secondary Leaderboards routes |

Selecting in a modal closes it, then scrolls. Song Detail, Rivalry and Rival Detail offer quick links only on mobile (`showDesktopRail: false`).

## Active-section tracking

1. **Natural:** the last item (in list order) whose top is ≤ `scrollTop + offset + 1` is active; items with unknown tops are skipped; with none past the line, the first item is active. Offset 32 px by default (16 px for the Songs virtualizer). No page overrides it.
2. **Jump (compact):** the target becomes active immediately and stays active while the smooth scroll runs.
3. **Arrival:** once the target is within 8 px of its destination (2 px on Player), or visible with its top in the reachable band `[-96, offset + 96]`, a settle timer (120 ms; 80 ms on Player) marks the jump **owned**.
4. **Owned:** the target stays active while (a) it is visible and the page has not moved more than the threshold from the landing position, or (b) its top stays in the reachable band. If the target could not reach the top (it is near the end of the content), it stays active **while visible**. Otherwise ownership releases to the natural section.
5. On the wide rail the previously active item holds during the scroll and hands off on arrival, rather than switching immediately.

## Visibility rules

- Web shows the entry point when items ≥ 1, but most pages require ≥ 2 and a loaded page (`ContentIn`); see the table. **Native rule: ≥ 2 sections**, because a single-item jump list does nothing.
- The modal closes itself if the items become empty or the rail takes over.

## Per-page items

| Page (`testIdPrefix`) | Title | Items in order (id → label; icon) | Shown when |
|---|---|---|---|
| Songs (`songs`) | "{Sort} Quick Links" | One bucket per sort key, `${sortMode}:${token}`, in first-seen order of the sorted rows: letters `a`–`z`/`#` (Title/Artist), decades `1990` → "1990s" (Year), `lt2`…`gte5` (Duration), `leaving-tomorrow`/`in-shop`/`not-in-shop` (Shop), plus score, FC, percentage, percentile, stars, season, intensity, difficulty, max-distance and max-score-diff buckets (`songQuickLinks.ts:130-409`) | ≥ 2 buckets and loaded (`SongsPage.tsx:851,1073`) |
| Song Detail (`song-detail`) | "Quick Links" | `intensity` "Intensity"; `score-history` "Score History" (player with history); promoted `band-<type>` (band profile); `instrument-<key>` per Settings-visible instrument the song supports (instrument icon); remaining `band-<type>` Duos/Trios/Quads (people icon) | Mobile only; loaded; ≥ 2 (`SongDetailPage.tsx:528-602`) |
| Player / Statistics (`player`) | "Quick Links" | `global` "Global Statistics"; `instrument:<key>` per visible instrument; `top-songs` "Top Songs"; `bands` "Bands" (when stats exist) | ≥ 1 (`PlayerContent.tsx:542-748`) |
| Band (`band`) | "Quick Links" | `members`, `summary`, `statistics`, `rank-history` "Rank History", `songs` | Loaded, no error, ≥ 2 (`BandPage.tsx:385-441`) |
| Compete (`compete`) | "Quick Links" | `leaderboards` "Leaderboards" (trophy), `rivals` "Rivals" (people) | Loaded (`CompetePage.tsx:200-262`) |
| Rivals, Song tab (`rivals`) | "Quick Links" | `common` "Common Rivals" (≥ 2 instruments loaded); `combo` "{Combo} Rivals"; `<instrumentKey>` "{Instrument} Rivals" per visible instrument with rivals | Loaded, ≥ 2 (`RivalsPage.tsx:305-373`) |
| Rivals, Leaderboard tab (`rivals`) | "Quick Links" | `<instrumentKey>` "{Instrument} Rivals" per visible instrument with rivals | Same (`LeaderboardRivalsTab.tsx:90-183`) |
| Rivalry (`rivalry`) | "Quick Links" | One per song in the `?mode` category: `${songId}:${instrument}:${index}` → song title, landmark "{title} ({Instrument})" | Mobile only; loaded; ≥ 1 (`RivalryPage.tsx:147-183`) |
| Rival Detail (`rival-detail`) | "Quick Links" | `rival-category:<key>` per non-empty category: Closest Battles, Almost Passed, Slipping Away, Barely Winning, Pulling Forward, Dominating Them | Mobile only; loaded; ≥ 1 (`RivalDetailPage.tsx:136-168`) |
| Leaderboards (`leaderboards`) | "Leaderboards Quick Links" | `rank-history` "Rank History Graph" (tracked player); promoted `band:<type>`; `instrument:<key>` per visible instrument; remaining `band:<type>` | Loaded, not all errored, ≥ 2 (`LeaderboardsOverviewPage.tsx:317-367`) |
| Settings (`settings`) | "Quick Links" | `app-settings`, `diagnostics` (web only, when visible; native apps have no Diagnostics section, #374), `item-shop`, `show-instruments`, `show-metadata`, `version`, `service-info`, `first-run`, `licenses`, `refresh-profile-name` (profile selected), `export`, `reset` | ≥ 2 (`SettingsPage.tsx:398-463`) |

## Keyboard and accessibility

- Rail and modal render `<nav aria-label={title}>` with one button per item; `aria-label` = `landmarkLabel`; `aria-current="location"` on the active item; depth > 0 uses 14 px/500 labels in 44 px rows.
- The modal uses the shared `ModalShell` focus trap and Escape-to-close. No keyboard shortcut opens quick links.
- Native platforms must expose an equivalent: a labelled entry point whose value is the active section, a "current" marker in the list, and assistive-technology navigation between sections.

## Related settings

- **No setting toggles Quick Links.**
- `showButtonsInHeaderMobile` ("Show Buttons In Header (Mobile)", `SettingsContext.tsx:30,70`) mentions Quick Links in its description but gates only mobile header pills. Every quick-links header pill already requires non-mobile chrome, so today it never affects Quick Links.

## Known web gaps (do not port)

- On mobile, Rivalry quick links are unreachable: `Routes.rivalry()` always adds `?mode=`, and the FAB offers quick links only when `mode` is absent (`App.tsx:1367-1387`).
- The Rivals FAB's direct action opens quick links even when none are registered (a no-op).
- The Compete config stays registered in the error state, when its anchors are not rendered.
- The Leaderboards title and "Rank History Graph" use inline default strings; the i18n keys are missing.
