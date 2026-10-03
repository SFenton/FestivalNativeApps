# Privacy Policy — Mac notes

> **What:** how the Privacy Policy differs on macOS from the [iPhone design](ios.md). **Read when:** changing the policy row or sheet on the Mac. Spec: [spec.md](spec.md).

| Aspect | Mac |
|---|---|
| Entry | Settings window › **About** pane, after Licenses (`fst.settings.privacy-policy`) |
| Surface | Window-modal sheet on the Settings window. `PrivacyPolicySheet` sets a macOS frame (min 480×420, ideal 620×560) because a scroll view has no ideal size. HIG Sheets (macOS): "Present a sheet in a reasonable default size" |
| Dismiss | The shared `FestivalModal` Close in the sheet's toolbar. HIG Modality: "macOS/tvOS use a button in the main content view" |
| Text | macOS has no Dynamic Type ("macOS doesn't support Dynamic Type", HIG Typography); text uses the system text styles and is selectable |
