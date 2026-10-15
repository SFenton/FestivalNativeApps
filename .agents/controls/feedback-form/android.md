# In-app feedback form: Android notes

> **What:** how Android builds the Report an Issue / Request a Feature form, its pickers, polling and tests. **Read when:** changing feedback on Android. Spec: [spec.md](spec.md); Windows: [windows.md](windows.md).

## Implementation

| Piece | Where |
|---|---|
| Domain | `core/feedback/Feedback.kt`: `FeedbackKind`, `FeedbackLimits`, `FeedbackCopy`, `FeedbackDraft` (validation, `withAttachments` limits and notice), `FeedbackSubmission` (wire parts, clipped diagnostics), `FeedbackJob`/`FeedbackJobState` (message, `isValidId`), `FeedbackException` (code/status → fixed copy, `Retry-After`) |
| Wire | `data/feedback/FestivalApiFeedback.kt`: `feedbackEnabled()` (`/api/features`), `submitFeedback()` (multipart via `MultipartFormBody.kt`, streams each `content://` URI after a size preflight), `feedbackStatus(id)`; `FeedbackWire` parsers |
| State | `presentation/feedback/FeedbackViewModel.kt`: phases Editing → Submitting → `Filing(job)`; a filed or received form closes and its result moves to `sent` (`FeedbackSent`: title, message), cleared by `dismissSent()` (#565); 2 s poll, 5 min deadline; `available` + `loadAvailability()` |
| UI | `ui/settings/FeedbackDialog.kt`: Material 3 **full-screen dialog** below 600 dp of available width (a 640 dp `shapes.extraLarge` card on wider windows), with the shared `FestivalModalHeader` (title, Submit, Close), `OutlinedTextField`s with `supportingText` helper lines, and `BackHandler` → discard `FestivalAlertDialog`. The result is a single-Done `FestivalAlertDialog` (no `dismissLabel`) that `FeedbackDialogHost` shows only once the form is gone. On a separating hinge the dialog keeps to one side (`festivalSheetHingeSide`, read from the activity window before the `Dialog` opens: inside the new dialog window the root width is still 0, so the hinge was ignored; issue #146, `FeedbackDialogHingeTest`) and decides compact vs centred from that side's width |
| Rows | `ui/settings/SettingsScreen.kt`: App Settings rows get an action only when `available` is true; a `LaunchedEffect` loads it on each visit |

## Pickers and opening

- **Photos & videos:** `ActivityResultContracts.PickMultipleVisualMedia(4)` (the Android Photo Picker, which needs no storage or media permission). **Files:** `OpenMultipleDocuments()` with `image/*` and `video/*` (SAF). No runtime permission is requested and the manifest declares none.
- Thumbnails are 88 dp tiles with a 48 dp remove target. TalkBack reads "Image, name, size" with an Open action. Tapping a tile sends `ACTION_VIEW` with `FLAG_GRANT_READ_URI_PERMISSION`; when no app can open it, the form shows "No app on this device can open …".

## Validation and design decisions (issue #143)

- **Submit is disabled while invalid** (spec): `canSubmit` requires `draft.problem == null`. A neutral line (`fst.settings.feedback.validation`, info icon plus `textSecondary` bodyMedium, no live region) sits above the fields and names the first problem, for example "Add a title after the prefix.". The red `.error` banner is reserved for send and filing failures. Before #143, Submit stayed enabled and a tap showed the problem as an error.
- **Busy view (owner, #634):** Submit fades the fields out (150 ms, `AccordionMotion.FADE_MS`) and then fades in a busy view, centred horizontally and vertically in the body under the header (`FeedbackBusySwap`/`FeedbackBusyView`). It is the app's `FestivalLoading` (36 dp white arc, named "Sending your issue"/"Sending your request") over a titleLarge bold title and a bodyLarge subtitle, the `FestivalEmptyState` typography. With media the title reads **Uploading Media** over a determinate white `LinearProgressIndicator` (≤ 280 dp, named "Upload progress"), which follows the bytes `MultipartFormBody` writes in whole-percent steps (`FeedbackViewModel.reportUpload`); a body of unknown length shows the indeterminate bar. Filing reads **Filing Issue**/**Filing Request** over "We’re filing your issue/request. Please wait while we upload it.". On the hand-off only the title, bar and subtitle fade out, then in (150 ms each); the spinner node stays and keeps spinning. A failure fades back to the fields with every value kept and the error banner scrolled into view.
  - **Agent decision (#634):** a form **without media** shows the Filing copy from Submit on. "Uploading Media" would be inaccurate for a few hundred bytes of text and would flash for a fraction of a second. With media the owner's two steps run in order.
  - **Agent decision (#634):** the header (title, disabled Submit, Close) stays above the busy view, so Close and its discard confirmation keep working while sending and Close needs no confirmation while filing (spec). The view is centred in the space under the header, not over it.
  - The hidden fields stay composed at alpha 0, outside TalkBack (`clearAndSetSemantics`) and touch (a pointer-consuming overlay), so their text, focus and scroll survive a failure. Reduce Motion (system or in-app, `LocalFestivalAccessibility`) snaps both swaps. The busy column scrolls when 200 % text makes it taller than the body.
  - This is the owner-approved variant [modal-shell](../../patterns/modal-shell.md) R16 of the app's "spinner, never with a subtitle" rule ([empty-error-states](../../patterns/empty-error-states.md) R6). Material 3's progress-indicator guidance allows both: a circular indicator for the ongoing work and a linear determinate one for "the progress of a process with a known duration". Before #634 a 24 dp spinner and "Sending your report…"/"Filing your report on GitHub…" sat in a row above the still-visible, disabled fields, and the upload had no progress.
- **Result (owner, #565):** a filed or received form closes by itself, then a basic `AlertDialog` ("Report Sent" / "Request Sent", the outcome text, one Done) opens over Settings. The web keeps its modal open with the success text; the owner asked native forms to close first ("Modal closes automatically and we get the alert"), and an alert rather than a Snackbar keeps the owner's alert and matches Apple. Failures stay in the form.
- **Material 3 deviations, deliberate:**
  - The header is the repo's `FestivalModalHeader`: title leading, then actions, then Close trailing. This matches Apple and Windows. M3's full-screen dialog instead puts Close leading and the action trailing.
  - Colours come from the dark-only brand palette rather than dynamic colour, so the form stays dark when the system is in light mode.
  - The disabled Submit's text contrast (ATF estimate 2.91:1) is exempt: WCAG 1.4.3 excludes inactive controls.
- **Accessibility (TalkBack order on FST_Phone):**
  - Editing: title (heading), Submit, Close, then the validation reason or error banner, then each field (value, label, helper), the Attachments heading, the helper and Attach Media.
  - Sending and filing (#634): title, Submit (disabled), Close, the spinner ("Sending your issue"), the busy title (a heading and a polite live region, so each step's title is announced), then the upload bar ("Upload progress" with its percentage) or the sentence. No field is read.
  - Discard confirmation: title, message, Keep Editing, Discard.
  - Sent (#565): the form has closed; the result alert reads "Report Sent", the outcome text, then Done. No Close, Submit or Cancel. Back or Done dismisses it and the form does not come back.
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

`fst.settings.feedback.bug|feature` (rows), `.dialog`, `.title`, `.close`, `.submit`, `.field.title|description|repro|expected`, `.attach`, `.attach.media`, `.attach.files`, `.attachments`, `.attachment`, `.attachment.remove`, `.attachments.notice`, `.progress` (the busy view), `.progress.spinner`, `.progress.title`, `.progress.bar`, `.progress.subtitle`, `.validation`, `.error`, `.sent` (the result alert), `.sent.message`, `.done` (its single action), `.discard.dialog|confirm|cancel`.

## Tests

- `core/feedback/FeedbackTest.kt`; `data/feedback/FeedbackDataTest.kt` (FakeTransport: multipart body and its write progress, codes, `Retry-After`, status parsing, features flag, no key/profile headers); `presentation/feedback/FeedbackViewModelTest.kt` (virtual-time polling, deadline, failed filing, unknown outcome, close while filing, availability, upload progress and the busy status per step).
- `settings/FeedbackUiTest.kt` (Robolectric, 411 dp) covers every reachable state:
  - `unavailable` (rows hidden without the flag) and `editing-empty` (a clean form closes without asking).
  - `invalid`: Submit disabled, the validation text and no error banner.
  - `editing-dirty` and `discard-confirm`, both while editing and while sending.
  - `sending`: the fields leave the tree, Submit is disabled and the busy view reads Filing Issue with the named spinner, centred under the header (#634).
  - `filing`: the job is polled from processing to submitted.
  - `sent`: both "filed as issue #N" and "received" when the status can't be read; each checks the form, Close, Submit and progress are gone and the alert has one Done (`assertResultAlertOnly`). `backClosesTheResultAlert` checks one covering modal and that Back closes the alert without reopening the form.
  - `error`: a 503, and a failed filing that keeps the input.
  - `attachments`: an `ActivityResultRegistry` override plus a fake `ContentProvider` give image and video tiles, the type and over-limit notices, Remove, and Attach disabled at 4.
  - `settings/FeedbackExpandedUiTest.kt` (1280 dp) checks the centred 640 dp card.
  - `ui/settings/FeedbackBusyViewTest.kt` (#634): with media, Uploading Media over a bar that follows the upload, centring, the hand-off to Filing Request with the spinner kept, the old title held during the 150 ms fade-out, and an instant swap under Reduce Motion.
  - `FakeTransport.standard()` does not serve `/api/features`, so add it per test.
- `androidTest/journeys/FeedbackFormJourneyTest.kt` (device, ATF on every interaction, TalkBack order per state): invalid → dirty → sending → discard while sending → filing → sent (the form closes, then the result alert reads title → message → Done with a 48 dp Done and no Close/Submit/Cancel), and a feature request with a 503 error. #634 adds the busy reading order (spinner → title → sentence, no field) with ATF in the sending and filing states; `mediaUploadReadsUploadingThenFilingAndPassesChecks` (`@DeviceCi`, API 29+: a test `ActivityResultRegistryOwner` answers Attach Media with a PNG the test puts in MediaStore and deletes, and the fixture POST writes the real multipart body into a sink that holds halfway) asserts spinner → Uploading Media (heading) → "Upload progress, N percent" with a published range strictly between 0 and 1, no field, ATF, then the hand-off to Filing Issue with the same spinner node; and `busyViewWrapsCentredAtLargeText` (200 % text: the sentence wraps inside the view, the spinner stays centred under the header, Close keeps 48 dp). Run `device.py test com.festivalscoretracker.android.journeys.FeedbackFormJourneyTest --avd FST_Phone`, and also `--avd FST_Book_Fold --posture half`.
- Open at 200 % text (found in issue #528, not yet fixed): once a field has been scrolled up under the header, ATF measures Submit at 47 dp. The drawn button stays 53 dp. Compose subtracts the scrolled field's semantics bounds, which reach up behind the header, from the earlier header nodes. `zIndex(1f)` on `FestivalModalHeader` restores the bounds but makes TalkBack read the header after the form, so a fix must keep the header first in traversal (for example a traversal index). Add a 200 % pass to this journey with that fix.
- Coverage (2026-10-04, `fst_android.py build --tests --coverage`): logic 98.0%, UI 96.4% overall. `FeedbackDialog.kt` rose from 62.2% to 93.2%; only the real `ACTION_VIEW` launch and the system pickers' own UI stay device-only.
