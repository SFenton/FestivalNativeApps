# Public Shop offers — Windows notes

> **What:** Windows Shop data, badges and publication rules across Shop, Songs and Song Detail. **Read when:** touching `ShopModels.cs`, `FestivalSession.Shop.cs` or Shop accents. Contract: [spec.md](spec.md).

- `ShopResponse.Validate` rejects count mismatches, duplicate (case-insensitive) or unsafe IDs, empty titles/artists and any link other than `https://www.fortnite.com/item-shop/jam-tracks/<slug>` (no port, credentials, query or fragment). Links open with `Launcher.LaunchUriAsync` only after that check.
- `FestivalSession` keeps one process-only feed with the publication it was observed under; `ShopOffersForCatalog` is non-null only when catalogue, Shop and client publications are equal (`SongRelatedPublicationPolicy`). Songs uses that for borders, filter and sort; mismatch pauses them with a notice.
- `ShopPresentationPolicy.Highlight`: Leaving Tomorrow wins over New; Hide Item Shop or Disable Shop Highlighting suppresses both (preferences kept).
- Colors: New = gold text/border (`FSTGoldBrush`), Leaving Tomorrow = white on `FSTStatusRedBrush`.
