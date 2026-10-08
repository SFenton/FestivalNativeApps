# Item Shop — iPad notes

> **What:** iPad layout decisions for the Shop route. **Read when:** the iPadOS phase or changing the Shop grid. Behavior: [spec.md](spec.md).

- Regular width: lazy full-bleed square-art grid with readable title scrims and red/gold accents, plus a persistent grid/list toggle (web tablet 820×1180 comparable). Cards are the web `ShopCard` (batch 6.9, Lane A3): art square only, 16pt scrim text, Leaving pill top-right, the whole card opens the official shop; the former "View Song Details" row under each card moved to the card's context menu (pushed through the root navigator). Switching List ↔ Grid gives the content a new identity, so the old layout fades out and the new one staggers in (web `toggleView`, batch 6.10).
- At accessibility text sizes the grid reflows to a list (a clipped grid artist label prompted this).
- Toolbar order: **Sort, Filter, List/Grid** (issue #379; HIG toolbars › "Group by function/frequency and consistently across platforms"). Sort opens the same Songs Sort sheet as a form sheet (HIG popovers › "Avoid popovers in compact views" applies to Slide Over and narrow splits, so iPad keeps the sheet like Songs); the grid and list both follow it ([ios.md](ios.md)).
- The Filter button (issue #19, [ios.md](ios.md)) sits before the grid/list toggle and filters the grid and list alike; the sheet is the system form sheet with the same switch rows. The no-match card replaces the grid.
- The Filter button (issue #19, [ios.md](ios.md)) sits before the grid/list toggle and filters the grid and list alike; the sheet is the system form sheet with the same switch rows. The centred filtered-empty state (no card, no Reset; #377) replaces the grid.
- The web's wide-sidebar Shop entry is not ported.
