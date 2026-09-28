# Difficulty meter (`fst.songs.difficulty-meter`)

Source: `FortniteFestivalWeb/src/components/songs/metadata/DifficultyBars.tsx:15-37` and `packages/core/src/api/serverTypes.ts:69-95`. This branded content must match the web shape rather than being replaced by a platform progress bar.

Seven 8×20 parallelograms sit one unit apart. Bar `i` starts at `x = i × 9` and has vertices `(x+2,0) (x+8,0) (x+6,20) (x,20)`, making the canvas 62×20. Filled is sRGB white `#FFFFFF`; unfilled is `#666666`. For a raw 0–6 level, truncate then clamp to 0–6 and add one. A display 1–7 level clamps without truncation: 3.5 fills 3 bars but is announced as “Difficulty 3.5 of 7”. Web raw 5.9 fills 6; out-of-range raw 99 fills 7. Non-finite values are excluded from song chart support; the native control additionally renders “Difficulty unavailable” instead of claiming a valid level.

States: one through seven visible bars and invalid/unavailable. A visible chart change updates the shape, the accessible value and any parent row/card announcement together. Do not rely on color alone; attach an image-like single accessible element and hide decorative child polygons. Keep native test ID `fst.songs.difficulty-meter` stable; the invalid state uses `fst.songs.difficulty-unavailable`.

Current evidence: SwiftUI Canvas geometry and all seven rendered states are exercised by `apple/Tests/FestivalDesignTests/DifficultyMeterTests.swift` (62×20, seven center pixels in source color space). Android and Windows controls and cross-platform screenshots are pending; the registry status remains `pending` until all platforms, invalid/fractional states and accessibility order are verified.
