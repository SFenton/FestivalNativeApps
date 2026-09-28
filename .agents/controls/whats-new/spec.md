# What's New changelog (`fst.whats-new.*`) — spec

> **What:** platform-neutral behavior of the launch "What's New" changelog card: content, show-once gate, ordering after first-run carousels, dismissal persistence and replay. **Read when:** changing the changelog, its gate or its Settings replay on any platform. Platform notes: [ios.md](ios.md).

Source: `FortniteFestivalWeb/src/changelog.ts`, `src/changelogHash.ts`, `src/components/modals/ChangelogModal.tsx:20-99`, `src/App.tsx:284,553-571,1458-1472`.

## Web behavior

- Content is a list of entries, each a list of `{title, items[]}` sections. Section titles are stored upper case (`ITEM SHOP`) and the card upper-cases them in CSS. The card title is `What's New · <app version>`; the footer has one full-width **Dismiss** and the header a Close (✕); tapping the overlay also dismisses.
- **Gate:** `localStorage['fst:changelog']` holds `{version, hash}`. The card shows when nothing is stored, the value does not parse, or `hash !== changelogHash()` — content, not app version, drives it. `changelogHash` is the precomputed `calculateChangelogHash(changelog)`: a 32-bit `((h << 5) - h) + charCode` over the UTF-16 units of `JSON.stringify(entries)`, printed base 36.
- **Ordering:** `showChangelog = hasNewChangelog && !dismissed && !activeCarouselKey` — a first-run carousel always wins; the card appears after it closes (first launch: Songs carousel, then What's New; `ios/changelog-dismiss.mp4` in the PWA reference).
- **Dismiss** writes `{version: APP_VERSION, hash}` and hides the card for this session. The web has no replay entry point.

## Client contract (all platforms)

- Ship the web entries byte-identical and verify the web hash in a unit test, so natives show the card exactly when the web would.
- Display section titles in Title Case (native deviation from the CSS upper-casing). Never advertise the deprecated Manual: drop any section or bullet that names it.
- Share the first-run "one sheet at a time" slot: never present over a carousel and never let a carousel present over the card.
- Persist dismissal as a bounded, validated `{version, hash}` record; corrupt data means "show again", never a crash.
- Natives add a Settings → Version → **What's New · Show** replay (the web has none); replay never changes the gate except to record dismissal.
- Debug builds must default to *not* auto-presenting, so screenshot/UI automation is never blocked by an unexpected launch sheet.

## States

| State | Acceptance |
|---|---|
| hidden-seen | Stored hash equals the current hash: nothing presents |
| waiting-for-first-run | Unseen, but a first-run carousel holds the slot: presents after it closes |
| presented | Title with version, Title Case sections, bullets, Dismiss + Close |
| dismissed | Dismiss/Close/swipe persists `{version, hash}`; a relaunch does not present |
| replay | Settings row presents the same card on demand |
