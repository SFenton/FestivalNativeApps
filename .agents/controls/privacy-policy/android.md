# Privacy Policy — Android notes

> **What:** how Android implements Settings › Privacy Policy. **Read when:** changing the policy row or sheet on Android. Spec: [spec.md](spec.md).

## Implementation

| Piece | Where |
|---|---|
| Text | `app/src/main/assets/privacy-policy.json`, a byte-for-byte copy of `contracts/privacy-policy.json`, parsed by `core/privacy/PrivacyPolicy.kt` (schema 1; invalid blocks dropped; unreadable → "The privacy policy could not be loaded.") |
| Row | `SettingsScreen.kt` `NavigationRow` (`fst.settings.privacy-policy`) after Licenses, Quick Link `privacy-policy` |
| Sheet | `ui/settings/PrivacyPolicySheet.kt`: the shared `FestivalModalSheet` on compact widths, `FestivalModalDialog` (≤ 640 dp tall) on medium/expanded |
| Pane | List/detail Settings (≥ 840 dp text-scaled, e.g. a phone in landscape, #371): `PrivacyPolicyPane` in the shared detail column (`fst.settings.detail.privacy-policy`, scrolls, 840 dp cap): the pane `Header`, then the policy inside one `GlassCard` (#609) |
| IDs | `fst.privacy-policy.sheet`, `.title`, `.close`, `.content` (lazy list in the modal, a column in the pane card), `.effective-date`, `.section.<id>`, `.empty`; pane: `fst.privacy-policy.pane`, `.card` |

## Decisions

- **Modal, not a push:** Material full-screen-style sheet/dialog, matching every other Festival modal. Dismiss with Close, Back or swipe down (sheet).
- **Pane text in a card (#609):** in the list/detail pane the policy never sits on the bare artwork; it reads in one `GlassCard` like every other Settings detail ([surface-materials](../../patterns/surface-materials.md) R4), frosted by default and opaque under Reduce Transparency or Increase Contrast. Its readable width is the detail column's 840 dp cap, the same as the other detail cards. The modal keeps its opaque surface with no inner card (R6). Material 3 lists Card under "Containment" (outlined: "Surface fill, outline-variant border"; `GlassCard` is that tonal Surface with a border, R5), and its layout checklist asks to "Verify content doesn't stretch beyond readable line lengths".
- **Text:** Material type scale in `sp`, so it follows the system font scale; section titles are TalkBack headings; bullet glyphs are hidden from TalkBack; HTTPS addresses are `LinkAnnotation.Url` links that open the browser. Each section is a `SelectionContainer`, so its text is selectable. Bullet labels are not bolded (the spec makes that optional). No WebView, no network.

## Tests

`privacy/PrivacyPolicyTest.kt` (asset equals the contract byte for byte, section order, malformed/schema/invalid-block handling, link ranges); `settings/SettingsUiTest.kt` (row opens the sheet, scroll to Contact, Close returns to Settings; on expanded windows `ExpandedSettingsUiTest.privacyPolicyOpensInThePane`: the card under the header, inside the pane, ≤ 840 dp, scrolls to Contact); `settings/SettingsPaneCardSurfaceUiTest.kt` (pane card frosted, opaque under Reduce Transparency and Increase Contrast, text and the unreadable state inside it). Connected: `journeys/PrivacyPolicyPaneAccessibilityJourneyTest` (landscape phone: ATF, reading order title → hint → effective date → Overview, the card a traversal group, text unclipped; 200 % text drops to the modal; opaque card pixels under Reduce Transparency) and `ModalCloseJourneyTest.settingsPrivacyLicensesAndFeedbackClose` (portrait sheet).
