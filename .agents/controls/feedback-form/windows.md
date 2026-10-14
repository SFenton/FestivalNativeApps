# In-app feedback form: Windows notes

> **What:** how Windows builds the Report an Issue / Request a Feature dialog, its picker, polling and tests. **Read when:** changing feedback on Windows. Spec: [spec.md](spec.md); Android: [android.md](android.md).

## Implementation

| Piece | Where |
|---|---|
| Domain | `Festival.Core/Domain/Feedback.cs`: kinds, limits, copy, draft validation and attachment limits, submission wire parts, `FeedbackJob`/`FeedbackJobState`, `FeedbackException` (code/status → fixed copy, `Retry-After`) |
| Wire | `Festival.Core/Data/FestivalApiClient.Feedback.cs`: `GetFeedbackEnabledAsync` (`/api/features`), `SubmitFeedbackAsync` (multipart, streamed files; an optional `IProgress<double>` reports the bytes sent through `UploadProgressContent`, #634), `GetFeedbackStatusAsync` (validated 32-hex ID) |
| State | `Festival.Core/ViewModels/FeedbackFormViewModel.cs`: submit → filing poll (`PollInterval` 2 s, `PollTimeout` 5 min), fixed outcome text, failed filing returns to editing. `SettingsViewModel.FeedbackAvailable` gates the rows |
| UI | `Festival.App/Controls/FeedbackDialog.cs`: Fluent `ContentDialog` (max width 640) with Submit/Cancel and headed `TextBox`es whose `Description` holds the helper text as a word-wrapping `TextBlock` (a plain string renders as one unwrapped line and clipped at compact and 200% text; issue #239), inside its own `ScrollViewer` (the dialog's scroller never scrolls vertically). Submit fades the fields out and a centred busy stage in (#634, below). Discard confirmation is an inline warning `InfoBar` with Discard / Keep Editing, because a `ContentDialog` cannot open a second one |
| Rows | `Festival.App/Pages/SettingsPage.xaml`: App Settings rows bound to `FeedbackAvailable` |

## Picker and opening

- `Microsoft.Windows.Storage.Pickers.FileOpenPicker` (Windows App SDK, window-ID based), multi-select, filtered to `FeedbackMedia.Extensions` (images and videos). No capability is required.
- Thumbnail buttons open the file with `Windows.System.Launcher.LaunchFileAsync` (the system Photos or Media Player app). Each has a Narrator name and a separate remove button.

## Test IDs

`fst.settings.feedback.bug|feature` (rows), `.title`, `.description`, `.repro`, `.expected`, `.attachments`, `.attachment`, `.attachment.remove`, `.attach`, `.busy` (the `ProgressRing`, read "Busy Sending your issue, ProgressRing": WinUI prefixes "Busy" with no separator), `.status` (the centred title/bar/subtitle stack), `.progress` (the busy title), `.progress.bar` (the upload bar), `.progress.subtitle` (the filing sentence), `.sent`, `.error`, `.discard`, `.keep-editing`, `.discard-confirm`, `.scroller`, `.validation` (why Submit is disabled), `.cancel`; dialogs `fst.settings.feedback.bug|feature.dialog`.

## Behavior notes (issue #236)

- **Submit availability:** `FeedbackFormViewModel.CanSubmit` is false until the draft is valid; `ValidationMessage` names the first unmet rule ("Add a title after the prefix.", "Add a description.", "Shorten the text and try again."). The dialog disables Submit and shows that reason in a caption pinned above the buttons, outside the scroller, so it stays next to Submit. Narrator hears the reason when it changes, not on every keystroke.
- **Focus:** Cancel on a dirty form opens the discard bar and focuses **Keep Editing** once the InfoBar's buttons have loaded (`FocusWhenLoaded`, Low priority). Keep Editing returns focus to the title. After picking files, focus moves to Attach Media, or to the last tile at the 4-file limit, where Attach Media is disabled. Removing a tile focuses Attach Media.
- **Announcements:** WinUI live regions alone aren't spoken, so each new busy title (once per step), sent and the skipped-files notice go through `ScreenReader.Announce`. The error InfoBar sets `Message` before `IsOpen` because its open notification reads the text as it is at that moment.
- **Wrapping:** field headers (issue #236) and helper text (issue #239) are word-wrapping `TextBlock`s. A string `Header`/`Description` doesn't wrap and was cut mid-sentence at compact width and at 200% text.
- **Contrast:** the tile play and remove badges use theme brushes (`SolidBackgroundFillColorBaseBrush`, `ControlStrokeColorDefaultBrush`, `TextFillColorPrimaryBrush`), not fixed black and white.

## Verification

- `Festival.Core.Tests/FeedbackTests.cs` and `SettingsServiceInfoTests.cs` (availability). `tools/windows/test.ps1 -Coverage` on 2026-10-02: 1423 passed, 98.85% line coverage.
- End to end against a loopback stub (`--base-url=http://127.0.0.1:<port>/`): rows appear with the flag, the POST carries every field, the dialog polls three times, then shows "Thanks! Your report was filed as issue #N." Against production the rows stay hidden while `/api/features` lacks `feedback: true`.

## Validation (issue #236, 2026-10-05)

Production `GET /api/features` answers `feedback: false`, so on the live service only `unavailable` is reachable: Settings shows no Report an Issue / Request a Feature rows. All other states run on `tools/windows/feedback_fixture.py`; no feedback was ever sent to production.

Tests:
- Journeys: `python tools/windows/journeys/feedback.py --preset <size>` (`unavailable`, `validation`, `submit`, `error`). These cover every state with UIA patterns only, plus the fixture's POST/status log. 4/4 pass at compact, medium, wide, maximized and snapped left. The snapped-left `error` journey once lost its window while queued behind another lane's desktop lock and passed on the re-run.
- Matrix pages: `tools/windows/journeys/a11y-feedback.json` (one page per state, Axe scan). 60/60 pass with 0 errors at compact, medium, wide, maximized and both snaps. With `--mode`: Desert (compact, wide) 20/20, Night sky, text 200% (compact, wide), display 100% and 150%, and light/dark theme at medium.
- Unit tests: `FeedbackTests.Form_SubmitDisabledWithInlineReasonUntilValid` and the existing feedback suite. `test.ps1 -Coverage`: logic 98.9%, UX 98.0%.

| State | Where | Asserted |
|---|---|---|
| `unavailable` | live + fixture `features=off` | No `fst.settings.feedback.bug|feature` rows; no POST |
| `editing-empty` | open from the row | Bug form has repro/expected (feature form doesn't); Submit disabled, `.validation` "Add a title after the prefix."; Cancel closes without asking |
| `invalid` | title only, or description cleared again | Submit disabled, reason "Add a description." |
| `editing-dirty` | title + description | Submit enabled, `.validation` hidden |
| `discard-confirm` | Cancel while dirty / while sending | `.discard-confirm` open, focus on Keep Editing; Keep Editing returns focus to the title; Discard closes |
| `attachments` | 5 files picked through the system picker | 4 kept with the notice "You can attach up to 4 files."; tiles named "Image, shot-1.png, N KB" with "Remove shot-1.png"; Attach Media disabled and focus on the last tile; removing one re-enables and focuses Attach Media |
| `sending` / `filing` | fixture POST held, then status `processing` | Fields faded out; centred `.busy` ring, `.progress` "Uploading Media" over `.progress.bar`, then "Filing Issue" over the sentence (#634), Submit disabled. One POST: kind `bug`, platform `windows`, 3 media parts, no `X-API-Key` or selected-profile header |
| `sent` | status `filed` | `.sent` "Thanks! Your report was filed as issue #1."; fields and Submit gone, only Done remains |
| `error` | feature form: `fixture-unavailable` (503 busy), then `fixture-failed` (filing failed) | `.error` "Not sent" with "Feedback is busy right now. Try again in a minute." / "Your request couldn't be filed on GitHub. …"; fields kept, Submit enabled; editing clears the error; the third try is filed |

| Configuration | Result |
|---|---|
| Compact, medium, wide, maximized, snapped left/right | Pass after fixes. **Fixed:** the description helper was cut mid-sentence at compact |
| Light / dark system theme | Pass, identical (dark-only app, documented deviation in [design/windows.md](../../design/windows.md)) |
| Desert, Night sky | Pass. **Fixed:** tile play/remove badges were fixed black/white and now follow contrast themes. The validation caption, notice and InfoBars use system colours |
| Text 200% | Pass after the wrap fix: headers, helper text, validation caption and InfoBars wrap; the form scrolls within the dialog |
| Display 100% / 150% (host is 300%) | Pass: layout scales; the dialog keeps its 640-epx cap and the scroller fits the window. At medium with 150%, Axe flags a Settings description clipped to zero height at the page's top edge behind the dialog (known viewport-edge clipping, [open issue 7](../../testing/windows-accessibility.md#open-issues)); the dialog scans clean |
| Keyboard only | **Fixed:** Cancel on a dirty form now focuses Keep Editing (it stayed on the field), focus follows a pick, and Submit is disabled with a reason instead of silently ignoring an invalid draft. Order: title → description → (repro → expected) → tiles (open, remove) → Attach Media → Submit → Cancel. Esc = Cancel |
| Narrator / UIA | Fields are `Edit` with Name = header and HelpText = helper; tiles are buttons named "Image, <file>, <size>" with a "Remove <file>" button. Sending/filing/sent/skipped notices and validation changes are announced through `ScreenReader.Announce`; the error InfoBar reads its message on open (Message set before IsOpen). The console was locked, so spoken output was checked through UIA names and announcements, not live Narrator |

Design review (`winui-design`, `winui-code-review`): Fluent `ContentDialog` with an accent primary button, headed `TextBox`es with `Description`, and `InfoBar` for error and confirmation ("Feedback: inline status / async progress → InfoBar"). Brushes are `{ThemeResource}` by semantic name ("Hard-coded color literals → {ThemeResource} brushes by semantic name"). Deliberate deviations: discard confirmation is an inline InfoBar, because a `ContentDialog` can't open a second one. Strings are C# constants, because the repo has no `.resw` localisation yet.

## Accessibility tests (issue #433)

`tools/windows/journeys/a11y-feedback.json` asserts, beyond the Axe scan, what #78 added. CI runs it at `normal` and `text-225` (`ui_ci.generated_runs`).

- **Settings rows:** "Report an Issue, button, Tell us about something that isn't working right." and "Request a Feature, button, …" (HelpText is the subtitle), bug row before feature row, at least 40×40 epx, Tab/Shift+Tab between them, Enter opens the form.
- **Fields:** each edit reads "<header>, edit, <helper>" (the title adds its "[Bug] " value). Keyboard order is title → description → repro → expected → Attach Media → Cancel while Submit is disabled, and Attach Media → Submit → Cancel once it is enabled. "Media" is a level-3 heading.
- **States:** the validation reason, the unavailable Submit, progress, sent ("Done, button") and error phrases, each in reading order with the title.
- **Attachments:** tile and "Remove <file>" phrases, Shift+Tab through remove → tile → remove, and focus back on Attach Media after a remove.
- **Discard bar:** heading, message, Discard, Keep Editing in order; Tab between the buttons; Enter on Keep Editing closes the bar and focuses the title.
- **Rule:** every button the form builds in code (Attach Media, Discard, Keep Editing) uses `DialogChrome.TargetSize` (`FSTMinTargetSize`, 40 epx), the same as the dialog's Submit/Cancel. Discard and Keep Editing were 31.7 epx tall until #433. `ModalMarkupTests.FeedbackContentButtons_KeepTheMinimumTouchTarget` guards this.

## Busy stage (issue #634)

Owner-approved variant [modal-shell](../../patterns/modal-shell.md) R16 (spec Submit). `FeedbackDialog.cs` `#region Busy stage`:

- **Stage:** the dialog's middle row holds the field `ScrollViewer` and a busy `ScrollViewer` (centred content, its own scroller so very large text stays reachable, like `EmptyStateView`). Submit fades the fields out, collapses them (focus moves to Cancel if it was inside), then fades the busy view in. It holds a 48-epx `ProgressRing` (named `FeedbackCopy.BusyName`, "Sending your issue"/"Sending your request", kept across steps), a `SubtitleTextBlockStyle` title and either a 240-epx determinate `ProgressBar` ("Upload progress", 0–100) or the `FSTSecondaryTextBrush` body sentence. Text wraps and stays centred at text 225 %.
- **Steps (`FeedbackFormViewModel`):** `StatusTitle`/`StatusSubtitle`/`ShowsUploadBar`. With media: "Uploading Media" over the bar, then "Filing Issue"/"Filing Request" over "We’re filing your issue/request. Please wait while we upload it.". **Without media the Filing copy shows from Submit** (agent decision shared with Android: "Uploading Media" would be wrong and would flash). `UploadFraction` comes from `UploadProgressContent` (bytes written ÷ content length) and never moves backwards.
- **Motion:** each swap is `AccordionMotion`'s 150 ms CSS-ease fade phase (web `QUICK_FADE_MS`). The hand-off fades only the `.status` stack; the ring is not touched, so it keeps spinning. `SwapStatus` skips the fade when the copy doesn't change. With Reduce Motion (Windows animations off or the app setting) every swap is instant. Interrupted fades continue from the reached opacity and stale callbacks are dropped (sequence tokens).
- **Layout:** while busy the stage keeps the form's height (`MinHeight`, capped to the scroller's maximum), so the dialog doesn't jump and the status centres in the same space. The discard InfoBar sits above the stage, so Cancel while sending still asks and Keep Editing returns focus to Cancel (the fields are gone). Close while filing needs no confirmation.
- **Narrator:** ring → title → bar (with its value) or sentence → Cancel; the hidden fields are out of the tree. Each new title is announced once (`announcedStatus`), so a form without media hears "Filing Issue" once, not twice. A failure fades the fields back with every value and attachment kept and the error bar in view. The Windows sent state stays in the dialog (Done); #565's close-then-alert is Apple's.
- **Fluent:** WinUI's progress-controls guidance asks for "progress text … not just a spinner with no context"; a determinate `ProgressBar` shows a known amount of work and a `ProgressRing` an indeterminate wait.
- **Tests:** `FeedbackTests` (`Form_SubmitsPollsAndShowsIssueNumber` captions, `Form_WithoutMediaReadsAsFilingFromSubmit`, monotonic upload progress, client progress reporting); journeys `feedback.py submit|error` (centred busy, no fields, Keep Editing focus, Filing copy, the error restores values); matrix pages `feedback-sending`, `feedback-uploading-media` (`"state": "sending"`), `feedback-filing`, `feedback-error` (exact Narrator phrases, order, `assertcentred`, one announcement per step, 40×40 Cancel). `ui_ci.py` runs them at normal, text 225 % (compact) and app Reduce Motion (medium).