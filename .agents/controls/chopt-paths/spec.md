# CHOpt Paths (`fst.song-detail.paths`) — spec

> **What:** platform-neutral web behavior and wire for the Paths modal (image + structured text). **Read when:** changing Paths on any platform. Platform notes: [ios.md](ios.md) · [ipados.md](ipados.md) · [macos.md](macos.md).

Source: `FortniteFestivalWeb/src/pages/songinfo/SongDetailPage.tsx:163-167,302-320,634-645`, `src/pages/songinfo/components/path/PathsModal.tsx:110-216,270-535,550-755`, `src/pages/songinfo/components/path/PathDataTable.tsx:63-137,338-437`, `src/contexts/SettingsContext.tsx:112-148`, `packages/core/src/api/serverTypes.ts:176-235`, `FSTService/Api/SongEndpoints.cs:259-385`. Audit refs: `PathsModal.tsx:110-190,550-652`.

## Wire

- `/api/paths/{songId}/{instrument}/{difficulty}` → PNG; `/data` → schema-2 JSON (activation beats, note frets, OD, scores). Both keyless, 200 live (2026-09-25).
- `generationId` = the catalogue's `pathArtifactGenerationId`; publication pin / 409 retry / ETag with distinct image and text URL keys. Bound decoded sizes; no third-party chart assets shipped.

## States and transitions

| State | Web behavior |
|---|---|
| Open / default | Mobile FAB / desktop header action; first visible path chart, Expert, saved image/text default |
| Warning | Enabled Karaoke warns once per opening, or "Don't show again" persists |
| Image | Separate PNG load/error, scroll and pinch zoom |
| Text | Activation note, beat, time, OD and score table; desktop columns drag-reorder and save to Settings |
| Switch | Instrument, four difficulties, image/text; an old request never paints after a new choice. Content fades out (300 ms), spinner fades in for at least 400 ms (image) / 500 ms (text), fades out (300 ms), new content fades in (`PathsModal.tsx:537-750`) |
| Side by Side (native, owner #368) | Not on the web. Where Paths covers a wide window (iPhone Duo inner display, iPad sidebar shell, Mac) the View menu adds Side by Side: image first, text table second, both loaded and switched independently; Duo book pose always shows it, with no View menu, split on the fold. The Settings Path Default View stays Image/Text and is the first view each opening. ([modal-shell](../../patterns/modal-shell.md) R11, [hinge-columns](../../patterns/hinge-columns.md) R10) |
| Error | Independent text/image failures |
| Dismiss | Close / overlay / Escape; the web dialog lacks a full focus trap (natives fix this). Native bottom/page sheets also swipe down to close (Apple issue #96); the Apple full-screen cover closes with Close or a pull down past the top of the image or table (#368) |

Settings dependencies: chart visibility limits the instrument menu (Intensity unaffected); if only Karaoke is visible, Paths must disappear entirely.

## Accessibility order (target)

Header/Close → instrument → difficulty → display → image/zoom **or** text summary/activation rows. The background page must not accept actions while the sheet is open. IDs: `fst.song-detail.paths`, `fst.paths.*`, `fst.settings.path-default-view`.
