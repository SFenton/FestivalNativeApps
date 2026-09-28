# Solo leaderboard — iPhone notes

> **What:** iPhone implementation state and decisions for the Solo chart. **Read when:** changing the Solo page on iPhone. Behavior: [spec.md](spec.md).

- Implemented: 25-row pages, first/previous/info/next/last with ≥44pt actions on an opaque two-row Fluent plate that stays readable over art; enabled/disabled boundaries tested. The web uses icon-only portal controls — intentional Fluent deviation, not pixel parity.
- Accuracy/FC via the shared row ([score-accuracy/ios.md](../../controls/score-accuracy/ios.md)); the full List keeps separate row and `fst.score.accuracy.*` IDs.
- AccessibilityXXXL: the fixed song header left no usable List viewport and `99,900` wrapped into `99,90` + `0`. The header/disclosure now scroll above scores inside the same List, and rank/name, whole score and accuracy each get a full-width line; ordinary sizes keep compact columns.
- A live probe decoded one real 25-row Lead chart (2026-09-25); tapping into a live Solo page on device is not yet shown.
- Open: rows cannot open player profiles until that route exists; selected-profile footer; announced page change and stable VoiceOver focus. Warm-offline "last seen scores" banners predate online-only — remove, don't extend.
