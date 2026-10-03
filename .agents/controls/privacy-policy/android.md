# Privacy Policy — Android notes

> **What:** how Android implements Settings › Privacy Policy. **Read when:** changing the policy row or sheet on Android. Spec: [spec.md](spec.md).

## Implementation

| Piece | Where |
|---|---|
| Text | `app/src/main/assets/privacy-policy.json`, a byte-for-byte copy of `contracts/privacy-policy.json`, parsed by `core/privacy/PrivacyPolicy.kt` (schema 1; invalid blocks dropped; unreadable → "The privacy policy could not be loaded.") |
| Row | `SettingsScreen.kt` `NavigationRow` (`fst.settings.privacy-policy`) after Licenses, Quick Link `privacy-policy` |
| Sheet | `ui/settings/PrivacyPolicySheet.kt`: the shared `FestivalModalSheet` on compact widths, `FestivalModalDialog` (≤ 640 dp tall) on medium/expanded |
| IDs | `fst.privacy-policy.sheet`, `.title`, `.close`, `.content` (lazy list), `.effective-date`, `.section.<id>`, `.empty` |

## Decisions

- **Modal, not a push:** Material full-screen-style sheet/dialog, matching every other Festival modal. Dismiss with Close, Back or swipe down (sheet).
- **Text:** Material type scale in `sp`, so it follows the system font scale; section titles are TalkBack headings; bullet glyphs are hidden from TalkBack; HTTPS addresses are `LinkAnnotation.Url` links that open the browser. Each section is a `SelectionContainer`, so its text is selectable. Bullet labels are not bolded (the spec makes that optional). No WebView, no network.

## Tests

`privacy/PrivacyPolicyTest.kt` (asset equals the contract byte for byte, section order, malformed/schema/invalid-block handling, link ranges); `settings/SettingsUiTest.kt` (row opens the sheet, scroll to Contact, Close returns to Settings; dialog on expanded windows).
