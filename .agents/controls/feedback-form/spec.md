# In-app feedback form (`fst.settings.feedback.*`): spec

> **What:** platform-neutral behavior of Settings → App Settings → **Report an Issue** / **Request a Feature**: fields, attachments, availability gate, submission, filing poll and dismissal (issue #78). **Read when:** changing the feedback rows, form or service calls on any platform. Platform notes: [ios.md](ios.md), [ipados.md](ipados.md), [duo.md](duo.md), [macos.md](macos.md), [android.md](android.md), [windows.md](windows.md). Wire safety: [service-safety](../../platforms/service-safety.md#user-initiated-feedback-post).

Source: the service contract `docs/components/in-app-feedback.md` and `FSTService/Api/FeedbackEndpoints.cs` in the service repo (branch `report/78-service` when written). The pinned web revision has no form yet (contract anchor: App Settings, `FortniteFestivalWeb/src/pages/settings/SettingsPage.tsx:516`); the in-progress web form is `FortniteFestivalWeb/src/pages/settings/feedback/FeedbackModal.tsx` on `report/78-web`. The service document wins on any difference.

Rollout: production turns `feedback` on through the release machine's declared feature rollout ([release machine](../../workflow/release-machine.md#service-feature-flags)), not through a client change.

## Service contract (summary)

| Call | Use |
|---|---|
| `GET /api/features` → `{appManual, feedback}` | Rows show only when `feedback` is JSON `true`. Anything else (missing, non-boolean, error, non-object) hides them; a failed read retries on the next Settings visit |
| `POST /api/feedback` (multipart) | Fields `kind` (`bug`/`feature`), `platform` (`web`, `ios`, `ipados`, `macos`, `iphone-duo`, `android`, `windows`), `title` ≤ 200, `description` ≤ 10 000, `repro` + `expected` (bug only, omitted when empty), `appVersion` ≤ 64, `clientInfo` ≤ 256 (trimmed and clipped client-side), up to 4 `media` file parts. The whole request must be ≤ 94 371 840 bytes. **202** `{id, status:"queued"}` |
| `GET /api/feedback/{id}` | `id` is 32 lowercase hex characters (validated before the call). `{id, status: queued\|processing\|submitted\|failed, issueNumber?, attachments[{outcome: pending\|attached\|transcoded\|skipped}]}`. Kept in memory for 60 minutes, then 404. No issue URL |
| Errors | 400 `{error, code}` (validation codes), 404 `feedback_disabled`, 413 `payload_too_large`, 429 (5 per 10 minutes per IP, `Retry-After`), 503 `feedback_busy` (`Retry-After: 60`) |

The service transcodes oversized media, labels the issue with the plain platform name (`web`→`Web`, `ios`→`iOS`, `iphone-duo`→`iPhone Duo`, `ipados`→`iPadOS`, `macos`→`macOS`, `android`→`Android`, `windows`→`Windows`) plus `From App`, and files it. Clients never talk to GitHub.

## Client contract (all platforms)

- **Entry:** two App Settings rows, *Report an Issue* and *Request a Feature*, hidden unless the features flag is on. Each opens one modal form; only one form or sheet at a time.
- **Fields:** Title is pre-filled with `[Bug] ` / `[Feature] ` and must keep the prefix with text after it (Apple restores a deleted or mangled prefix in front of the remaining text). Lengths are counted in UTF-16 units, as the service counts. Description is required. The bug form adds **Steps to Reproduce** and **Expected Behavior** (optional). Every field has a visible label and a visible helper line, not placeholder-only text: placeholders vanish while typing, which HIG, Material and Fluent all discourage for guidance.
- **Attach Media:** system pickers only (a photo/video picker and a file picker where the platform has both). Images and videos only; at most 4 files and less than 90 MB in total; rejected picks show one combined notice. Attachments render as thumbnails above the button, each with a labelled remove action; activating a thumbnail opens it in the system viewer. No in-app player. Apps that copy picked media keep private copies and delete them when the form closes; Apple also strips location metadata from its copies because the issue is public. **Apple (#373):** media dropped on the form attaches with the same limits; on iPad/Duo at regular width the photo library opens inline beside the form; the Files picker always stays presented (no public inline form) ([modal-shell](../../patterns/modal-shell.md) R11).
- **Dismissal:** closing a form with any input beyond the prefix asks *Discard?* first. Closing while the request is being filed does not ask: the service already accepted it.
- **Submit:** disabled while invalid; shows *Sending your report/request…* while uploading, then *Filing your report/request on GitHub…* while polling every 2 s for at most 5 minutes.
- **Outcome copy is fixed client text, never server text:**
  - submitted: *Thanks! Your report was filed as issue #N.* plus *K attachment(s) couldn't be attached.* when the service skipped some;
  - unknown outcome (no ID, poll error, expired job or timeout): *Thanks! Your report was received and will be filed on GitHub shortly.*, so people don't send duplicates;
  - failed filing: back to the form with input kept and a retry message;
  - HTTP errors: mapped from the service `code` (or the status), with `Retry-After` shown as "Try again in N minutes".
- **Never** send `X-API-Key` or selected-profile headers. Automation posts only to fixtures. `tools/mock_service.py` reports `feedback: true`, answers 202 with a job that is `submitted` as issue #1, `503 feedback_busy` when the title contains `fixture-unavailable` and a job that `failed` when it contains `fixture-failed`.

## States

| State | Acceptance |
|---|---|
| unavailable | Features flag off or unknown: neither row is shown |
| editing-empty | Form open with only the prefix: Submit disabled, closes without a prompt |
| editing-dirty | Any input: closing asks for confirmation |
| invalid | Title without text after the prefix, missing description or over-long text: Submit disabled with an inline reason |
| attachments | Thumbnails above Attach Media; tap opens externally; remove works; over-limit picks show a notice |
| discard-confirm | Discard / Keep Editing; Discard cancels an upload in flight |
| sending | Progress row; inputs and Submit disabled |
| filing | Accepted; the progress row says it is being filed on GitHub; closing needs no confirmation |
| sent | The form has closed by itself; an alert over Settings titled *Report Sent* / *Request Sent* shows the success text with the issue number (or the "received" text) and a single Done action. No form control (Cancel, Close, Submit) remains after a successful filing ([modal-shell](../../patterns/modal-shell.md) R7, owner #565) |
| error | Form kept with a fixed error message; Submit enabled again |
