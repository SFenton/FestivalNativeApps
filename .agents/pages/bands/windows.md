# Bands without an ID — Windows notes

> **What:** what the Windows `/bands` route shows. **Read when:** changing `windows/Festival.App/Pages/BandsPage*`. Behavior: [spec.md](spec.md); iPhone reference: [ios.md](ios.md).

## Implemented

- `/bands` with no band ID shows the web `BandPage` error state (operator 2026-09-28, [windows-gaps](../../testing/pwa-reference/windows-gaps.md) row 3): page title **Band**, centred **Band not found** (heading level 2) and "This band link is missing an ID and cannot be resolved." (web `band.notFound` / `band.missingId` through `EmptyState`). No hub, no search: `/api/bands/search` can write server state on a GET ([service-safety](../../platforms/service-safety.md)). The page makes no service request.
- The message sits in a vertical `ScrollViewer` (centred while it fits, like the Search empty state), so large text in a short window scrolls rather than clips.
- Narrator: on load the page speaks "Band not found. This band link is missing an ID and cannot be resolved." (`ScreenReader.Announce` with `Announcement.Failure`, as `ServiceStatusView` does for errors); navigation alone reads only focus and the title.
- Back (title-bar button or Alt+Left) from a deep-linked `/bands` opens the Leaderboards section root.
- Bands are reached from a player's Bands list (`AppRoute.PlayerBands`) and Band Rankings. The Leaderboards overview's "Browse Bands" link to the old hub was removed; its band-ranking cards remain.

## IDs

`fst.bands.title` (heading 1), `fst.bands.screen` (the body `ScrollViewer`), `fst.bands.not-found` (heading text) and `fst.bands.not-found.message`. Put IDs on UIA-visible elements: before issue #211, `.screen` and `.not-found` sat on a `Grid` and a `StackPanel`, which have no automation peer. Journeys: `tools/windows/journeys/bands.json` → `bands-not-found` (state, then Back → Leaderboards); `a11y-keyboard.json` → `kb-bands-not-found-back` (Alt+Left) and `kb-bands-not-found-back-button` (Back focused + Enter); `a11y.json` → `bands`.

## Validation (issue #211, 2026-10-03)

Checked with the winui-design and winui-code-review skills, `a11y_matrix.py` (fixture, `fixture-player-1`) and the live public service (keyless default origin, anonymous, throwaway data dirs). The host's 3840×2160 display is natively at 300%, so the `wide` preset is clamped to 1280×672 epx there; 1440 epx was checked at display 100% and 150%. Axe.Windows reported 0 errors in every row.

| Configuration | Finding |
|---|---|
| Compact 500, medium 900, wide 1280/1440, snap-left, maximized | Pass. The title is top-left and the message centred in the content area; the body wraps at compact. Fixture and live. |
| Light / dark app mode | Same rendering, a deliberate deviation: the app is dark-only ([design/windows.md](../../design/windows.md#content-branded-fluent-tokens)). |
| High contrast: Aquatic, Desert, Dusk, Night sky | Pass: system window and text colours, no artwork. Desert and Night sky were also checked live. |
| Text 200% (compact, medium, wide) and 225% | Pass: the heading and message wrap. At the shortest window this host allows (500×360 epx) with 225% text, the message still fits; the `ScrollViewer` is a safeguard. The shell's notification badge digits overflow (shell, not Bands). |
| Display scale 100% / 150% | Pass, live, at compact and wide. |
| Animation effects off, transparency off | Pass (static page; only the shared background reacts). |
| Keyboard only | Tab: Back → menu → search → notifications → profile → navigation pane; no trap, no stop outside the window. The page has no focusable content. Alt+Left and Back + Enter both open Leaderboards (`kb-bands-not-found-*`, all three sizes). |
| Narrator / UIA | Title heading 1, "Band not found" heading 2, message text, all with IDs; the failure is announced on load. **Fixed:** `fst.bands.screen` and `.not-found` were missing from the UIA tree (set on panels), and nothing announced the failure. |

Deliberate deviations from winui-design: the empty state has no call-to-action, although the skill's layout review asks empty states to say "what the user can do". It mirrors the web state (operator decision: no hub), and Back plus the navigation pane are always present. Strings are hard-coded English, following the repo convention (no `.resw`). The WinUI analyzer package isn't referenced by the project, so its rule checks didn't run.
