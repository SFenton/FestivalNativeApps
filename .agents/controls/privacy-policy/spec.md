# Privacy Policy (`fst.privacy-policy.*`): spec

> **What:** platform-neutral behavior of Settings → **Privacy Policy**: the canonical policy text, its entry row, modal presentation, direct web URL and test matrix (issue #98). **Read when:** changing the policy wording or its entry/presentation on any platform. Platform notes: [ios.md](ios.md), [ipados.md](ipados.md), [duo.md](duo.md), [macos.md](macos.md), [android.md](android.md), [windows.md](windows.md).

Source of truth: [`contracts/privacy-policy.json`](../../../contracts/privacy-policy.json). The pinned web revision has no privacy policy; this contract is native-first and the web reads the same text.

## Canonical text

- **Every platform renders the contract's text verbatim**: `title`, `effectiveDateText`, then each `sections[]` entry's `title` and `blocks[]` in order. No platform may reword, add or drop a sentence; change the JSON and every platform's copy in the same change.
- Block kinds (`schema` 1): `paragraph` (`text`) and `bullets` (`items[]`, one string per bullet). Presentation-only styling is allowed when the words stay identical: a bullet's short leading label before `": "` may be bold, and `https://` addresses in the text should be tappable links that open the system browser.
- Each platform keeps a native copy (no runtime fetch, works before the service answers) plus a unit test that decodes the JSON and asserts its copy is identical. Apple: `FestivalCore/PrivacyPolicy.swift` + `PrivacyPolicyTests`. Android: `assets/privacy-policy.json` (byte-identical copy) + `PrivacyPolicyTest`. Windows: the csproj links the contract file itself + `PrivacyPolicyTests`.
- Required sections (industry-standard, App Review 5.1.1(i)): `information-collected`, `how-used`, `third-parties` (Epic Games, Cloudflare, GitHub, app stores), `retention`, `your-rights`, `contact` (last); the contract also has `overview`, `public-game-data`, `children`, `security` and `changes`, plus the effective date. Tests assert the required `id`s exist.
- Bump `effectiveDate`/`effectiveDateText` whenever the wording changes. Claims must stay true of the shipped clients and service: re-check the policy when adding analytics, accounts, a new third-party host, persisted server data or a new user-initiated write ([service-safety](../../platforms/service-safety.md)).
- No public contact email exists; contact goes through the public GitHub issues page and in-app Report an Issue, with a note not to post private details. TODO(orchestrator): replace with a private contact address if one is created.

## Entry and presentation

| Surface | Entry | Presentation | Dismiss |
|---|---|---|---|
| Web | Settings link row next to Licenses | Modal over Settings; `/settings/privacy` opens the same modal on direct visit or refresh | Close button, Escape, backdrop |
| Native | Settings row (title, description, chevron) after Licenses | Modal sheet titled "Privacy Policy" | Platform-standard (see platform files) |

- The row reads "Privacy Policy" with the description "How Festival Score Tracker handles your information." It opens a modal rather than pushing a page, so it never stacks over another modal.
- Content scrolls; body text uses the platform's scalable text style (Dynamic Type / font scale); section headings are exposed as accessibility headings; text is selectable where the platform supports it; content stays inside safe areas.
- No network calls; the contact address opens the system browser.

## States

| State | Acceptance |
|---|---|
| settings-row | Row visible in Settings (and Mac Settings › About) with label, description and chevron |
| presented | Modal shows the title, effective date and every section |
| scrolled | Content scrolls to the Contact section and its issues address |
| dismissed | Dismiss returns to Settings with focus on the row |
| large-text | Largest accessibility text size wraps without clipping or truncation |

## Test matrix

Unit: native copy equals the JSON; required sections present; no empty text; the contact address is a link; styling never changes the words. UI: row opens the modal; dismiss returns to Settings; hosted render at default and accessibility text sizes.
