# Rivalry — Windows notes

> **What:** Windows state of `/rivals/:rivalId/rivalry`. **Read when:** changing `windows/Festival.App/Pages/RivalryPage*` or `RivalryViewModel`. Full Rivals notes: [../rivals/windows.md](../rivals/windows.md).

- Re-reads the rival detail through the session cache (usually a cache hit from Rival Detail) and shows one category (`mode`; unknown keys show the key and an empty state, as on the web).
- Native sort `ComboBox` (`fst.rivalry.sort`): Default (category order), Closest Gap, Your Biggest Leads, Their Biggest Leads, Title. The web has no sort here; the service's `sort` parameter is left at `closest`.
- Full head-to-head rows (You | rank and score gaps | Them) in a virtualized list; below 380 epx they collapse to one line.
