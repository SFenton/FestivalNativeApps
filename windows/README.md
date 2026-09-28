# Windows foundation

Native .NET 9 / WinUI 3 unpackaged x64 application, with a system `NavigationView`,
virtualized `ListView`, Songs/publication and Settings shell, and native 62 × 20
seven-bar difficulty meter. This is a **foundation**, not a certified page port:
the website revision and public wire payload still require independent verification.
No GUI was started in this SSH session.

Build with Visual Studio 2022 MSBuild (the `dotnet build` MSBuild path lacks
WinUI packaging tasks on this host):
`& 'C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\MSBuild.exe' windows\Festival.App\Festival.App.csproj /t:Build /p:Configuration=Debug /p:Platform=x64`.
Test with `dotnet test windows\Festival.Core.Tests\Festival.Core.Tests.csproj`.
The app requires a Windows desktop session to launch. Its Debug endpoint is
**only** `http://127.0.0.1:8765/api/songs` (fixture server, not started by build or
tests). For manual Debug UI work, run `python windows\fixtures\serve.py` in
another terminal; it serves only the checked-in fixture on loopback and
rejects POST. Release uses `https://festivalscoretracker.com/api/songs`; its exact
availability and wire compatibility are **unverified**. Launch only after
confirming the public service contract; build and tests never make a request
to that host. Neither build contains credentials or writes to the service.
Data loading occurs only when the user presses **Refresh songs**.

The **provisional local fixture contract** is a `GET /api/songs` returning
`{"publicationId":"opaque","songs":[{"id":"opaque","title":"text",
"artist":"text","difficulty":1}]}` where difficulty is 1–7. A successful
response may carry an `ETag`; subsequent GETs carry `If-None-Match` and
`X-Publication-Id`. `304` reuses the matching cached snapshot and `409` drops
that cache and reports the conflict; the user can retry by refreshing.
No POST, tracking, name refresh, scrape, maintenance, or admin action exists.
This schema/header/URL is a **client-side fixture assumption**, not a claim
about the website's public API. Replace it only after checking actual public
wire examples and documenting side effects. Cache is in-memory and scoped to
the app session; failed refreshes preserve the previously visible songs.

UI automation scaffold (requires a real interactive Windows desktop):
`fst.shell.navigation`, `fst.shell.songs`, `fst.songs.publication`,
`fst.songs.refresh`, `fst.songs.status`, `fst.songs.list`,
`fst.songs.difficulty-meter`, `fst.settings.connection-mode`. Assert default
Songs selection, Settings round trip, refresh/loading/offline publication
display, seven meter states, high contrast, text scaling, keyboard focus and
screen-reader order with fixture-backed responses. UIA over SSH and screenshots
have **not** been established; the static XAML assertions in
`Festival.Core.Tests` are only a scaffold, not runtime UI evidence or a
coverage result. The
product contract in `contracts/product.json` remains pending.
