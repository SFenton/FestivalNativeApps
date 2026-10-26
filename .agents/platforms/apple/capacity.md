# Simulator and build capacity

> **What:** the machine-wide slots that every repository on a Mac waits on before booting a simulator, driving a device or compiling. **Read when:** changing how `tools/ios_sim.py` (or any tool) takes the simulator or build lock, or vendoring `tools/devcap.py` into another repo.

FST lanes and other projects' lanes (Fenton-HASS-Native) share one Mac. `tools/devcap.py` is the one capacity mechanism for all of them: machine-wide slots handed out first come, first served, so a lane waits its turn instead of booting another simulator or starting another compile on a full machine.

This repository holds the **canonical copy** (`tools/devcap.py`, tests in `tools/tests/test_devcap.py`). Other repositories vendor both files byte for byte and keep `VERSION` in step; change the protocol here first, bump `VERSION`, then copy it out.

Worktrees keep whatever copy they branched with, so the Mac also has a **shared install** at `~/.devcap/lib/devcap.py`: every copy from 1.2.1 on runs it instead of itself when it is newer. After merging a devcap change, run `python3 tools/devcap.py install` from an up-to-date default-branch checkout (never from an unmerged branch). Copies older than 1.2.1 can't defer; those worktrees need to rebase.

## Gates

| Gate | Slots | Taken by |
|---|---|---|
| `device-<UDID>` | 1 | `--sim UDID` or `--device UDID`: one lane per simulator or physical device |
| `simulator` | RAM / 16 GB, 1–6 (4 on a 64 GB Mac) | `--sim UDID`: one per simulator in use |
| `build` | cores / 4, 1–4 | `--pool build`: heavy `xcodebuild` / `swift build` compiles |

State lives in `~/.devcap/<gate>/`: per-slot OS locks (released by the OS when a holder dies), a FIFO ticket queue (dead waiters pruned), holder records, and `~/.devcap/devcap.log`. Override counts with `DEVCAP_SLOTS_<POOL>` or `~/.devcap/config.json`.

## Simulators booted outside a hold

A booted simulator whose device gate nobody holds is **unmanaged**: something booted it without devcap, or left it booted after its hold. Unmanaged simulators count against the `simulator` slots, so the limit holds whoever boots them. After 5 minutes unmanaged (`DEVCAP_REAP_GRACE` or `config.json` `reap_grace_seconds`; `off` disables), the next waiter or finished simulator hold shuts it down and closes Device Hub windows of devices nobody is using, including stale "Devices – No Selection" windows (owner decision, 2026-10-13). Simulators running an app under Xcode's debugger are never shut down. A lane may leave its simulator booted between consecutive runs so the next run skips the boot (warm). It still counts against the slots, and when every slot is in use the waiter at the head shuts down the one idle longest after 60 s idle (`DEVCAP_EVICT_AFTER` or `evict_after_seconds`; owner request, 2026-10-14). `python3 tools/devcap.py status` lists unmanaged simulators; `python3 tools/devcap.py reap [--dry-run]` sweeps on demand.

Consequences: never boot or drive a simulator outside a hold (a direct `simctl boot` or `xcodebuild test` gets shut down after 5 minutes), and `ios_sim.py`'s product simulator no longer stays booted for long between holds. Device Hub handling compiles a small Swift helper into `~/.devcap/bin` on first use and needs the Accessibility permission the agents already have; `DEVCAP_HUB=off` turns it off.

## How FST tools use it

