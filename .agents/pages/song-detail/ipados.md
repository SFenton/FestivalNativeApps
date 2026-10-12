# Song Detail — iPad notes

> **What:** iPad-specific Song Detail findings. **Read when:** the iPadOS phase, or when a change touches Detail's score rows or split view. Behavior: [spec.md](spec.md).

- Hide Sidebar with Detail visible once hung the main thread (padding inside the shared score badge caused a split-view/hosting-scroll layout loop); keep that transition in device journeys and never infer responsiveness from a painted frame. Fix and details: [score-accuracy/ipados.md](../../controls/score-accuracy/ipados.md).
- Settings visibility propagation (hidden Bass absent from leaderboard actions and Paths, Intensity kept) is exercised on iPad as well as iPhone.
- No passing iPad full-page Detail audit is recorded; treat it as open.
- Band previews pair in the card columns in landscape (#366). Their AX5 landscape journey `SongDetailBandColumnsJourneyTests` (#491, `apple-ci` iPad list) checks headings, 44 pt named buttons, reading order and the system audit for the band cards; it is not a full-page Detail audit.
