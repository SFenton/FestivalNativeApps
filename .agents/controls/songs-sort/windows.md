# Songs Sort — Windows notes

> **What:** the Windows Sort flyout and Item Shop sort. **Read when:** changing `SongSortDraft`, `SongListPipeline.CompareShop` or `ShopSections`. Rules: [spec.md](spec.md).

- Flyout: `RadioButtons` over Title/Artist/Year/Duration/Item Shop/Has FC, the web's list (Item Shop removed while Shop is hidden; a saved Shop sort then shows no selection), direction `ToggleSwitch`, Reset; every change applies live (no Cancel/Apply). Summary label on the button (`Item Shop ↑`), gold when non-default.
- Item Shop sort needs `ShopOffersForCatalog`; otherwise Title order in the saved direction with a pause notice (hidden, loading/failed, publication mismatch).
- Buckets use the first-seen order of the sorted rows (Leaving Tomorrow / In Shop / Not In Shop); a single bucket has no header and disables the jump index.