- `ios_sim.sim_lock(udid, purpose)` takes `~/.fst-sim.lock` (FST's one-product-simulator rule) and then `devcap` `--sim udid`. `shot`, `drive`, `uitest` batches, `pose`/shutdown and `pwa_ios.py` all go through it.
- `ios_sim.build_lock()` takes `~/.fst-build.lock` and then a devcap `build` slot; `mac_app.py build` and `lane_integrate.sh`'s `swift build` do the same.
- The FST locks are always taken before the devcap gates, and devcap takes devices before pools, so holders never deadlock. A child of a devcap hold inherits `DEVCAP_HELD` and reuses its parent's gates.
- The 5-minute hold rule ([simulator driver](../../workflow/simulator-driver.md)) still bounds FST holds; `sim_lock` adds no devcap watchdog of its own.

## Slim simulators

> **Why:** a stock simulator runs about 258 processes in about 4 GB; slimmed with simslim it needs a fraction of that (measured below), so FST lanes stop taking stock simulators from the shared `simulator` slots (owner, 2026-10-25, the same change as Fenton-HASS-Native's SFenton/Fenton-HASS-Native#154).

[simslim](https://github.com/MobAI-App/simslim) (`brew install mobai-app/tap/simslim`, 0.12.2 on the Mac) disables a simulator's background daemons with launchd overrides stored on the device, so a slimmed product simulator stays slim across shutdowns. `ios_sim.boot_exclusive` slims every FST simulator right after its boot, inside the `sim_lock` hold and before the app is installed (`tools/sim_slim.py`), so `shot`, `drive`, `uitest` batches, `pose`, `slim`, `apple_perf.py ipad` and `pwa_ios.py` all come up slim. It is idempotent: a simulator already on the profile costs one `simslim verify` (about 0.5 s), nothing more while it stays booted in the same `ios_sim.py` process (later `uitest` batches), and about 90 s the first time.

`tools/simslim/ui.json` (the one profile) turns off everything except the `photos` category (`assetsd`, `photoanalysisd`, …): feedback attachments use `PhotosPicker` and the inline library (`FeedbackFormSheet`), and on iPad a photo is dragged in from the Photos app (`FeedbackMediaJourneyTests`). `simslim doctor <UDID> --requires photos` runs after every fresh slim, and both `FeedbackMediaJourneyTests` methods pass slim on the iPad.

Off on purpose, each checked against what the app uses:

- `store` (push, StoreKit): the app has no entitlements and no push; Debug builds never call StoreKit (`AppDistributionResolver` answers `.development` or `FST_DEBUG_DISTRIBUTION`), and Release falls back after its timeout.
- `widgets`, `siri`: no widget, Live Activity or App Intents target.
- `web`, including `webbookmarksd`: Safari's Add to Home Screen and launching the web clip standalone both work without it (`pwa_ios.py install` and `launchIcon` on a loopback page, 2026-10-25), so the PWA lab needs nothing kept.
- The rest (`search`, `icloud`, `pim`, `family`, `health`, `apps`, `messaging`, `connectivity`, `telemetry`, `other`): nothing in the app uses them. Share sheets keep `sharingd` and XCUITest launches keep `gamed`, which simslim never disables; networking (`NWPathMonitor`), accessibility settings, the keyboard, XCUITest's services and Vision text recognition in the test runner are core.

Measured on this Mac (2026-10-25, `simslim measure` after the same journeys, phys_footprint):

| Device | Stock | Slim (159/168 off: `ui.json` while it still kept `webbookmarksd`; the final profile turns 160/168 off) |
|---|---|---|
| `iphone` (iOS 26.5) | 296 processes, 3.73 GB | 110 processes, 1.36 GB |
| `ipad` (iPadOS 26.5) | 294 processes, 3.76 GB | 110 processes, 1.33 GB |
| `duo` (iOS 27.1, folded) | 227–290 processes, 1.90–2.43 GB | 117–118 processes, 0.93 GB |

Rules:

- **Slim inside the hold, after the boot.** Go through `ios_sim.py` (or `python3 tools/ios_sim.py slim --device <alias> [--measure]` to slim ahead of a run). `sim_slim.ensure_slim` refuses a UDID whose `device-<UDID>` gate is not in `DEVCAP_HELD`: never run `simslim` on a simulator you do not hold, or on another project's device.
- **Never `simslim off`, `erase` or `delete` a product simulator** another lane may use. A newly created device is stock and is slimmed by its first `ios_sim.py` boot; overrides do not survive `simctl clone`.
- **A first slim may reboot.** `simslim on --no-reboot` is tried first; when the profile needs a daemon back on, `simslim on` reboots the device, which drops an unfolded iPhone Duo to folded. `boot_exclusive` then reports the device as fresh, so `uitest --pose … --set-pose` sets the pose again.
- **Need a feature that is off?** Add its category to `except` (or a daemon to `keep`) in `tools/simslim/ui.json`, prove it with `simslim doctor <UDID> --requires <feature>` where a feature exists (`simslim doctor --list`; `simslim profiles <category>` lists daemons), add a row to the table above and say why in the commit. Do not widen the profile to make one failing journey pass: find the daemon the app really needs.
- **One profile, no lean variant.** Photos is the only category kept (~60 MB idle), and moving back from a leaner profile costs a reboot that drops an unfolded Duo pose, so a second profile would save little and cost more.
- **Opt out for one run:** `FST_SIM_SLIM=0` skips slimming (A/B and perf comparisons); `FST_SIM_SLIM_PROFILE=<file>` applies another profile. Opting out does not un-slim a device: its overrides are stored; `simslim off <UDID>` inside a hold does, and costs a reboot.
- **CI stays stock.** GitHub Actions runners skip slimming: each run creates a fresh runner simulator, so slimming would cost a `brew install` and a 90 s first slim per device on a VM that already runs journeys several times slower, for RAM a runner does not share.
- **Perf baselines.** Slim simulators have less background noise than the stock ones earlier `apple_perf.py ipad` numbers were taken on: compare a run against a baseline taken the same way.
- A missing `simslim` or a failed `simslim on` is a warning (`sim_slim: leaving … as it is`); the run goes ahead on the simulator as it is. `simslim list --booted` shows a booted simulator's slim count (`0/N slim` is stock), `simslim measure <UDID>` its memory.

## Commands

```bash
python3 tools/devcap.py status                               # holders, waiters, slot counts
python3 tools/devcap.py run --sim "$UDID" --shutdown -- <command>  # anything else that drives a simulator
python3 tools/devcap.py run --pool build -- <compile command>
```

`python3 tools/devcap.py pick-sim --name "<simulator name>" [--prefer <UDID>]` prints a free member of that device type's pool ("<name>", "<name> (pool 2)", …, one per simulator slot, created on demand with the same type and runtime), so lanes that want the same device type run in parallel instead of queuing on one device gate. `run` waits up to `--wait` seconds (3600, then exit 75), holds up to `--hold` seconds (1800, max 7200, `0` = no limit; overrun kills the process group and exits 124) and forwards Ctrl-C to the command. `--shutdown` shuts the `--sim` simulators down before the slots are released, including after a hold timeout, so a killed run never leaves a simulator booted outside a hold. `--shutdown-on-timeout` keeps the simulator warm after a normal run and shuts it down only when the hold times out (a hung run).
