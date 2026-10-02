# CHOpt Paths — iPad notes

> **What:** iPad-specific Paths findings. **Read when:** the iPadOS phase or changing the Paths sheet layout. Behavior: [spec.md](spec.md).

- Narrower centered sheet (web tablet: wide dialog with reorderable columns).
- Image placement and hidden indicators are shared with iPhone (issue #87, [ios.md](ios.md)); the Paths journey asserts equal margins on iPad too.
- Full `.all` audit still fails with unnamed "Potentially inaccessible text" despite rendered-contrast checks on header, Close and summary — open, not waived.
- Settings-hidden Bass is absent from the Paths menu on iPad as on iPhone; the Paths journey also exercises Hide Sidebar (see [score-accuracy/ipados.md](../score-accuracy/ipados.md)).
- Native iPad warning coverage is not yet recorded.
