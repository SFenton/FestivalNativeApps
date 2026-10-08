# CHOpt Paths — iPad notes

> **What:** iPad-specific Paths findings. **Read when:** the iPadOS phase or changing the Paths sheet layout. Behavior: [spec.md](spec.md).

- In the sidebar shell (regular width) Paths opens as a full-screen cover with the View menu's Image / Text / Side by Side (owner, #368; [modal-shell](../../patterns/modal-shell.md) R11); pull down past the top of the image or table, or Close, dismisses it. Side by Side splits the window into equal halves, image leading. A compact-width iPad (tab bar) keeps the sheet. Verified live 2026-10-08 on the iPad simulator (24K Magic, Lead Expert).
- Image placement and hidden indicators are shared with iPhone (issue #87, [ios.md](ios.md)); the Paths journey asserts equal margins on iPad too.
- Full `.all` audit still fails with unnamed "Potentially inaccessible text" despite rendered-contrast checks on header, Close and summary — open, not waived.
- Settings-hidden Bass is absent from the Paths menu on iPad as on iPhone; the Paths journey also exercises Hide Sidebar (see [score-accuracy/ipados.md](../score-accuracy/ipados.md)).
- Native iPad warning coverage is not yet recorded.
- Instrument, Difficulty and View are the same native pop-up menus as on iPhone (issue #88; [ios.md](ios.md)); at regular width the instrument label has room for its name beside the icon.
- Swipe down dismisses the compact-width page sheet as on iPhone (issue #96, [ios.md](ios.md)); the regular-width cover uses the same pull-down gesture through `PullDownToDismiss` (#368).
