# What's New changelog — iPhone notes

> **What:** the SwiftUI What's New sheet, its launch gate and Settings replay as built, decisions and open gaps. **Read when:** changing the changelog content, gate or sheet on iPhone. Spec: [spec.md](spec.md).

## Architecture

| Piece | File | Notes |
|---|---|---|
| Data + hash + seen store | `FestivalCore/Changelog.swift` | `Changelog.entries` decoded from the bundled `Apps/iOS/WhatsNew.json` (generated per release build; checked-in placeholder `2610.01.01`), `decode(_:)` bounds it; `hash(_:)` reproduces `calculateChangelogHash`; `emptyHash` never shows; `displayEntries` drops Manual; `ChangelogSeenStore` (`fst.changelog.seen.v1`, ≤1 KB, empty/oversized hash → unseen) |
| Sheet | `Features/WhatsNew/WhatsNewSheet.swift` | Each entry: Title 3 semibold heading (`Version …`, or for testers `Changes Since Release …` / `Changes So Far (No Release Yet)`) over Headline category headings from `groups` (none when every note is uncategorized, like TestFlight's text). `NavigationStack` inline title `What's New · <CFBundleShortVersionString>`, opaque `cardBackground` (page, nav bar, `presentationBackground`), bullets as primary text, **Dismiss** in an opaque `safeAreaInset(.bottom)` bar with a hairline (the list ends above it), toolbar ✕ |
| Launch gate | `Features/WhatsNew/WhatsNewModifier.swift` | `.whatsNew(session:)` over `WhatsNewLauncher.shared` (tests inject their own); resolves once per process; waits `settleDelay` (700 ms) so the launch page's `.firstRun` claims first, then claims `FirstRunCenter` slot `whats-new`; re-checks whenever `activeKey` returns to nil; `onDismiss` stores `{version, hash}` and releases the slot |
| Root hook | `App/FestivalRootView.swift` | One additive `.whatsNew(session: session)` line after the global-search sheet |
| Replay | `Features/Settings/SettingsScreen.swift` | Version card row `fst.settings.whats-new` ("Show") |
| Install channel | `FestivalCore/AppDistribution.swift` | `AppDistributionResolver.shared` (`@Observable`; issue #80): Debug answers `FST_DEBUG_DISTRIBUTION` (default `development`) without StoreKit; Release treats an `appStoreReceiptURL` named `sandboxReceipt` as TestFlight at once (iOS/iPadOS; macOS's `_MASReceipt/receipt` can't tell), else races `AppTransaction.environment` against 10 s. Only a definitive answer is cached. A timeout/error publishes a provisional `.appStore`; a timed-out probe keeps running and upgrades `channel`, and a failed one is retried on the next call. `channel == nil` is *pending*. `WhatsNewChannelSheet` (launch, Settings replay, Mac command) shows a spinner (`fst.whats-new.pending`) then, for TestFlight/development, the tester list; App Store installs never see it. The hash ignores tester sections |

## Debug (`FST_DEBUG_WHATS_NEW`)

| Value | Debug behavior (Release is always `on`) |
|---|---|
| unset / other | `off`: never auto-present |
| `on` | Real gate |
| `fresh` | Forget stored dismissal once at launch, then real gate |
| `force` | Present every launch |

`FST_DEBUG_DISTRIBUTION=appstore|testflight|development` (Debug only, default `development`) picks the channel for screenshots and tests.

## Decisions

- Gate on the content hash (web parity), not on the native app version; the title shows the native version because the card lives in the native app.
- Launch and Settings replay both use `whatsNewPresentation(isPresented:)`, built on the shared `festivalModalPresentation` ([modal-shell](../../patterns/modal-shell.md) R12, #368): a full-height `fullScreenCover` on iPhone (operator, 2026-09-28: the large sheet's curved bottom corners exposed the page and content scrolled visibly under Dismiss), a sheet on macOS. A cover has no system swipe-down, so `PullDownToDismiss` (iOS 18+) closes it when the list is pulled ≥ 80 pt past its top and released (operator batch 6, 6.14). Dismiss is full width with centred text (web parity; 6.14's centring was a Windows repro). Close is the shared `FestivalModal`'s system Close, top-right (issue #23 moved it from a leading hand-drawn ✕).
- Category groups (issue #80, owner scope update): render `groups` / `testflight.groups` exactly as `versioning.py` writes them (page order, prefixes stripped, null = "Other" last); never re-classify in the app. Documents without `groups` show flat notes. The old "New Since …" / "In This Build vs. Release …" pair is gone: testers see one list, the same as TestFlight's What to Test. HIG `apple-hig/references/hig/typography.md`: "Adjust weight, size and color as needed to emphasize important information and show hierarchy" (Title 3 over Headline, built-in styles for Dynamic Type); `loading.md`: "Show something quickly" (spinner while pending, never wrong notes).
- Natives no longer mirror the web changelog (operator, 2026-10-01): content is the iOS-only notes per released version. `WhatsNewLauncher` takes `changelogHash` (default `Changelog.currentHash`) because SwiftPM tests have no app bundle and would otherwise see an empty changelog.

## Tests

`FestivalCoreTests/ChangelogTests.swift` (decode/bounds (40 bullets per release entry, 120 in the tester list, 24 groups), category groups and tester list, bundled placeholder, hash, JSON escaping, Title Case, Manual filter, seen store, channel resolver: sandbox receipt, pending, timeout + late answer, error retry); `FestivalUITests/WhatsNewAndServiceInfoTests.swift` (debug-mode parse, pending gate, slot exclusion, hosted render with category headings and the pending spinner); `iOSUITests/WhatsNewJourneyTests.swift` (launch → Dismiss → relaunch not shown; Settings replay; pull-down dismissal + centred Dismiss; needs `tools/mock_service.py --port 18791`).
