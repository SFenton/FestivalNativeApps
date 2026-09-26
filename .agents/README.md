# Agent knowledge map

| If the task is about… | Read / update |
|---|---|
| Fluent vs native chrome, color, motion | [design/fluent.md](design/fluent.md) |
| SwiftUI, Duo, Liquid Glass, classic iOS, macOS | [platforms/apple.md](platforms/apple.md) |
| Android compact, passport, book, tablet, tri-fold | [platforms/android.md](platforms/android.md) |
| WinUI 3, game-alongside performance | [platforms/windows.md](platforms/windows.md) |
| Specific screen, guard, modal or deep link | `pages/<page-id>.md` and [contracts/product.json](../contracts/product.json) |
| Control geometry, state, interaction | `controls/<control-id>.md` and [contracts/product.json](../contracts/product.json) |
| Songs Sort draft, direction and state propagation | [controls/songs-sort.md](controls/songs-sort.md) |
| Safe player search, viewed vs selected identity and band-read gate | [controls/profile-selection.md](controls/profile-selection.md) |
| Solo score accuracy and full-combo states | [controls/score-accuracy.md](controls/score-accuracy.md) |
| CHOpt Paths image/text, chart selectors and stale loading | [controls/chopt-paths.md](controls/chopt-paths.md) |
| Shop route, public offers and visibility/highlight rules | [pages/shop.md](pages/shop.md), [controls/shop-offers.md](controls/shop-offers.md) |
| Unit/UI/visual/a11y/serial runtime evidence | [testing/quality-gates.md](testing/quality-gates.md) |
| Repeated page migration | [skills/port-page.md](skills/port-page.md) and `tools/verify_product.py` |
| Prioritized React-to-native gap list and dependencies | [parity-audit.md](parity-audit.md), [contracts/parity-backlog.json](../contracts/parity-backlog.json), `python3 tools/parity_backlog.py --list` |

Add a page/control spec **as it is investigated**, not from a route name alone. Mark its contract status `pending` until every documented reachable state and navigation edge has native evidence. Include original source path/line and, where practical, a fixture-backed visual reference. `contracts/source-snapshot.json` hashes the reviewed dirty source files; on the Mac, `python3 tools/source_snapshot.py --source <FST-repo>` checks for drift and fully qualified backlog/`.agents` citation bounds; `--write` refreshes hashes after a new review. A valid line number does **not** prove the cited semantics; review them against source. A commit hash alone does not represent the dirty Duo worktree. Update `contracts/product.json` after the website revision is stabilized.

Use executable checks instead of multiplying prose: contract uniqueness/coverage in `tools/verify_product.py`; platform tests and measured reports for line coverage and performance. Unsupported emulator poses and test-runner limitations must remain explicit gaps.
