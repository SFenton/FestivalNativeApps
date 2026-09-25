# Festival Native Apps

Native clients for [Festival Score Tracker](https://festivalscoretracker.com):
SwiftUI on iOS/iPadOS and macOS, Kotlin/Jetpack Compose on Android, and C#/WinUI 3 on Windows. This is a new product, not a React Native or embedded-web app.

**Status:** Initial architecture and contract inventory are under construction. No platform or page is currently certified feature-parity with the website. `python3 tools/verify_product.py --strict` must pass before anyone claims parity.

The source-of-truth website and service are in `SFenton/FortniteFestivalLeaderboardScraper`. The initial observations came from commit `47090ef1ab7c2e189b04a1e29cfcf469a4098464` **with additional uncommitted website changes**; any parity claim requires a reproducible source snapshot and re-audit. This repository is separate: do not modify the website to make a native test pass.

## Where to start

- [Agent routing and safety](AGENTS.md)
- [Design, platform, page/control, and testing index](.agents/README.md)
- [Machine-checkable product inventory](contracts/product.json)
- [Deterministic inventory validator](tools/verify_product.py)

Run `python3 -m unittest discover -s tools/tests` and `python3 tools/verify_product.py` after updating the inventory. The non-strict command checks consistency and reports unported surfaces; strict mode additionally fails unless every listed surface has evidence for all platforms.

Public PWA functionality does **not** require distributing the service's privileged `X-API-Key`. Never put a shared service credential in an app, fixture, log, repository, or build artifact. Local UI automation uses fixtures, not production endpoints that may have side effects.
