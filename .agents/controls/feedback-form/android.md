# In-app feedback form: Android notes

> **What:** how Android builds the Report an Issue / Request a Feature form, its pickers, polling and tests. **Read when:** changing feedback on Android. Spec: [spec.md](spec.md); Windows: [windows.md](windows.md).

## Implementation

| Piece | Where |
|---|---|
| Domain | `core/feedback/Feedback.kt`: `FeedbackKind`, `FeedbackLimits`, `FeedbackCopy`, `FeedbackDraft` (validation, `withAttachments` limits and notice), `FeedbackSubmission` (wire parts, clipped diagnostics), `FeedbackJob`/`FeedbackJobState` (message, `isValidId`), `FeedbackException` (code/status → fixed copy, `Retry-After`) |
| Wire | `data/feedback/FestivalApiFeedback.kt`: `feedbackEnabled()` (`/api/features`), `submitFeedback()` (multipart via `MultipartFormBody.kt`, streams each `content://` URI after a size preflight), `feedbackStatus(id)`; `FeedbackWire` parsers |
| State | `presentation/feedback/FeedbackViewModel.kt`: phases Editing → Submitting → `Filing(job)` → `Sent(job)`; 2 s poll, 5 min deadline; `available` + `loadAvailability()` |
| UI | `ui/settings/FeedbackDialog.kt`: Material 3 **full-screen dialog** below 600 dp of available width (a 640 dp `shapes.extraLarge` card on wider windows), with the shared `FestivalModalHeader` (title, Submit, Close), `OutlinedTextField`s with `supportingText` helper lines, and `BackHandler` → discard `FestivalAlertDialog`. On a separating hinge the dialog keeps to one side (`festivalSheetHingeSide`) and decides compact vs centred from that side's width |
| Rows | `ui/settings/SettingsScreen.kt`: App Settings rows get an action only when `available` is true; a `LaunchedEffect` loads it on each visit |

## Pickers and opening

- **Photos & videos:** `ActivityResultContracts.PickMultipleVisualMedia(4)` (the Android Photo Picker, which needs no storage or media permission). **Files:** `OpenMultipleDocuments()` with `image/*` and `video/*` (SAF). No runtime permission is requested and the manifest declares none.
- Thumbnails are 88 dp tiles with a 48 dp remove target. TalkBack reads "Image, name, size" with an Open action. Tapping a tile sends `ACTION_VIEW` with `FLAG_GRANT_READ_URI_PERMISSION`; when no app can open it, the form shows "No app on this device can open …".

## Validation and design decisions (issue #143)

- **Submit is disabled while invalid** (spec): `canSubmit` requires `draft.problem == null`. A neutral line (`fst.settings.feedback.validation`, info icon plus `textSecondary` bodyMedium, no live region) sits above the fields and names the first problem, for example "Add a title after the prefix.". The red `.error` banner is reserved for send and filing failures. Before #143, Submit stayed enabled and a tap showed the problem as an error.
- **Progress** uses the app's `FestivalLoading` (24 dp, white arc) beside the status text, per [design/android.md](../../design/android.md) (one loading indicator, never the theme's blue primary). It is not a `LinearProgressIndicator`. The indicator's semantics are cleared, so TalkBack makes a single polite live-region stop: "Sending your report…" / "Filing your report on GitHub…". With animator scale 0 the arc is static and the text still changes.
- **Material 3 deviations, deliberate:**
  - The header is the repo's `FestivalModalHeader`: title leading, then actions, then Close trailing. This matches Apple and Windows. M3's full-screen dialog instead puts Close leading and the action trailing.
  - Colours come from the dark-only brand palette rather than dynamic colour, so the form stays dark when the system is in light mode.
  - The disabled Submit's text contrast (ATF estimate 2.91:1) is exempt: WCAG 1.4.3 excludes inactive controls.
- **Accessibility (TalkBack order on FST_Phone):**
  - Editing: title (heading), Submit, Close, then the validation reason or error banner, then each field (value, label, helper), the Attachments heading, the helper and Attach Media.
  - Discard confirmation: title, message, Keep Editing, Discard.
  - Sent: title, Close, then the result.
  - Every target is at least 48 dp: Submit is 69×48 dp, Close is 48×48 dp, and the attachment remove target is 48 dp around a 24 dp glyph.
