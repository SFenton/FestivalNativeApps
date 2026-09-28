# Windows accessibility results

> **What:** per-page Windows accessibility status (Axe.Windows, keyboard, Narrator, contrast themes, text size, motion/transparency, in-app settings) and open gaps. **Read when:** changing a Windows page or control, or re-running the accessibility pass. Tools and the Narrator script: [windows.md](windows.md#accessibility); design rules: [design/windows.md](../design/windows.md#accessibility).

Evidence comes from `tools/windows/a11y_matrix.py` against the anonymized fixture (`rivals_fixture.py`), Debug build, 3840×2160 at 150%: sizes `compact` 500×800, `medium` 900×700, `wide` 1440×900 epx. Legend: ✅ pass · ⚠️ pass with a noted gap · ❌ fail · — not applicable · ⏳ not yet run.

## Checks

| Check | How |
|---|---|
| Axe | `--scan`: Axe.Windows 2.4.2 rules over every top-level window of the process, 0 errors required at compact/medium/wide |
| Tab | `--tabs 30`: Tab walk stays in the window, no repeated stop (trap), order follows reading order (title bar → pane → page) |
| Keys | `journeys/a11y-keyboard.json` `assertfocus` journeys (focus order, Esc returns focus to the invoker, Ctrl+1…7/Ctrl+comma, Ctrl+E/Ctrl+F, Alt+Left) |
| Narrator | Tree audit (names, roles, headings, landmarks, groups) + load/result/error notifications; manual script in [windows.md](windows.md#narrator-manual-script-operator) |
| HC | Aquatic, Desert, Dusk, Night sky (`--mode hc-*`): theme colours only behind content, text legible, focus visible |
| Text | 150% and 225% (`--mode text-*`): no clipped controls, title-bar search usable |
| Motion | Animation effects off, transparency off, in-app Reduce Motion/Disable Animated Artwork/Save Data and More Contrast/Less Transparency |

## Pages

| Page | Axe C/M/W | Tab | Keys | Narrator | HC | Text | Motion |
|---|---|---|---|---|---|---|---|
| Shell (title bar, pane, profile flyout) | ✅✅✅ | ✅ | ✅ | ✅ | ⏳ | ⚠️ 1 | ⏳ |
| Songs | ✅✅✅ | ✅ | ✅ | ✅ | ⚠️ 2 | ⏳ | ⏳ |
| Song Detail (+ Paths dialog) | ✅✅✅ | ✅ | ✅ | ✅ | ⚠️ 2 | ⏳ | ⏳ |
| Song Leaderboard | ✅✅✅ | ✅ | — | ✅ | ⏳ | ⏳ | ⏳ |
| Player History | ✅✅✅ | ✅ | — | ✅ | ⏳ | ⏳ | ⏳ |
| Song Band Leaderboard | ✅✅✅ | ✅ | — | ✅ | ⏳ | ⏳ | ⏳ |
| Item Shop | ✅✅✅ | ✅ | — | ✅ | ⏳ | ⏳ | ⏳ |
| Suggestions | ✅✅✅ | ✅ | ✅ | ✅ | ⏳ | ⏳ | ⏳ |
| Leaderboards | ✅✅✅ (fixed: card groups) | ✅ | ✅ | ✅ | ⏳ | ⏳ | ⏳ |
| Full Rankings | ✅✅✅ | ✅ | — | ✅ | ⏳ | ⏳ | ⏳ |
| Band Rankings | ✅✅✅ | ✅ | — | ✅ | ⏳ | ⏳ | ⏳ |
| Rivals / Compete | ✅✅✅ (fixed: section groups) | ✅ | — | ✅ | ⏳ | ⏳ | ⏳ |
| All Rivals | ✅✅✅ | ✅ | — | ✅ | ⏳ | ⏳ | ⏳ |
| Rival Detail | ✅✅✅ (fixed: category groups, button name) | ✅ | — | ✅ | ⏳ | ⏳ | ⏳ |
| Rivalry | ✅✅✅ (fixed: button name) | ✅ | — | ✅ | ⏳ | ⏳ | ⏳ |
| Statistics | ✅ (fixed: `/statistics` opened Coming Soon) | ⏳ | ✅ | ✅ | ⏳ | ⏳ | ⏳ |
| Player Profile | ✅✅✅ | ✅ | — | ✅ | ⏳ | ⏳ | ⏳ |
| Bands | ✅✅✅ | ✅ | — | ✅ | ⏳ | ⏳ | ⏳ |
| Player Bands | ⚠️ 3 | ✅ | — | ✅ | ⏳ | ⏳ | ⏳ |
| Band Detail | ✅✅✅ | ✅ | — | ✅ | ⏳ | ⏳ | ⏳ |
| Search | ✅✅✅ | ✅ | ✅ | ✅ | ⏳ | ⏳ | ⏳ |
| Settings | ✅✅✅ | ✅ | ✅ | ✅ | ⏳ | ⏳ | ⏳ |
| Licenses | ⏳ | ⏳ | — | ✅ | ⏳ | ⏳ | ⏳ |
| First-run dialog | ⏳ | — | ⏳ | ✅ | ⏳ | ⏳ | ⏳ |

## Open issues

1. Text size ≥150%: the title-bar caption is dropped so global search keeps its width; the title-bar layout itself belongs to the shell/infra lane.
2. Contrast themes keep brand hues for status rings (FC gold, scored green, no score red), Shop borders and percentile chips; the meaning is in each row's UIA name, but a system-colour mapping for HC is a design decision (TODO(orchestrator)).
3. Player Bands at compact once reported a zero-area row button (Axe `BoundingRectangle`), an `ItemsRepeater` element mid-recycle; not reproduced at medium/wide.
4. Narrator itself has no scripted driver: announcements are verified by unit tests (`LoadAnnouncer`) and the UIA tree; the operator script in [windows.md](windows.md#narrator-manual-script-operator) covers speech.
