# App navigation — iPad notes

> **What:** the iPad sidebar as built. **Read when:** changing the iPad split-view shell. Rules: [spec.md](spec.md); layout: [design/apple/ipados.md](../../design/apple/ipados.md).

- `NavigationSplitView` sidebar with custom Buttons: every row on an opaque Fluent card; selection = 3pt accent-blue leading bar + semibold + `.isSelected`. A screenshot-pixel test checks the accent moves Songs → Settings → Leaderboards; the manufacturer Songs audit runs without a contrast exception.
- Sidebar footer shows the selected player's name; it opens the selection/switch sheet (the web links to Statistics, which does not exist natively yet — WIP gap).
- An iPad audit once misreported white "Leaderboards" text (18.49:1 measured); opaque row cards removed the finding without suppressing any audit issue.
