# In-app feedback form: Windows notes

> **What:** how Windows builds the Report an Issue / Request a Feature dialog, its picker, polling and tests. **Read when:** changing feedback on Windows. Spec: [spec.md](spec.md); Android: [android.md](android.md).

## Implementation

| Piece | Where |
|---|---|
| Domain | `Festival.Core/Domain/Feedback.cs`: kinds, limits, copy, draft validation and attachment limits, submission wire parts, `FeedbackJob`/`FeedbackJobState`, `FeedbackException` (code/status → fixed copy, `Retry-After`) |
| Wire | `Festival.Core/Data/FestivalApiClient.Feedback.cs`: `GetFeedbackEnabledAsync` (`/api/features`), `SubmitFeedbackAsync` (multipart, streamed files), `GetFeedbackStatusAsync` (validated 32-hex ID) |
| State | `Festival.Core/ViewModels/FeedbackFormViewModel.cs`: submit → filing poll (`PollInterval` 2 s, `PollTimeout` 5 min), fixed outcome text, failed filing returns to editing. `SettingsViewModel.FeedbackAvailable` gates the rows |
| UI | `Festival.App/Controls/FeedbackDialog.cs`: Fluent `ContentDialog` (max width 640) with Submit/Cancel and headed `TextBox`es whose `Description` holds the helper text, inside its own `ScrollViewer` (the dialog's scroller never scrolls vertically). The progress row sits **above** the fields and the form scrolls to the top on submit so progress is visible. Discard confirmation is an inline warning `InfoBar` with Discard / Keep Editing, because a `ContentDialog` cannot open a second one |
| Rows | `Festival.App/Pages/SettingsPage.xaml`: App Settings rows bound to `FeedbackAvailable` |

## Picker and opening

- `Microsoft.Windows.Storage.Pickers.FileOpenPicker` (Windows App SDK, window-ID based), multi-select, filtered to `FeedbackMedia.Extensions` (images and videos). No capability is required.
- Thumbnail buttons open the file with `Windows.System.Launcher.LaunchFileAsync` (the system Photos or Media Player app). Each has a Narrator name and a separate remove button.

## Test IDs

`fst.settings.feedback.bug|feature` (rows), `.title`, `.description`, `.repro`, `.expected`, `.attachments`, `.attachment`, `.attachment.remove`, `.attach`, `.progress`, `.sent`, `.error`, `.discard`, `.keep-editing`, `.discard-confirm`, `.scroller`, `.cancel`.

## Verification

- `Festival.Core.Tests/FeedbackTests.cs` and `SettingsServiceInfoTests.cs` (availability). `tools/windows/test.ps1 -Coverage` on 2026-10-02: 1423 passed, 98.85% line coverage.
- End to end against a loopback stub (`--base-url=http://127.0.0.1:<port>/`): rows appear with the flag, the POST carries every field, the dialog polls three times, then shows "Thanks! Your report was filed as issue #N." Against production the rows stay hidden while `/api/features` lacks `feedback: true`.
