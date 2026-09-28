# Windows design (WinUI 3)

> **What:** WinUI 3 chrome decisions. **Read when:** laying out Windows screens (host paused).

- `NavigationView` for navigation; WinUI surfaces and system focus conventions; Fluent/WinUI focus visuals, system high contrast and text scaling.
- Expose `AutomationProperties.AutomationId` from the shared `product.json` test-ID registry.
- Keep background visuals when the app sits beside a game; gate them on data-saving/reduced-motion/measured occlusion ([platforms/windows.md](../platforms/windows.md)).
