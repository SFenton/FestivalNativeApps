# App navigation — iPhone notes

> **What:** the iPhone shell as built and planned. **Read when:** changing the iPhone tab shell or toolbar profile action (Lane A owns `App/Shell`, orchestrator owns `AppRoute`). Rules: [spec.md](spec.md); chrome: [design/apple/iphone.md](../../design/apple/iphone.md).

- `TabView` (Liquid Glass on iOS 26+, classic below) with three sections even after a player is selected; Suggestions/Statistics/Compete/Rivals are not added yet (web fixture captures visibly add them). `AppRoute` already models all 24 web routes; placeholder screens exist.
- Profile action is reachable from Songs, Settings and the Leaderboards root and opens the selection sheet without changing the active section ([profile-selection/ios.md](../profile-selection/ios.md)).
- A verified generation change currently **clears** retained `Song`-valued routes with a persistent visible explanation; an identity switch also clears them. TODO: carry song IDs and re-resolve against the new catalogue.
- Wave 1 (Lane A): conditional tabs mirroring `BottomNav`, profile button top-right on every root, leading hamburger drawer ([PROGRESS.md](../../../PROGRESS.md)).
