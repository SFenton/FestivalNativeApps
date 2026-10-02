# macOS host limits

> **What:** signing and GUI-automation constraints for the macOS app on this Mac. **Read when:** running macOS UI tests or claiming macOS evidence. In-process alternative: [hosted snapshots](../../testing/apple/hosted-snapshots.md).

- The macOS UI-test scheme uses local **ad-hoc signing for development only**; distribution signing needs separate approval.
- `xcrun automationmodetool status` reports Automation Mode **disabled, requiring user authentication**. The ad-hoc runner timed out enabling automation before running a test. **Do not enable or bypass this setting from an agent.**
- Claim no macOS GUI/accessibility pass until a signed `.xcresult` actually contains test results. SwiftPM does not measure `apple/Apps/macOS` coverage.
- **Version (issue #21):** Settings → App Version and the default About window read `CFBundleShortVersionString`/`CFBundleVersion`, plus `FSTGitSHA` in Settings, all stamped from a `macos/vYYMM.DD.NN` tag. `version-bump` creates macOS tags only while `FST_RELEASE_MACOS_ENABLED=true`, and [`macos-release.yml`](../../../.github/workflows/macos-release.yml) is still a scaffold, so no Mac build carries a bumped version yet ([release machine](../../workflow/release-machine.md#versions-notes-and-whats-new)).
