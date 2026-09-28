# Windows testing

> **What:** Windows coverage and UI-automation rules. **Read when:** Windows work resumes (host paused; do not reconnect). Architecture: [platforms/windows.md](../platforms/windows.md).

- Separate logic tests (testable view models) from XAML/UI automation; **95% / 90%** line coverage via Cobertura XML, which `tools/coverage_gate.py` parses and merges.
- UIA-pattern queries can sometimes work over SSH; injected pointer gestures and screenshots may need an interactive desktop. Prove both before choosing a test-runner setup. Do not configure autologon without separate authorization.
- Compare app/game impact in Release builds with representative workloads.
- No Windows coverage has been measured yet.
