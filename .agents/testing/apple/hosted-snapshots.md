# Native hosted snapshots (macOS host)

> **What:** rendering real AppKit-backed SwiftUI states inside `swift test`, without a simulator or the Mac app GUI. **Read when:** adding a per-state UI snapshot test (UX-test phase) or measuring host UX coverage.

Helpers: `apple/Tests/FestivalUITests/NativeHostedSnapshot.swift` (`nativeHostedView`, `nativeHostedImage`, `nativeHostedWindow`, `nativeHostedPNG`).

## Recipe

1. Build a `FestivalSession` over an **in-memory transport** that rejects writes, privileged keys, selected-profile headers, wrong routes and mismatched publication pins (a throwing factory is fine for error states; never fall through to production). Use a separate `UserDefaults` suite via `.defaultAppStorage` and clean it up.
2. Apply `.preferredColorScheme(.dark)` and the app tint; render with `nativeHostedView` / `nativeHostedImage`. Bitmaps are at backing scale (2×). AppKit/ColorSync shifts token RGB slightly: assert geometry and painted foreground/selected state, not exact token bytes.
3. Lazy `List` may paint **no rows** in an unattached host even after successful GETs: attach only that host to `nativeHostedWindow`, assert it never becomes visible, and keep the window alive through capture. A standalone `Form` (e.g. Songs Sort) is the opposite: attaching a window makes pickers look inactive — render its content surface bare.
4. Optional private captures: `FST_PROFILE_RENDER_OUT`, `FST_PATH_RENDER_OUT` or `FST_SHOP_RENDER_OUT` pointing at an **existing private** directory. Never commit screenshots, service payloads or game artwork.
5. AppKit `NSTextField` accepts a typed `controlTextDidChange` to drive the real 250 ms search task; `NSSegmentedControl` can switch scopes. SwiftUI result buttons expose no `NSButton` children, so viewed/select/focus flows still need device tests.

## Pitfalls

- **Never use `ImageRenderer` output as evidence**: it paints yellow crossed placeholders for native `Form`, `Picker`, `TextField` and `List`; a synchronous render of a `NavigationStack` with a prefilled path paints only the brand surface. Use a real offscreen `NSHostingView` and let navigation lay out. (A genuinely gold Shop badge is not a placeholder.)
- Artwork tests time retries from the view's start and enforce the five-request pool even when a busy host misses the transient three-request observation.
- Host pixels do not increase device coverage and are not macOS GUI, VoiceOver or focus evidence.

Verified selector (15 cases):

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path apple --filter 'profileSheet|profileAction|pathSheet|shopScreen|songsSortSheet|selectedSongsRows|songsListPaints|selectedScoreSummary|invalidMetadataFields|profileBandScope' --quiet
```
