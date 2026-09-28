# What's New changelog — iPhone notes

> **What:** the SwiftUI What's New sheet, its launch gate and Settings replay as built, decisions and open gaps. **Read when:** changing the changelog content, gate or sheet on iPhone. Spec: [spec.md](spec.md).

## Architecture

| Piece | File | Notes |
|---|---|---|
| Data + hash + seen store | `FestivalCore/Changelog.swift` | `Changelog.entries` verbatim from the web; `hash(_:)` reproduces `calculateChangelogHash` (`ChangelogTests` pins `webHash` `-6p8bh3`); `displayEntries` drops Manual; `ChangelogSeenStore` (`fst.changelog.seen.v1`, ≤1 KB, empty/oversized hash → unseen) |
| Sheet | `Features/WhatsNew/WhatsNewSheet.swift` | `NavigationStack` inline title `What's New · <CFBundleShortVersionString>`, `festivalSheet(.large)`, bullets as primary text, bottom-inset prominent **Dismiss**, toolbar ✕ |
| Launch gate | `Features/WhatsNew/WhatsNewModifier.swift` | `.whatsNew(session:)` over `WhatsNewLauncher.shared` (tests inject their own); resolves once per process; waits `settleDelay` (700 ms) so the launch page's `.firstRun` claims first, then claims `FirstRunCenter` slot `whats-new`; re-checks whenever `activeKey` returns to nil; `onDismiss` stores `{version, hash}` and releases the slot |
| Root hook | `App/FestivalRootView.swift` | One additive `.whatsNew(session: session)` line after the global-search sheet |
| Replay | `Features/Settings/SettingsScreen.swift` | Version card row `fst.settings.whats-new` ("Show") |

## Debug (`FST_DEBUG_WHATS_NEW`)

| Value | Debug behavior (Release is always `on`) |
|---|---|
| unset / other | `off`: never auto-present |
| `on` | Real gate |
| `fresh` | Forget stored dismissal once at launch, then real gate |
| `force` | Present every launch |

## Decisions

- Gate on the content hash (web parity), not on the native app version; the title shows the native version because the card lives in the native app.
- System sheet with drag indicator instead of the web's centred card (HIG); swipe-down counts as Dismiss.
- The shipped web entries include web-only chrome items (FAB dock, search modal). They are kept verbatim for hash parity. TODO(orchestrator): decide whether natives should curate a separate changelog.

## Tests

`FestivalCoreTests/ChangelogTests.swift` (hash parity, JSON escaping, Title Case, Manual filter, seen store); `FestivalUITests/WhatsNewAndServiceInfoTests.swift` (debug-mode parse, pending gate, slot exclusion, hosted render); `iOSUITests/WhatsNewJourneyTests.swift` (launch → Dismiss → relaunch not shown; Settings replay; needs `tools/mock_service.py --port 18791`).
