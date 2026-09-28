# Songs — Android notes

> **What:** what the Android Songs page implements, native decisions and open gaps. **Read when:** changing Songs on Android. Behavior: [spec.md](spec.md).

## Implemented

- Live keyless `/api/songs` through `FestivalApi.catalog()` (publication-aware, memoized per publication); loading / service-status (freeze countdown + Retry Now) / empty / populated; pull to refresh re-checks the publication.
- Search field at the top of the list (250 ms debounce, `SongSearch` NFKD/apostrophe/separator rules); Sort sheet (Title/Artist/Year/Duration + direction, persisted in DataStore, gold icon when non-default); Filter sheet (single visible chart) **only with a selected player**; right-edge section index for Title/Artist/Year (`SongSectionIndex`, consecutive-key chunks, `#` bucket).
- Glass card rows: 48 dp art, Title, `artist · year · duration`; the active chart filter adds its difficulty meter. One merged TalkBack stop, whole card tappable, no chevron. Test tags `fst.songs.list|search|sort|filter|row.<id>|empty|section-index`.
- Expanded widths / separating hinge: list + Song Detail panes (`fst.songs.detail-pane`).

## Native decisions

| Web | Android | Why |
|---|---|---|
| Sort/Filter draft with Apply | Choices apply immediately | Material bottom-sheet pattern; revisit with profile sort modes |
| Lower search dock | Search field as the first list item | Material; keeps the bottom bar for navigation |
| Filter hidden without a profile (mobile) | Same | Parity with web/Apple |

## Open

Item Shop sort/highlights, profile score chips/metadata, invalid-score action, Quick Links, first-run carousel, band rows, section-index TalkBack alternative.
