# Privacy Policy — iPhone Duo notes

> **What:** how the Privacy Policy sheet behaves on iPhone Duo compared with the [iPhone design](ios.md). **Read when:** changing the policy row or sheet on Duo. Spec: [spec.md](spec.md).

| Pose | Behavior |
|---|---|
| Folded (outer display) | Identical to iPhone: full-height sheet, system Close, swipe down |
| Unfolded (regular width) | Centred form sheet like iPad (`presentationSizing(.form)` via `festivalSheet`). HIG iPhone Duo: "Alerts, context menus, sheets, and standard split views adapt to the fold", so no custom fold handling is needed; the 680 pt text column stays inside the form sheet |
