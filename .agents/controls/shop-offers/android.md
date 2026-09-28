# Shop offers — Android notes

> **What:** how Android validates Shop offers and applies badges/borders across Shop, Songs and Song Detail. **Read when:** touching `core/shop/`, `presentation/shop/ShopStore.kt` or Shop accents. Behavior: [spec.md](spec.md).

- `ShopResponse.validate` rejects count mismatches, duplicate (case-insensitive) or `/`-containing IDs, empty titles/artists and any URL that isn't `https://www.fortnite.com/item-shop/jam-tracks/<slug>` without credentials, port, query or fragment. Bodies over 4 MB are rejected.
- `ShopPresentationPolicy.highlight`: Leaving Tomorrow, then New; none when Shop is hidden, highlighting is disabled or there's no offer.
- `SongRelatedPublicationPolicy.matches(catalogue, shop, current)` gates Songs sort/filter/accents and Song Detail's badge/link: a feed from another observed publication pauses Shop choices with a notice and never decorates older rows.
- Songs rows: 2 dp red (Leaving) / gold (New) border plus a circular badge (clock / sparkle); the row announcement adds "Item Shop: …". Shop page and Detail use text badges.
- One process-wide `ShopStore` (AppContainer `shop`) shared by all three surfaces; online-only, in-process.
