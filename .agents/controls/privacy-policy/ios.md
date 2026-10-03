# Privacy Policy — iPhone notes

> **What:** how iPhone implements Settings › Privacy Policy. **Read when:** changing the policy row or sheet on iPhone, or any shared Apple code they use. Spec: [spec.md](spec.md).

## Implementation

| Piece | Where |
|---|---|
| Text | `FestivalCore/PrivacyPolicy.swift` (`PrivacyPolicy.current`), the Swift copy of `contracts/privacy-policy.json`; `FestivalCoreTests/PrivacyPolicyTests` fails if they differ, a required section is missing or the effective date and its text disagree |
| Row | `SettingsScreen.privacyPolicyRow` (`fst.settings.privacy-policy`): same title + description + chevron style as Licenses, placed after Licenses with Quick Link `privacy-policy`. A `Button` with label "Privacy Policy" and hint "How Festival Score Tracker handles your information" |
| Sheet | `Features/Settings/PrivacyPolicySheet.swift`: `FestivalModal("Privacy Policy", closeIdentifier: "fst.privacy-policy.close")` + `festivalSheet(.large)` from `SettingsScreen`'s own `.sheet(isPresented:)` |
| IDs | `fst.privacy-policy.content` (scroll view), `.effective-date`, `.section.<id>` (headings) |

## Decisions

- **Modal, not a push.** HIG Sheets: "A sheet requests specific information or presents a scoped, context-related task people complete before returning to the parent view." Licenses pushes because each entry opens its own sheet; the policy is one self-contained document, which the issue asks to surface as a modal.
- **Dismiss:** the shared system Close in the navigation bar plus the sheet's swipe-down. HIG Sheets (iOS, iPadOS): "Support swiping vertically to dismiss." HIG Modality: "Always provide an obvious, platform-conventional dismissal: iOS/iPadOS/watchOS commonly use a top-toolbar button or swipe down". Large detent only, so no grabber (same as every large Festival sheet).
- **Text:** `.body`/`.headline`/`.subheadline` Dynamic Type styles with `fixedSize(horizontal: false, vertical: true)` so every line wraps at accessibility sizes; headings carry `.isHeader` (HIG VoiceOver: "Use titles and headings to convey hierarchy"); `.textSelection(.enabled)` (HIG Text views: "Make useful text selectable"); bullet glyphs are hidden from VoiceOver and each bullet reads as one element; a short bullet label ("GitHub:") is bold and the Contact address is an inline `AttributedString` link (`PrivacyPolicy.styledText`), with the words unchanged. Column capped at 680 pt, centred.
- The Contact address opens the system browser; no in-app web view and no network call.

## Tests

`SettingsJourneyTests.testPrivacyPolicyRowOpensDismissibleSheet` (open, scroll to Contact, system Close) and the Quick Links page-order test; hosted render `PrivacyPolicyHostedTests` (macOS host).
