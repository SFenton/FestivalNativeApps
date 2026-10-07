# Score metadata — iPad notes

> **What:** iPad width behavior for selected metadata pills. **Read when:** the iPadOS phase or changing pill wrapping. Spec: [spec.md](spec.md).

- Open sidebar vs Hide Sidebar give different detail widths; neither justifies a fixed number of pill rows. Toggle Hide/Show Sidebar in the edge journey (a prior badge layout stalled there).
- Full-screen iPad `.all` for selected Songs is still open ([accessibility](../../testing/apple/accessibility.md)).
- Wide rows (#340, [songs-profile-panel](../../patterns/songs-profile-panel.md)): with a player or band selected, iPad and the Duo inner display (`DeviceLayout.isRegularInBothDimensions`) set `songRowsAllowProfilePanel`; `SongRowView` measures its width (`onGeometryChange`) and splits rows ≥ 600 pt whose compact cards fit one line (`SongProfilePanelPolicy.arrangement`; from about 640 pt at default text). Live SFentonX, iPad Pro 11" portrait (half 383 pt): one column of one-line cards, stars dropped. Landscape (half ≈ 563 pt) keeps stars in one column. Tests: `SongProfilePanelPolicyTests`, `SelectedBandSessionTests`, `SelectedSongRowRenderTests.wideSongRows*`, `songsGridColumnsWithSelectedPlayer`.
