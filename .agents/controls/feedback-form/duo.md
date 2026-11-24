# Feedback form — iPhone Duo notes

> **What:** how the feedback form behaves on iPhone Duo compared with the [iPhone design](ios.md). **Read when:** changing the feedback form on iPhone Duo. Spec: [spec.md](spec.md).

| Aspect | Duo |
|---|---|
| Surface | Same sheet. Folded, the form and sending status stay in the safe region beside the rail. Unfolded (regular width) the form opens page-sized (`FestivalSheetSizing.regularPage`, #373) so the photo library can sit beside it. The two panes use `HingeRow` or UIKit's `UKHingeColumnsView` ([hinge-columns](../../patterns/hinge-columns.md) R1, R7): partially folded, the form ends and the library starts at the fold's clearance; flat, they divide the usable sheet at its midpoint ([designing for iPhone Duo](../../design/apple/duo.md)) |
| Platform label | `iphone-duo` whenever `DeviceLayout.pose` is not `.standard` (folded, unfolded or partially folded), so a folded Duo is not reported as a plain iPhone |
| Sent | As iPhone (#565): the sheet (and the inline library pane when unfolded) closes before the alert shows over Settings |
| Sending (#634) | As iPhone: the panes fade out and the status centres in the sheet; `FestivalCentredFill` keeps it on the larger side of a partially folded Duo, like the empty state ([modal-shell](../../patterns/modal-shell.md) R16) |
| Media | Folded: as iPhone. Unfolded: Photo Library opens inline beside the form, as on [iPad](ipados.md) ("more space may expose another level … both side by side", HIG iPhone Duo). Files stays a presented picker. Dropping media onto the form attaches it in every pose. Folding to the cover closes the inline library, not the draft; reopening the inner display keeps the attachments without reopening the library |

UIKit shares the [grouped form gutter](../../patterns/modal-shell.md#known-debt) with Songs and Shop. The cover rail's native safe area supplies its own gutter; the inline form and library keep their usual margins on the inner display.

Settings owns the draft above the sheet content, which the system can recreate
on a display handoff. Keep accepted inline ticks and their attachments with that
draft. Only the visible picker may remove an attachment; a remote picker reset
when its pane disappears is not an untick. Apple HIG
[Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo)
recommends keeping the state of elements consistent between displays.
