# Feedback form — iPhone Duo notes

> **What:** how the feedback form behaves on iPhone Duo compared with the [iPhone design](ios.md). **Read when:** changing the feedback form on iPhone Duo. Spec: [spec.md](spec.md).

| Aspect | Duo |
|---|---|
| Surface | Same sheet. Folded it matches iPhone; unfolded (regular width) `festivalSheet` applies form sizing so the sheet does not span the fold. The system sheet's fold adaptation is relied on, with no custom fold layout ([designing for iPhone Duo](../../design/apple/duo.md)) |
| Platform label | `iphone-duo` whenever `DeviceLayout.pose` is not `.standard` (folded, unfolded or partially folded), so a folded Duo is not reported as a plain iPhone |
| Media | Same Photos picker / Files importer and Quick Look preview as iPhone |
