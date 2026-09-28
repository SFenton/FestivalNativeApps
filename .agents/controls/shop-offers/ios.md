# Shop offers — iPhone notes

> **What:** Apple implementation choices and tests for Shop offers and their Songs/Detail effects. **Read when:** changing Shop badges, borders or links on iPhone (Lane S). Spec: [spec.md](spec.md).

- Songs rows add small **accessible status icons** to the web's border-only red/gold state, so offer state is not conveyed by border colour alone.
- iPhone always uses compact Shop rows; forced list at accessibility text sizes.
- Cancellation guard runs before generic publication-cache mutation **and** inside the cache actor: `detailShopLoadsAfterCancelledSongsRequestWithoutStalePromotion`, `canceledPublicCacheWritesNeverPromoteOldResponses`.
- Tests: `ShopCatalogTests` (link validation, New/Leaving/hidden precedence, order, pin/304, malformed/oversized rejection); device `testPublicShopOffersAndSongDetailNavigation`, `testPublicShopEmptyAndErrorStayDistinct`, `testPublicShopSettingsHideAndHighlightPropagation`, `testPublicShopMembershipDecoratesSongsAndDetail`, `testShopFeedFailureAndEmptyStaySeparateFromSongs`; `shop-error` vs `shop-empty` [scenarios](../../testing/fixtures.md).
- The Songs "Retry Item Shop status" button has the only scoped audit exception ([accessibility](../../testing/apple/accessibility.md)).
- Open: rapid device gestures, Shop WebSocket, Shop filtering beyond two toggles, profile-dependent sorts, full Detail audit.
