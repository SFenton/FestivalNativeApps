# CHOpt Paths (`fst.song-detail.paths`) — spec

> **What:** platform-neutral web behavior and wire for the Paths modal (image + structured text). **Read when:** changing Paths on any platform. Platform notes: [ios.md](ios.md) · [ipados.md](ipados.md).

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
| Switch | Instrument, four difficulties, image/text; an old request never paints after a new choice |
| Error | Independent text/image failures |
| Dismiss | Close / overlay / Escape; the web dialog lacks a full focus trap (natives fix this) |

Settings dependencies: chart visibility limits the instrument menu (Intensity unaffected); if only Karaoke is visible, Paths must disappear entirely.

## Accessibility order (target)

Header/Close → instrument → difficulty → display → image/zoom **or** text summary/activation rows. The background page must not accept actions while the sheet is open. IDs: `fst.song-detail.paths`, `fst.paths.*`, `fst.settings.path-default-view`.
