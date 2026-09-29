# What's New changelog — iPhone notes

> **What:** the SwiftUI What's New sheet, its launch gate and Settings replay as built, decisions and open gaps. **Read when:** changing the changelog content, gate or sheet on iPhone. Spec: [spec.md](spec.md).

## Architecture

| Piece | File | Notes |
|---|---|---|
| Data + hash + seen store | `FestivalCore/Changelog.swift` | `Changelog.entries` verbatim from the web; `hash(_:)` reproduces `calculateChangelogHash` (`ChangelogTests` pins `webHash` `-6p8bh3`); `displayEntries` drops Manual; `ChangelogSeenStore` (`fst.changelog.seen.v1`, ≤1 KB, empty/oversized hash → unseen) |
| Sheet | `Features/WhatsNew/WhatsNewSheet.swift` | `NavigationStack` inline title `What's New · <CFBundleShortVersionString>`, opaque `cardBackground` (page, nav bar, `presentationBackground`), bullets as primary text, **Dismiss** in an opaque `safeAreaInset(.bottom)` bar with a hairline (the list ends above it), toolbar ✕ |
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
- Launch and Settings replay both use `whatsNewPresentation(isPresented:)`: a full-height `fullScreenCover` on iPhone (operator, 2026-09-28: the large sheet's curved bottom corners exposed the page and content scrolled visibly under Dismiss), a sheet on macOS. A cover has no system swipe-down, so `PullDownToDismiss` (iOS 18+) closes it when the list is pulled ≥ 80 pt past its top and released (operator batch 6, 6.14). Dismiss is full width with centred text (web parity; 6.14's centring was a Windows repro).
- The shipped web entries include web-only chrome items (FAB dock, search modal). They are kept verbatim for hash parity. TODO(orchestrator): decide whether natives should curate a separate changelog.

## Tests

`FestivalCoreTests/ChangelogTests.swift` (hash parity, JSON escaping, Title Case, Manual filter, seen store); `FestivalUITests/WhatsNewAndServiceInfoTests.swift` (debug-mode parse, pending gate, slot exclusion, hosted render); `iOSUITests/WhatsNewJourneyTests.swift` (launch → Dismiss → relaunch not shown; Settings replay; pull-down dismissal + centred Dismiss; needs `tools/mock_service.py --port 18791`).
