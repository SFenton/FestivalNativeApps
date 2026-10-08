# Feedback form — iPhone Duo notes

> **What:** how the feedback form behaves on iPhone Duo compared with the [iPhone design](ios.md). **Read when:** changing the feedback form on iPhone Duo. Spec: [spec.md](spec.md).

| Aspect | Duo |
|---|---|
| Surface | Same sheet. Folded it matches iPhone; unfolded (regular width) the form opens page-sized (`FestivalSheetSizing.regularPage`, #373) so the photo library can sit beside it: the form and library panes are equal halves, so their divider meets the hinge. The system sheet's fold adaptation is relied on, with no custom fold layout ([designing for iPhone Duo](../../design/apple/duo.md)) |
| Platform label | `iphone-duo` whenever `DeviceLayout.pose` is not `.standard` (folded, unfolded or partially folded), so a folded Duo is not reported as a plain iPhone |
| Media | Folded: as iPhone. Unfolded: Photo Library opens inline beside the form, as on [iPad](ipados.md) ("more space may expose another level … both side by side", HIG iPhone Duo). Files stays a presented picker. Dropping media onto the form attaches it in every pose |
