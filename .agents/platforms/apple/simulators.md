# Apple simulators

> **What:** the product simulators and the rules for sharing them. **Read when:** choosing a device for `tools/ios_sim.py` or a test run. Keep the table in sync with `DEVICES` in `tools/ios_sim.py`.

| Alias | UDID | Device / OS | Use |
|---|---|---|---|
| `iphone` (default) | `4E9F2A49-127D-40BC-A909-08AF3D4BE6A5` | FST iPhone 17 Pro, iOS 26.5 (Liquid Glass) | Current phase |
| `iphone27` | `32DF9891-BCDB-46FB-9317-35EC1239267E` | FST iOS 27 Fresh iPhone 17 Pro | Newer-runtime checks |
| `ipad` | `11E2F7B2-DE32-4466-8A97-04B37F559086` | FST Native iPad Pro 11, iPadOS 26.5 | iPadOS phase |
| `duo` | `BC8A530D-805F-45FD-9D32-71B838C7A05F` | iPhone Duo (FST), iOS 27.1 | Duo phase ([duo.md](duo.md)); poses only via Device Hub, verify with `ios_sim.py pose` |

## Rules

- **One product simulator at a time per host**, only through `tools/ios_sim.py` (global `flock` on `~/.fst-sim.lock`). Never call `simctl` directly while lanes run.
- Never stop, reset, erase or repurpose another project's devices (e.g. the Home Assistant simulators), booted or not. Never erase product simulators to fix a test; clean only the product's DerivedData build output.
- Runtimes on this Mac (2026-09-24): iOS 26.5 / 27.0 / 27.1. **No iOS 17 or iOS 18 runtime**: iOS 17 is compile-checked only until Wave 4 ([PROGRESS.md](../../../PROGRESS.md)).
- Unavailable runtimes and posture controls are gaps, not passes.
