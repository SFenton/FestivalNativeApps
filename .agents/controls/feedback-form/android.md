# In-app feedback form: Android notes

> **What:** how Android builds the Report an Issue / Request a Feature form, its pickers, polling and tests. **Read when:** changing feedback on Android. Spec: [spec.md](spec.md); Windows: [windows.md](windows.md).

## Implementation

| Piece | Where |
|---|---|
| Domain | `core/feedback/Feedback.kt`: `FeedbackKind`, `FeedbackLimits`, `FeedbackCopy`, `FeedbackDraft` (validation, `withAttachments` limits and notice), `FeedbackSubmission` (wire parts, clipped diagnostics), `FeedbackJob`/`FeedbackJobState` (message, `isValidId`), `FeedbackException` (code/status → fixed copy, `Retry-After`) |
| Wire | `data/feedback/FestivalApiFeedback.kt`: `feedbackEnabled()` (`/api/features`), `submitFeedback()` (multipart via `MultipartFormBody.kt`, streams each `content://` URI after a size preflight), `feedbackStatus(id)`; `FeedbackWire` parsers |
| State | `presentation/feedback/FeedbackViewModel.kt`: phases Editing → Submitting → `Filing(job)` → `Sent(job)`; 2 s poll, 5 min deadline; `available` + `loadAvailability()` |
| UI | `ui/settings/FeedbackDialog.kt`: Material 3 **full-screen dialog** on compact widths (a 640 dp card on wider windows) with a top bar (Close, title, Submit), `OutlinedTextField`s with `supportingText` helper lines, and `BackHandler` → discard `FestivalAlertDialog` |
| Rows | `ui/settings/SettingsScreen.kt`: App Settings rows get an action only when `available` is true; a `LaunchedEffect` loads it on each visit |

## Pickers and opening

- **Photos & videos:** `ActivityResultContracts.PickMultipleVisualMedia(4)` (the Android Photo Picker, which needs no storage or media permission). **Files:** `OpenMultipleDocuments()` with `image/*` and `video/*` (SAF). No runtime permission is requested and the manifest declares none.
- Thumbnails are 88 dp tiles with a 48 dp remove target. TalkBack reads "Image, name, size" with an Open action. Tapping a tile sends `ACTION_VIEW` with `FLAG_GRANT_READ_URI_PERMISSION`; when no app can open it, the form shows "No app on this device can open …".

## Test IDs

`fst.settings.feedback.bug|feature` (rows), `.dialog`, `.title`, `.close`, `.submit`, `.field.title|description|repro|expected`, `.attach`, `.attach.media`, `.attach.files`, `.attachments`, `.attachment`, `.attachment.remove`, `.attachments.notice`, `.progress`, `.error`, `.sent`, `.done`, `.discard.dialog|confirm|cancel`.

## Tests

- `core/feedback/FeedbackTest.kt`; `data/feedback/FeedbackDataTest.kt` (FakeTransport: multipart body, codes, `Retry-After`, status parsing, features flag, no key/profile headers); `presentation/feedback/FeedbackViewModelTest.kt` (virtual-time polling, deadline, failed filing, unknown outcome, close while filing, availability).
- `settings/FeedbackUiTest.kt` (Robolectric): rows hidden without the flag; bug form → 202 → poll → "filed as issue #42"; feature form errors and discard confirmation. `FakeTransport.standard()` does not serve `/api/features`, so add it per test.
- Coverage (2026-10-02, `fst_android.py build --tests --coverage`): logic 98.0%, UI 94.1% overall. `FeedbackDialog.kt` alone is 62.2%: the picker and `ACTION_VIEW` paths need a device.
