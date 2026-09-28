# Web reference captures (PWA)

> **What:** how to capture the real web app with deterministic fixtures for layout/state comparison. **Read when:** comparing a native screen with the web at the same viewport. Procedure: [screenshot-compare](../skills/screenshot-compare.md).

- Harness: `tools/visual/pages.spec.ts` + `tools/visual/playwright.config.mjs`, run from the sibling web repo with its existing Playwright install:
  `cd <FortniteFestivalWeb> && FST_VISUAL_OUT=<evidence-dir> node_modules/.bin/playwright test --config <FestivalNativeApps>/tools/visual/playwright.config.mjs --project=webkit-mobile --workers=1`
- Uses the PWA's strict scenario router, the original synthetic fixture songs/players, a loopback-only art server and an unreachable API proxy. Standard viewports: phone 390×844, tablet 820×1180 (portrait and landscape).
- Add a case per new page/control state; filter with `--grep '<test name>'`.
- Captures are structural references, **not** pixel parity; they stay in private evidence (never commit third-party art). A browser viewport is not Duo hardware, and the "tablet" project is still a WebKit phone descriptor at tablet width.
- Web first-run carousels (e.g. Filter Songs) may overlay pages; dismiss them before comparing unobstructed content.
