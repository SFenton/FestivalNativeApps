# What's New changelog — Android notes

> **What:** the Compose What's New sheet/dialog, its launch gate, the shared onboarding slot and Settings replay as built. **Read when:** changing the changelog content, gate or presentation on Android. Spec: [spec.md](spec.md); iPhone: [ios.md](ios.md); Windows: [windows.md](windows.md).

## Implementation

| Piece | Where |
|---|---|
| Entries, web hash, Title Case, Manual filter | `core/whatsnew/Changelog.kt`; `WhatsNewTest.hashMatchesTheWebPrecomputedHash` pins `-6p8bh3` (web 0.1.133). Keep entries byte-identical to `FortniteFestivalWeb/src/changelog.ts` and bump `WEB_HASH` in the same commit |
| Dismissal record | `core/whatsnew/WhatsNewGate.kt` `ChangelogSeenStore` over DataStore key `fst.changelog.seen.v1` (`SettingsRegistry`, kept by Settings Reset): `{version, hash}` ≤ 1 KB, hash 1–32, version ≤ 64; corrupt/oversized → show again |
| Gate + launcher | `WhatsNewMode` / `WhatsNewGate` (pure) and `presentation/whatsnew/WhatsNewController.kt` (`AppContainer.whatsNew`): resolves once per process, claims the shared slot, records the dismissal on every close |
| One-modal slot | `FirstRunCenter.claim(key)` / `release(key)` / `claimed`: a claim fails while a carousel is active; `tryBegin`/`beginReplay` return null while a claim is held (web `activeCarouselKey`) |
| UI | `ui/whatsnew/WhatsNewSheet.kt`: `WhatsNewHost` (shell, beside `FirstRunHost`), `WhatsNewSheet`, `WhatsNewSettingsRow` |
| Replay | Settings → Version → **What's New · Show** (blue filled, `fst.settings.whats-new`) → `WhatsNewController.replay()` |

## Presentation

- Compact windows (< 600 dp): full-height `ModalBottomSheet` (M3 bottom sheets suit compact screens; swipe down, back and a scrim tap all close it). Wider windows: a 560 dp M3 dialog (a bottom sheet would be width-capped and short on landscape tablets); outside tap and back close it. Every close path records the dismissal (web writes `{version, hash}` on dismiss).
- Opaque `cardBackground`; title "What's New · <versionName>" (heading); Close icon (`fst.whats-new.close`); Title Case section headings (heading semantics) with decorative bullets; the list (`fst.whats-new.list`) scrolls above an opaque bottom bar with a hairline and a **centred** Dismiss button (`fst.whats-new.dismiss`, batch 6.14). Pane title = the sheet title.

## Gate and ordering

- `WhatsNewHost` waits 700 ms (`WhatsNewGate.SETTLE_MS`, > first-run's 600 ms settle) so the launch page's carousel claims the slot first; it re-checks whenever the carousel, profile sheet or notifications sheet closes. While What's New shows, `FirstRunHost` is blocked and re-evaluates the page once it closes.
- `FST_DEBUG_WHATS_NEW=off|on|fresh|force` ([android debug extras](../../platforms/android.md#debug-launch-extras-debug-builds-only)): debug default **off** so journeys and screenshots never meet it; release is always normal; `fresh` forgets the dismissal once per process.

## Tests

- JVM: `whatsnew/WhatsNewTest` (hash, `JSON.stringify` escaping, Title Case, Manual filter, store validation, mode/debug extra, slot exclusion, controller launch/replay/fresh/force).
- Robolectric: `whatsnew/WhatsNewUiTest` (phone sheet: force → Dismiss records seen; debug default off; Settings replay → Close) and `WhatsNewDialogUiTest` (wide dialog). Buttons inside the Robolectric bottom sheet are activated with the semantics `OnClick` action (touch injection into the sheet popup is unreliable there).
