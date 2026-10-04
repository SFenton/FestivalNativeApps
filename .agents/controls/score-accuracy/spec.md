# Score accuracy and full combo (`fst.score.accuracy.*`) — spec

> **What:** how accuracy and FC render in score rows, web vs native rule. **Read when:** drawing any score row (Detail preview, Solo chart, player cards) on any platform. Platform notes: [ios.md](ios.md) · [ipados.md](ipados.md) · [windows.md](windows.md).

Source: `FortniteFestivalWeb/src/components/songs/metadata/AccuracyDisplay.tsx:13-47`, `FortniteFestivalWeb/src/utils/formatters.ts:5-12`, `packages/core/src/app/formatters.ts:160-171`, `FortniteFestivalWeb/src/pages/leaderboard/global/components/LeaderboardEntry.tsx:105-147`, `packages/theme/src/spacing.ts:142-150,244-253`, `packages/theme/src/goldStyles.ts:17-34`, `FortniteFestivalWeb/src/pages/songinfo/components/InstrumentCard.tsx:226-253`. Never infer FC from an accuracy number.

| Response | Web | Native rule (all platforms) |
|---|---|---|
| Accuracy, FC false/missing | Rounded % pill, red→green background at 25% opacity | Same bounded interpolation, white %, spoken "Accuracy N%" |
| Accuracy, FC true | Gold outlined % (skewed, bold, italic) | Gold outline **plus visible `FC`**, spoken "Full combo, accuracy N%" |
| No accuracy, FC true | Gold outlined `0%` | `FC` / "Full combo; accuracy unavailable" — never invent 0% |
| Neither | Graded red `0%` (if the column shows) | No badge, no inferred FC |
| Non-finite / out-of-range | `NaN` → `0%`; colour clamps 0–100 | Reject non-finite tint input explicitly; keep out-of-range number, clamp colour only |
| Accessibility text size | Compact row adapts | Expand label, stack values, never clip score digits |

- Tint endpoints/midpoint must match the source exactly (test 0/50/98/100%, bounds, non-finite).
- One shared row renders both the Detail top-ten preview and the full Solo chart, so the policy must agree. Keep rank, name, whole score and badge independently accessible; colour is never the only cue.
- Missing accuracy is a **synthetic robustness state**: the service DTO uses a non-nullable integer and the chart copies it (`FSTService/Persistence/DataTransferObjects.cs:9-16`, `FSTService/Api/LeaderboardEndpoints.cs:389-405`); JSON omits nulls, not zeros (`FSTService/Program.cs:88-97`).
