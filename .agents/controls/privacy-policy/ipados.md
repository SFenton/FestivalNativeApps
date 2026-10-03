# Privacy Policy — iPad notes

> **What:** how the Privacy Policy sheet differs on iPadOS from the [iPhone design](ios.md). **Read when:** changing the policy row or sheet on iPad. Spec: [spec.md](spec.md).

| Aspect | iPad |
|---|---|
| Entry | Same Settings row after Licenses (`fst.settings.privacy-policy`), in Settings' readable centred column |
| Surface | `festivalSheet(.large)` applies `presentationSizing(.form)` at regular width: a centred form sheet over the dimmed Settings page. HIG Sheets (iOS, iPadOS): "Prefer page or form sheet styles in an iPadOS app" |
| Dismiss | System Close in the sheet's navigation bar; swipe down |
| Narrow windows | Compact-width windows (Slide Over, narrow splits) get the iPhone-style sheet |
