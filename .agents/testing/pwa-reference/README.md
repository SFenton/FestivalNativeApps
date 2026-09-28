# Installed PWA reference router

> **What:** measured behaviour of the real festivalscoretracker.com PWA installed to the Home Screen/Dock/Start menu on each platform, the labs that reproduce it, and the gaps against our native apps. **Read when:** matching native chrome, navigation or animation to the web; the fixture Playwright harness ([web-reference.md](../web-reference.md)) covers layout only.

| File | Read when |
|---|---|
| [apple.md](apple.md) | Apple devices: tooling (`tools/pwa_ios.py`), capture index, measured transitions, sheets, chrome |
| [apple-gaps.md](apple-gaps.md) | PWA vs native iPhone gap table with owners |
| [windows.md](windows.md) | Edge app on Windows: window chrome, layout per window preset, measured animations, dialogs; `tools/windows/pwa.py` |
| [windows-gaps.md](windows-gaps.md) | PWA vs native Windows gap table |
| [android.md](android.md) | Chrome-installed app on the FST AVDs: standalone chrome, postures, measured animations; `tools/android/pwa.py` |
| [android-gaps.md](android-gaps.md) | PWA vs native Android gap table |
