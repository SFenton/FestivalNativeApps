# Artwork background (`fst.shell.artwork-background`)

Source: `FortniteFestivalWeb/src/components/shell/AnimatedBackground.tsx:7-255` and `FortniteFestivalWeb/src/components/page/BackgroundImage.tsx:16-57`. Songs and Settings rotate at most 100 shuffled album covers; Detail and solo Leaderboard use a static, dimmed song cover. Changing to a new album-art image takes 1,000 ms, each image is displayed about 5,000 ms, and a slow 6,000 ms zoom/pan uses one of ten presets (scale up to 1.18, translation up to 18 logical units). Apply a black dim layer at 0.7 alpha behind readable content.

States to reproduce: no art, animated, reduced motion (one static image), data saving (no images or overlay), not visible (timer/animation paused), and static detail art. Animation depends on system accessibility and in-app additive overrides. Use platform-appropriate data-saver, visibility and low-power signals; do not download 100 images at once, cache artwork only in the active process, predecode to displayed dimensions, and measure scrolling/frame delivery.

Native implementations, screenshots, image provenance/rights and all device-state tests are **pending**. The mock service may supply synthetic, original fixture artwork; do not bundle copyrighted album art or use a live endpoint for automation.
