# iPhone Duo runtime facts

> **What:** what the Duo simulator does and does not prove. **Read when:** testing or debugging Duo layouts (Wave 4). Layout guidance: [design/apple/duo.md](../../design/apple/duo.md).

- Simulator `BC8A530D-805F-45FD-9D32-71B838C7A05F` (2026-09-24): `simctl io … enumerate` lists outer 1398×2034 and inner 2007×2853 buffers; the app launches on the outer screen.
- `simctl io … screenConfig --display=<outer UUID> power off` left the inner screenshot black (outer power restored afterward). Screen power is **not** a fold posture.
- `XCUIDevice.shared.orientation = .landscapeLeft` left the outer window at 466×678 portrait; the four-rotation Duo test fails at landscape-left and is excluded from matrices.
- **Neither screen power nor XCTest orientation proves an unfolded or rotated pose.** Verify posture, window migration and camera-cutout positions through supported Device Hub controls. The Duo pose/control matrix is unverified.
- The system places navigation vertically on the outer screen; inner/posture/rotation behavior is unverified.
