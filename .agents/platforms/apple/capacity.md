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

## Commands

```bash
python3 tools/devcap.py status                               # holders, waiters, slot counts
python3 tools/devcap.py run --sim "$UDID" --shutdown -- <command>  # anything else that drives a simulator
python3 tools/devcap.py run --pool build -- <compile command>
```

`python3 tools/devcap.py pick-sim --name "<simulator name>" [--prefer <UDID>]` prints a free member of that device type's pool ("<name>", "<name> (pool 2)", …, one per simulator slot, created on demand with the same type and runtime), so lanes that want the same device type run in parallel instead of queuing on one device gate. `run` waits up to `--wait` seconds (3600, then exit 75), holds up to `--hold` seconds (1800, max 7200, `0` = no limit; overrun kills the process group and exits 124) and forwards Ctrl-C to the command. `--shutdown` shuts the `--sim` simulators down before the slots are released, including after a hold timeout, so a killed run never leaves a simulator booted outside a hold. `--shutdown-on-timeout` keeps the simulator warm after a normal run and shuts it down only when the hold times out (a hung run).
