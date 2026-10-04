# Profile selection — iPad notes

> **What:** iPad-specific selection findings. **Read when:** the iPadOS phase or changing the sidebar profile footer. Spec: [spec.md](spec.md).

- The selected player's name is visible in the sidebar footer and changes on select/deselect; the sheet opens without changing the active section. Centered sheet.
- The toolbar avatar with a selected player selects the Statistics sidebar row (or pushes Statistics where it is not a tab in compact widths) instead of opening the sheet (issue #290, [ios.md](ios.md#profile-button-routes-to-the-selected-player-issue-290)); ⇧⌘P "Switch Profile…" still opens it.
- Full `.all` audit on the selected preview reports unnamed "Potentially inaccessible text"; named visible text measures ≥4.5:1; focus bounds unverified.
