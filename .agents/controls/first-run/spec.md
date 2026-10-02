# First-run experiences (`fst.firstRun.*`) — spec

> **What:** platform-neutral behavior for the onboarding slide carousels shown the first time a
> user visits a page, and their Settings "view again" replay. **Read when:** touching any page's
> onboarding, the seen-state store, or the Settings "First Run Guides" section, on any platform.
> Platform notes: [ios.md](ios.md).

Source: `FortniteFestivalWeb/src/firstRun/types.ts`, `contexts/FirstRunContext.tsx`,
`hooks/ui/{useFirstRun.ts,useRegisterFirstRun.ts}`, `components/firstRun/FirstRunCarousel.tsx`,
per-page `pages/<page>/firstRun/**`, `pages/settings/SettingsPage.tsx` (replay UI).

## Web behavior

- Each page registers an ordered list of slide definitions: `{id, version, title, description,
  contentKey?, gate?, render}`. `id` is a stable per-slide key; `version` is a **replay-contract**
  version bumped only when previously-dismissed users should see the slide again (not for
  demo/animation polish); `gate` is a predicate over runtime context deciding whether the slide
  is even eligible.
- Seen-state is one `{version, hash, seenAt}` record per slide id, persisted client-side. `hash`
  is a content hash of `contentKey ?? (title + description)`, so mobile/desktop copy variants can
  share one record via a common `contentKey`, and any other copy edit re-triggers the slide.
- A slide is **unseen** if it has no record, `slide.version > record.version`, or its current
  content hash differs from the recorded hash (`isSlideUnseen`).
- On a page visit, the carousel shows only the subset of that page's slides that are both
  gate-passing and unseen (`getUnseenSlides`) — **never** slides the user already dismissed, even
  if the page also gained a brand-new slide since. If one new slide is added to an
  already-dismissed page, only that new slide shows.
- Gate context (`FirstRunGateContext`): `hasPlayer`, `shopHighlightEnabled`,
  `experimentalRanksEnabled`, `ready` (false delays evaluation until dependent context
  stabilizes — nothing shows while `ready === false`), `alwaysShow` (bypasses seen-state but
  still respects gates — an internal escape hatch, not exposed as a user setting).
- Dismissing the carousel (close button, Skip after the last slide, or finishing) marks every
  *displayed* slide seen at once, not just the current one.
- Only one carousel may be visible at a time app-wide (`activeCarouselKey`); a second page whose
  slides also became eligible waits until the first is dismissed.
- Settings "First Run Guides" section: one row per registered page with a "Show" button. Opening
  it (`useFirstRunReplay.open`) resets that page's seen-state and shows **every** slide for the
  page (`getAllSlides`), ignoring both gates and seen-state — so replay never hides content behind
  a gate the user doesn't currently satisfy (e.g. no player selected) or behind already-seen
  state. Closing the replay marks all of them seen again. There is no "reset all" or per-page
  reset control in the Settings UI; `resetAll`/`resetPage` exist in `FirstRunContext` but are only
  used internally by the replay open action.

## Client contract (all platforms)

- Persist seen-state as one bounded, validated JSON blob (id → `{version, hash, seenAt}`).
  Corrupt/unparsable data must recover to an empty store rather than crash or block first-run
  forever; individual malformed records may be dropped without discarding the whole store.
- Compute unseen slides with the exact `isSlideUnseen` semantics above — order matters for the
  "only the new slide shows" behavior, and version comparisons are strictly `>`, not `!=`.
- Evaluate gates against the same four context fields as the web; `ready` must gate everything
  (nothing shows while facts the gates depend on could still be stale).
- Enforce "one carousel at a time" app-wide, not just per navigation stack — a hidden tab root and
  a pushed route for the same or a different page must not both present simultaneously.
- Settings replay must ignore both gates and seen-state (`getAllSlides`), matching the web
  exactly — a platform must not "improve" this by re-applying gates to replay.
- Native carousels are titled modals (issue #24): a short visible title naming the page the guide
  explains (the Settings row label, e.g. "Songs", "Score History"), announced first by the screen
  reader, on first run and replay alike. The web only labels its overlay (`aria-label` "Feature
  tour"). Verified 2026-10-02: Android's dialog header shows the page label (`paneTitle` "Feature
  tour: <page>") and Windows' `ContentDialog.Title` is the page label; iOS gained an inline
  navigation title.
- Navigation controls follow each platform's onboarding convention (issue #25), not the web's
  footer: every page has one prominent primary **Next** (**Done** on the last page); **Back**
  appears only after page one and is never shown disabled; an optional **Skip** stays easy to
  reach while pages remain; **Close** dismisses. Each control is a named button with at least the
  platform's minimum target (44×44 pt iOS, 48×48 dp Android, 40×40 epx touch target on
  Windows). Apple: Back is the leading navigation-bar chevron before the
  title, Next is a large prominent bottom button and Skip a quiet text button beneath it. Google
  (Material 3 / Setup Wizard footer): primary Next at the bottom end, secondary Skip at the
  bottom start, Back is the system Back or top app bar arrow. Microsoft (Fluent dialogs): the
  "do it" primary leftmost, the safe/dismiss action rightmost, Back as a secondary command.

## States

| State | Acceptance |
|---|---|
| No unseen slides for a page | No carousel; page renders normally |
| Unseen, gate-passing slides | Carousel with only those slides, in catalog order |
| A slide's gate fails | Excluded from both first-run and (unlike replay) not from replay |
| Page previously dismissed, one new slide added | Carousel shows only the new slide |
| Two pages become eligible near-simultaneously | Only one carousel shows; the other waits |
| Settings "Show" for a page | Carousel with every slide for that page, gates/seen-state ignored |
| Corrupt persisted seen-state | Recovers to empty (or partially valid) rather than blocking FRE |