- **Hinge:** on a separating hinge the dialog keeps to the start-side display area (left pane in book posture, lower pane in tabletop). The material-3 skill's layout guidance says: "Never place interactive content or critical information across the hinge area".
- ATF's missing-label finding on a text field scrolled to a sliver (the label child is clipped) is a harness artifact. `JourneyHarness` drops it once the field is seen composed with a label.

## Validation matrix (2026-10-04, #143)

Each configuration was driven through invalid → dirty → discard → sending → sent, then error, against `tools/mock_service.py`, because the live service reports `feedback:false`. Each run used animator scale 0, a font-scale 2.0 pass, and portrait plus landscape. Every configuration passed.

| AVD / posture | Layout | Findings |
|---|---|---|
| FST_Phone (portrait) | Full screen | All states correct. At font scale 2.0 the fields wrap and scroll without clipping. |
| FST_Phone (landscape) | Centred card | Card of at most 640 dp. It scrolls at font scale 2.0. |
| FST_Tablet | Centred card | All states correct in both orientations. |
| FST_Resizable compact / medium (800 dp) / expanded | Full screen / card / card | Switches at a width of 600 dp. |
| FST_Book_Fold folded / unfolded | Full screen / card | Folded matches the phone. |
| FST_Book_Fold half | Start pane | Left pane in portrait and lower pane in landscape. It never crosses the hinge. |
| FST_Passport_Fold folded / unfolded | Full screen / card | Folded landscape at font scale 2.0 leaves a short viewport, but it scrolls. |
| FST_TriFold | Centred card | All states correct. |

The app is dark-only, so system dark mode on or off renders the same. On the live service (FST_Phone, FST_Tablet) the Report an Issue and Request a Feature rows stay hidden (`unavailable`).

## Test IDs

`fst.settings.feedback.bug|feature` (rows), `.dialog`, `.title`, `.close`, `.submit`, `.field.title|description|repro|expected`, `.attach`, `.attach.media`, `.attach.files`, `.attachments`, `.attachment`, `.attachment.remove`, `.attachments.notice`, `.progress`, `.validation`, `.error`, `.sent`, `.done`, `.discard.dialog|confirm|cancel`.

## Tests

- `core/feedback/FeedbackTest.kt`; `data/feedback/FeedbackDataTest.kt` (FakeTransport: multipart body, codes, `Retry-After`, status parsing, features flag, no key/profile headers); `presentation/feedback/FeedbackViewModelTest.kt` (virtual-time polling, deadline, failed filing, unknown outcome, close while filing, availability).
- `settings/FeedbackUiTest.kt` (Robolectric, 411 dp) covers every reachable state:
  - `unavailable` (rows hidden without the flag) and `editing-empty` (a clean form closes without asking).
  - `invalid`: Submit disabled, the validation text and no error banner.
  - `editing-dirty` and `discard-confirm`, both while editing and while sending.
  - `sending`: fields, Attach and Submit disabled.
  - `filing`: the job is polled from processing to submitted.
  - `sent`: both "filed as issue #N" and "received" when the status can't be read.
  - `error`: a 503, and a failed filing that keeps the input.
  - `attachments`: an `ActivityResultRegistry` override plus a fake `ContentProvider` give image and video tiles, the type and over-limit notices, Remove, and Attach disabled at 4.
  - `settings/FeedbackExpandedUiTest.kt` (1280 dp) checks the centred 640 dp card.
  - `FakeTransport.standard()` does not serve `/api/features`, so add it per test.
- `androidTest/journeys/FeedbackFormJourneyTest.kt` (device, ATF on every interaction, TalkBack order per state): invalid → dirty → sending → discard while sending → filing → sent, and a feature request with a 503 error. Run `device.py test com.festivalscoretracker.android.journeys.FeedbackFormJourneyTest --avd FST_Phone`, and also `--avd FST_Book_Fold --posture half`.
- Coverage (2026-10-04, `fst_android.py build --tests --coverage`): logic 98.0%, UI 96.4% overall. `FeedbackDialog.kt` rose from 62.2% to 93.2%; only the real `ACTION_VIEW` launch and the system pickers' own UI stay device-only.
