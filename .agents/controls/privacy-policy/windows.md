# Privacy Policy — Windows notes

> **What:** how Windows implements Settings › Privacy Policy. **Read when:** changing the policy row or dialog on Windows. Spec: [spec.md](spec.md).

## Implementation

| Piece | Where |
|---|---|
| Text | `Festival.App.csproj` links `contracts/privacy-policy.json` as `Assets\privacy-policy.json` (no copy to drift); `Festival.Core/Domain/PrivacyPolicy.cs` parses it (1 MB cap, schema 1, invalid blocks dropped, unreadable → "could not be loaded") |
| Row | `SettingsPage.xaml` navigation row (`fst.settings.privacy-policy`) after Licenses, Quick Link `privacy-policy` (glyph `\uEA18`) |
| Dialog | `Festival.App/Controls/PrivacyPolicyDialog.cs` in the shared `FestivalDialog` (title "Privacy Policy", spanning Close; Esc and an outside click also close) |
| IDs | `fst.privacy-policy.dialog`, `.close`, `.content` (scroller), `.effective-date`, `.section.<id>` |

## Decisions

- **Fluent ContentDialog-style modal**, as triage suggested; focus returns to the row on close.
- The scroller is a tab stop named after the policy title, so the dialog opens focused on the text (arrow/Page keys scroll) instead of on the bottom hyperlink. Panel padding `8,6,16,6` keeps the focus rectangle from clipping the first letter of each line.
- Selectable `TextBlock`s follow the Windows text size; section titles are Narrator level-2 headings; bullet glyphs are Raw; HTTPS addresses are `Hyperlink`s. Bullet labels are not bolded (optional in the spec). No WebView, no network.

## Tests

`Festival.Core.Tests/PrivacyPolicyTests.cs` (the real contract via a linked fixture: sections, required ids, link runs, malformed input); `SettingsPageTests` (Quick Links order). Live UIA check: dialog present, 11 level-2 headings, focus on `fst.privacy-policy.content` while open and back on the row after close.
