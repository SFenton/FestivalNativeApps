# Score metadata — iPhone notes

> **What:** the SwiftUI card policy/layout and its measured constraints. **Read when:** changing `SongProfileCardPolicy`, `SongMetadataFlow` or selected Songs rows. Spec: [spec.md](spec.md).

- `SongProfileCardPolicy` (`FestivalUI`) projects `PlayerScore`, catalogue `Song`/season and the eight saved switches into typed fields in source order; `SongMetadataFlow` wraps them right-aligned (`Features/Songs/SongProfileMetadataPills.swift`).
- Place each wrapped pill at its **actual fitted width**: reserving the full width proposal left 14pt (iPhone) / 57pt (iPad) trailing gaps at AX5.
- Compare the Score's right edge with the **last** enabled pill (Last Played when present), within 2pt; at AX5 also align the wrapped date with the separate trailing Shop badge.
- Pills use scaled horizontal text insets: ≥4 painted glyph-to-edge pixels at xLarge, AX3 and AX5. At accessibility sizes stars become one star + a readable count. (The fixed Solo accuracy badge must **not** get padding — [score-accuracy](../score-accuracy/ios.md).)
- Native FC cue is visible and spoken ("FC 97.9%"); no gold skew.
- Hosted AX5 `ImageRenderer` passed with broken UIKit geometry once — keep device assertions and read real screenshots.
- Edge fixture: pinned port 8776 `--metadata-edge` (long title, 1,234,567 score, Shop New) — [fixtures](../../testing/fixtures.md).
- Open: Last Played sort, editable order, invalid-score substitution, band cards, representative-catalogue performance.
