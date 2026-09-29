# Item Shop — iPad notes

> **What:** iPad layout decisions for the Shop route. **Read when:** the iPadOS phase or changing the Shop grid. Behavior: [spec.md](spec.md).

- Regular width: lazy full-bleed square-art grid with readable title scrims and red/gold accents, plus a persistent grid/list toggle (web tablet 820×1180 comparable). Cards are the web `ShopCard` (batch 6.9, Lane A3): art square only, 16pt scrim text, Leaving pill top-right, the whole card opens the official shop; the former "View Song Details" row under each card moved to the card's context menu (pushed through the root navigator). Switching List ↔ Grid gives the content a new identity, so the old layout fades out and the new one staggers in (web `toggleView`, batch 6.10).
- At accessibility text sizes the grid reflows to a list (a clipped grid artist label prompted this).
- The web's wide-sidebar Shop entry is not ported.
