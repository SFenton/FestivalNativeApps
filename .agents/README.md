# Agent knowledge router

> **What:** the entry map for `.agents`. **Read when:** always, right after [AGENTS.md](../AGENTS.md); jump straight to the one file your task needs (≤2 hops).

## By task

| Task | Read |
|---|---|
| **Fix a tracker bug or build a tracker feature** (start here) | [skills/fix-reported-issue/SKILL.md](skills/fix-reported-issue/SKILL.md) → the owning [patterns](patterns/README.md) (`python3 tools/pattern_guard.py index`) → page/control spec + your platform file |
| Touch any shared behavior (fades, materials, chrome, modals, rows, loading, empty states, Quick Links, section headers) | [patterns/README.md](patterns/README.md): canonical component per platform, numbered rules, known debt |
| A design choice the owner hasn't made | [skills/design-decision/SKILL.md](skills/design-decision/SKILL.md): decide, document, owner may override |
| Port or change a page | [pages/README.md](pages/README.md) → `pages/<id>/spec.md` + your platform file; procedure: [skills/port-page/SKILL.md](skills/port-page/SKILL.md) |
| Port or change a control | [controls/README.md](controls/README.md) → `controls/<id>/spec.md` + your platform file; procedure: [skills/add-control/SKILL.md](skills/add-control/SKILL.md) |
| Call a service endpoint | [platforms/service-safety.md](platforms/service-safety.md) (blocked endpoints, headers, keys) |
| Visual check vs the web app | [skills/screenshot-compare/SKILL.md](skills/screenshot-compare/SKILL.md) |
| Decide what tests to write now | [testing/strategy.md](testing/strategy.md) (phases) |
| Lane ownership, integrate, simulator | [workflow/lanes.md](workflow/lanes.md) |
| CI, App Store Connect builds/submission, release credentials | [workflow/release-machine.md](workflow/release-machine.md) |
| Edit these docs | [workflow/docs-conventions.md](workflow/docs-conventions.md); check with `python3 .agents/_tools/check_docs.py` |
| Web source, snapshots, parity backlog | [workflow/source-of-truth.md](workflow/source-of-truth.md) |

## By platform

| Platform / form factor | Design | Architecture & runtime | Testing |
|---|---|---|---|
| iPhone (iOS 26 Liquid Glass; iOS 17 classic) | [design/apple/iphone.md](design/apple/iphone.md), [liquid-glass.md](design/apple/liquid-glass.md) | [platforms/apple/architecture.md](platforms/apple/architecture.md), [build-and-run](platforms/apple/build-and-run.md), [simulators](platforms/apple/simulators.md) | [testing/apple/](testing/apple/README.md) |
| iPhone Duo | [design/apple/duo.md](design/apple/duo.md) | [platforms/apple/duo.md](platforms/apple/duo.md) | [testing/apple/](testing/apple/README.md) |
| iPadOS | [design/apple/ipados.md](design/apple/ipados.md) | [platforms/apple/architecture.md](platforms/apple/architecture.md) | [testing/apple/](testing/apple/README.md) |
| macOS | [design/apple/macos.md](design/apple/macos.md) | [platforms/apple/macos.md](platforms/apple/macos.md) | [testing/apple/hosted-snapshots.md](testing/apple/hosted-snapshots.md) |
| Android (phone, foldables, tablet, tri-fold) | [design/android.md](design/android.md) | [platforms/android.md](platforms/android.md) | [testing/android.md](testing/android.md) |
| Windows (WinUI 3) — host paused | [design/windows.md](design/windows.md) | [platforms/windows.md](platforms/windows.md) | [testing/windows.md](testing/windows.md) |

Cross-platform: [design/fluent.md](design/fluent.md) (tokens), [testing/fixtures.md](testing/fixtures.md) (mock service), [testing/web-reference.md](testing/web-reference.md) (PWA captures).

## Folders

| Folder | Holds |
|---|---|
| [workflow/](workflow/README.md) | How we work: lanes, change loop, source of truth, doc rules |
| [design/](design/README.md) | Fluent tokens + per-platform design/HIG decisions |
| [platforms/](platforms/README.md) | Architecture, build/run, devices, service safety |
| [pages/](pages/README.md) | One folder per web route: `spec.md` + per-platform notes |
| [controls/](controls/README.md) | One folder per control: `spec.md` + per-platform notes |
| [testing/](testing/README.md) | Test phases, fixtures, per-platform test tooling |
| [patterns/](patterns/README.md) | Cross-page, cross-platform behavior patterns: canonical components, rules, debt, guards |
| [skills/](skills/README.md) | Repeatable step-by-step procedures |
| [_tools/](_tools/README.md) | `check_docs.py`: enforces this structure |
