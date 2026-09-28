# Service status — Android notes

> **What:** Compose implementation of the shared failed-read states. **Read when:** showing a failed read on Android. Spec: [spec.md](spec.md).

- `ServiceIssue.from(error)` (core) + `RetryingLoader` (presentation): scrape freeze counts down from `Retry-After` with `ServiceRetryBackoff` (30→60→…→300 s) and retries itself; other issues wait for Retry. A newer load cancels an older one.
- `ServiceStatusView` (full page, polite live region, `fst.service-status.title|countdown|retry`) and `ServiceStatusInline` (`fst.service-status.inline`, no live region). `FST_DEBUG_FORCE_FREEZE=1` freezes each API path once.
- Open: Reduce Motion has no pulsing symbol to remove yet; TalkBack announcement not verified on device.
