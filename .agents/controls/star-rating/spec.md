# Star rating (`fst.star-rating.*`, `fst.stars`) — spec

> **What:** how star counts render in score rows, cards and profile tiles on every platform. **Read when:** drawing stars anywhere (Songs metadata, Song Detail rows, leaderboards, Suggestions, profile/band stats).

Source: `FortniteFestivalWeb/src/components/songs/metadata/MiniStars.tsx:8-38`, `GoldStars.tsx:18-31`, images `FortniteFestivalWeb/public/star_white.png` and `star_gold.png`.

| Stars | Web | Native rule (all platforms) |
|---|---|---|
| 1–5 | That many white-star images (minimum 1), in circles | Same count of `star_white` images; spoken "N stars" |
| 6 (or more) | Five gold-star images with a gold outline | Five `star_gold` images; spoken "N gold stars" (5) |
| Average stars = 6 (profile/band) | Gold stars | Gold stars (same rule) |

- Always use the bundled web star images, never platform glyphs (SF Symbols, Material icons, Segoe glyphs).
- Do not list or mention the star images on the Licenses page (operator rule, [licenses spec](../../pages/licenses/spec.md)).
- Implementations: Apple `FestivalUI/Design/StarRating.swift`, Android `ui/design/StarRating.kt`, Windows `StarRow` + Core `StarRating`. The image row is one accessibility element with the spoken count.
- Platform notes: [windows.md](windows.md).
