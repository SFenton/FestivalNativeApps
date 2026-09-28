# Difficulty meter (`fst.songs.difficulty-meter`) — spec

> **What:** exact geometry, value mapping and accessibility of the branded seven-bar meter. **Read when:** drawing the meter on any platform. Platform notes: [ios.md](ios.md).

Source: `FortniteFestivalWeb/src/components/songs/metadata/DifficultyBars.tsx:15-37`, `packages/core/src/api/serverTypes.ts:69-95`. Branded content: match the web shape; never substitute a platform progress bar.

## Geometry

Seven 8×20 parallelograms one unit apart. Bar `i` starts at `x = i × 9` with vertices `(x+2,0) (x+8,0) (x+6,20) (x,20)`; canvas 62×20. Filled sRGB `#FFFFFF`, unfilled `#666666`.

## Values

- Raw 0–6 level: truncate, clamp to 0–6, add one (raw 5.9 → 6 bars; raw 99 → 7).
- Display 1–7 level: clamp without truncation (3.5 fills 3 bars, announced "Difficulty 3.5 of 7").
- Non-finite values are excluded from chart support; natives render "Difficulty unavailable" instead of a fake level.

## States and accessibility

`one` … `seven`, `invalid`. A chart change updates shape, accessible value and any parent row/card announcement together. One image-like accessible element; decorative polygons hidden; never colour alone. IDs: `fst.songs.difficulty-meter`, invalid `fst.songs.difficulty-unavailable`.
