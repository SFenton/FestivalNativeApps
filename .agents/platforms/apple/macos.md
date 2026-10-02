# macOS host limits

> **What:** signing and GUI-automation constraints for the macOS app on this Mac. **Read when:** running macOS UI tests or claiming macOS evidence. In-process alternative: [hosted snapshots](../../testing/apple/hosted-snapshots.md).

- The macOS UI-test scheme uses local **ad-hoc signing for development only**; distribution signing needs separate approval.
- `xcrun automationmodetool status` reports Automation Mode **disabled, requiring user authentication**. The ad-hoc runner timed out enabling automation before running a test. **Do not enable or bypass this setting from an agent.**
- Claim no macOS GUI/accessibility pass until a signed `.xcresult` actually contains test results. SwiftPM does not measure `apple/Apps/macOS` coverage.
