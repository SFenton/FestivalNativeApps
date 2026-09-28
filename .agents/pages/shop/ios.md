# Item Shop — iPhone notes

> **What:** iPhone implementation and decisions for the Shop route. **Read when:** changing Shop on iPhone (Lane S). Behavior: [spec.md](spec.md); offers/badges: [shop-offers/ios.md](../../controls/shop-offers/ios.md).

- `ShopScreen` is pushed within the Songs tab from a top toolbar action (three system tabs kept); Wave 1 moves the entry to the leading drawer ([PROGRESS.md](../../../PROGRESS.md)).
- Compact rows: original art, title, badge, official bag action; separate in-app Detail action when the catalogue matches. Red/gold borders for Leaving/New.
- Hide Shop in Settings removes the action and returns an open Shop route to Songs with a notice.
- Explicit empty card vs scalable unavailable/Retry for HTTP errors.
- Structural comparison against web phone captures (390×844) only; not pixel parity.
- Warm "publication unverified" Shop rows after connection loss predate online-only; do not extend. The strong recent-art cache tier stays ([architecture](../../platforms/apple/architecture.md)).
- Open: full focus order, landscape, rapid-gesture races on device, Shop filters/WebSocket.
