# licenses (`/settings/licenses`) — spec

> **What:** platform-neutral behavior of the Licenses page. **Read when:** adding or changing a dependency or bundled-asset acknowledgement on any platform. Platform notes: [ios.md](ios.md).

Source: `FortniteFestivalWeb/src/pages/settings/LicensesPage.tsx:27-158`, generated manifest `FortniteFestivalWeb/src/generated/licenseManifest.ts` (built by `tools/generate-license-manifest.mjs`, not hand-edited).

## Behavior

- A single scrollable list of every entry in the generated manifest (npm + NuGet, including devDependencies), each row showing name, ecosystem + version, and a license-type badge.
- Tapping a row opens a modal with the package's full license text (verbatim, from a small fixed set of full license bodies keyed by SPDX-like identifier) and, when known, its package/repository URL.
- Closing the modal returns focus to the triggering row (`ModalShell`'s standard focus-return behavior).
- No network calls; the manifest is a static generated file bundled at build time.

## Platform note

Each platform ships different code, so each platform's Licenses page must enumerate **that platform's own actual dependencies**, not re-export the web's npm/NuGet list. A platform with no third-party dependencies should say so explicitly rather than importing an irrelevant manifest.

## Test matrix

Row tap opens the correct entry's text; empty-dependency state (a platform/build with zero third-party packages) renders without error; modal dismissal returns focus/VoiceOver to the originating row.
