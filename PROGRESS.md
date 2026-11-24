# Festival Native Apps — Plan & Progress

Single source of truth for **what is being built, by whom, in which order**. Update the lane table and log whenever a lane lands work on `master`. Detailed per-route gaps stay in `contracts/parity-backlog.json` (`python3 tools/parity_backlog.py --list`).

_Last updated: 2026-09-27 · Orchestrator: Claude Opus 5.5 (Claude Code) · took over from Copilot CLI (GPT-6 Sol) session `215f6b3e` at `05aaaeb`._

---

## 1. Operating model (changed 2026-09-27)

| Before (Copilot) | Now |
|---|---|
| One agent, strictly sequential | **Orchestrator + parallel lanes**, each in its own git worktree |
| Tandem research (Sol + Opus) for every page/control | Opus researches and decides; lanes implement. No tandem passes. |
| Full device matrices + coverage gates on every slice | **Tests phased by maturity** (see §3). During feature build: unit tests + quick screenshots only. |
| Offline/warm-cache disclosure UX | **Online-only for now.** Keep in-process caches for speed; no offline UX. |
| Leaderboards "blocked" by Cloudflare 1010 | Re-probed 2026-09-27: `/api/rankings/*` returns **200** for native-style requests. Unblocked. |

### Lanes and file ownership

Parallel work is safe because **every lane owns a disjoint set of folders**. A lane may *read* anything but only *edit* what it owns. Shared routes, design primitives and package/project manifests are orchestrator-owned — ask in your final report if you need a change there.

`FestivalMobile` owns UIKit for iPhone, iPad and Duo. The separate mobile SwiftUI
shell and duplicate UIKit app target are retired; `FestivalDesktop` keeps native
SwiftUI. The route and menu models are shared. An in-place SwiftUI upgrade
reopens the UIKit window with the selected profile and Hide Item Shop intact.
Catalyst is compile-probed only, not part of the shipping graph.

```
apple/Sources/FestivalAppSupport/  shared route, tab, topic and client policies   → orchestrator
apple/Sources/FestivalUI/
  UIKit/          mobile shell, route map, controllers and controls → Apple UIKit lane
  Mac/            native SwiftUI shell, route map and menus          → macOS lane
  App/            shared app and shell policy                         → Lane A (Shell)
                  FestivalSession.swift                             → Lane P (Profile); others add FestivalSession+<Feature>.swift
  Design/         GlassSurface, SectionHeader, InstrumentIcon       → orchestrator (Lane A may add new files)
  Background/     everything                                        → Lane B (Background)
  Common/         status views, ComingSoonView                      → Lane A
  Features/Songs, SongDetail, Shop                                  → Lane S (Songs)
  Features/Profile                                                  → Lane P (Profile)
  Features/Leaderboards, SongLeaderboard                            → Lane L (Leaderboards)
  Features/Settings                                                 → Lane A
  Features/Rivals, Statistics, Suggestions, Compete, Bands  → Wave 2 lanes
apple/Sources/FestivalCore/   new domain files per lane (FestivalAPI+<Domain>.swift); edit an existing file only if your lane owns that domain
apple/Tests/**                tests for your own files only
apple/Apps/iOSUITests/**      frozen during Wave 1 (UX tests come at feature completion)
.agents/**                    → Lane D (Docs) restructures; other lanes only ADD new files under .agents/pages/<page>/ or .agents/controls/<control>/
tools/**                      → orchestrator
```

### Integration protocol

1. Lanes commit small, cohesive commits on their worktree branch (`lane/<name>`).
   Never squash with `git reset --soft origin/master` — worktrees share remote-tracking refs, so another lane's fetch turns it into a reversal of their work; check `git diff origin/master --stat` before pushing.
2. `tools/lane_integrate.sh` fetches, rebases onto `origin/master`, runs `swift build --build-tests` + the iOS build, pushes `HEAD:master`, and retries if another lane landed first. `--test` also runs `swift test`.
3. Simulator access **only** through `tools/ios_sim.py shot …` (global `flock`; one simulator at a time). Deep-link with `--tab`/`--route` (see `FestivalAppSupport/DebugLaunchRoute.swift`).
4. Lanes report back: what landed (SHAs), screenshots taken, open issues, seam changes needed.

---

## 2. Priorities (from operator, 2026-09-27; updated 2026-09-28)

- **UIKit Licenses (local lane):** The empty-dependency note remeasures when its pane narrows. In the actual Duo book pose, it now draws all four lines instead of clipping the last two. The Settings typography spacing still differs from SwiftUI.

- **UIKit Songs Filter (local lane):** The Score/FC disclosure opens separate Player Scores, All enabled charts and Individual charts groups. iPhone 18 Pro and folded Duo fixture journeys verify that a Lead-only check leaves the global check off, survives reopening, clears on Reset, and cannot be enabled while scores sync. Year and single-chart Stars put the named 44 pt bulk actions before the disclosure and remove them when it closes. Hiding the instrument buckets leaves no blank row before Reset. Expo confirms matching grouped fill and header order, not equal typography, spacing or animation. On the live service, SFentonX's Has FCs switch could be enabled and restored on both iPhone builds.

- **UIKit Songs player Retry (local lane, `a3ae8d4f5`):** The selected-player
  notice keeps a separate, full-safe-width text action with a 44 pt minimum
  target. At Large and AX5 on iPhone 18 Pro and folded Duo, the complete
  title paints and a tap in the padded area issues a new player request
  to the loopback service. The shared disclosure reserves a decorative
  icon column and uses native AX line spacing. The separate plated Shop
  Retry and the retained song order stay intact in the Shop failure journey.
  Twelve exact AX5 Explore pairs cover the initial, scrolled and song-row
  observations for 202 and 403. Initial iPhone differences above 16 RGB
  points fell from 32.90% to 12.96% and from 27.88% to 12.82% respectively;
  the final folded values are 12.96% and 12.68%. Scroll positions differ,
  so the captures establish the outcomes, not pixel identity.

- **UIKit First Run Songs persistence (local lane):** Normal-mode launches
  on both renderers and device families verify the stored lesson counts
  `0 → 5 → 6 → 6`. Removing just Navigation from the saved history presents
  only that lesson and records it again; the next cold launch goes straight
  to Songs. The single-lesson states expose Close and Done, without paging
  controls. Eighteen matched Explore pairs join to these exact saved-state
  checks. SwiftUI exposes the combined lesson as static text and UIKit
  labels its scroll view; this does not certify spoken VoiceOver.

- **UIKit compact Songs status (local lane, `309dbdd76`):** Player and band
  loading, syncing, unavailable and paused messages use a separate symbol
  and text column instead of an inline attachment. At AX5, the status fits
  below the art and Shop icons without reducing the text size. iPhone 18 Pro
  and folded Duo read back the complete syncing text at Large and AX5;
  the row remains a 44 pt or larger button and names the status once, before
  the Shop indicator. The Bass summary still replaces the existing song's
  score chips and restores them on returning to All Instruments.
  The default-size syncing text now begins at x=124 pt in both renderers.
  On folded Duo, Orbit wraps the same two lines and Pulse stays on one.
  The final 202/403 whole-frame differences on that build are 9.90%/9.86%
  on iPhone and 9.60%/8.86% on folded Duo, including earlier Retry changes.
  Centering the compact symbol on the wrapped block brings the folded
  202/403 glyphs within 0.91/0.41 pt of SwiftUI relative to their text;
  before centering they sat 7.91/8.41 pt too high. The AX layouts keep the
  symbol on the first line and still show the full status.

- **UIKit live Songs rows (local lane):** A filter that changes both membership and
  chart presentation now updates the surviving cards and their spoken summaries.
  The loopback Bass journey removes one song, changes the existing song from chart
  chips to a Bass summary, then restores both songs and the charts. Ten keyless
  Expo pairs compared anonymous, SFentonX, Has FCs, Lead with Has FCs, and confirmed
  deselection on iPhone 18 Pro and folded Duo. The fully unobscured songs matched
  in ID, order and spoken data; row pitch matched at 68, 142.33 and 182 pt for the
  anonymous, multi-chart and Lead layouts respectively. The sampled multi-chart
  chip bands matched at 1×. Publication endpoint observations were stable, not
  response-level proof. Background art differed and the stills do not certify
  whole-screen or animation parity.

- **Live invalid-score preference (local lane):** iPhone 18 Pro and folded
  Duo SwiftUI/UIKit all expose an enabled Over Threshold switch with the
  preference on; it remains unchecked. The three visible SFentonX rows
  match on both families with the preference on and off. Anonymous labels
  match on seven rows on iPhone and the four common folded rows; UIKit has
  seven AX-visible rows in the folded capture. All four arms observed
  publication 1847 at both boundaries, with pinning disabled. No invalid
  marker was sampled, so this proves the affordance, not score substitution.

- **UIKit Shop empty and error states (local lane):** Default-size iPhone text
  draws the filtered-empty subtitle on one line. On folded Duo the safe area
  moves the empty content's horizontal centre from x=233 to x=191 pt, matching
  SwiftUI, and keeps the two-line title and one-line subtitle clear of the rail.
  UIKit's first title line is still 8 pt lower on iPhone and 7 pt lower on folded
  Duo. The folded whole-frame differences above the 16-point RGB threshold
  went from 6.69% to 5.10% for genuine empty, 7.99% to 5.33% for error, and
  6.63% to 6.24% for filtered empty. These are fixed-backdrop fixture pairs,
  not pixel parity or a page-wide accessibility audit.

- **UIKit Notifications and accordion (local lane):** Notifications preserves native New/Older pinning, removes the extra system scroll-edge backing, and fades the text-aligned separator with its row. An aggregate notification marks itself read without leaving the sheet. The multi-chart message scales as one named button; the matched iPhone fixture row is 547 pt in UIKit and 549.67 pt in SwiftUI, with a different Tap Vocals wrap. The generated and never-generated empty states use the body safe area: on folded Duo both builds center at x=195 pt and the vertical centers differ by at most 2 pt in the generated case. The folded symbol size still differs. The controlled retry fixture (`5fc395c93`) reaches loading, error, retry loading and a recovered row on all four arms. The folded modal-header reading order remains open: the native rail moves Close out of the header and both raw snapshots list it before the title. That snapshot result does not prove spoken order. At AX5 a row can be taller than the available outer display. Normal Year recordings show resize before fade-in and fade-out before collapse, without a content flash. The SwiftUI reference still moves surrounding sections under in-app Reduce Motion on iPhone and folded Duo; UIKit keeps the snap and fade. A rapid repeat at the collapsed Year button's center does not prove interruption: the bulk actions move the button.

- **UIKit selected-account rail (local lane):** The folded portrait rail keeps the badged Notifications button and the named Profile button directly reachable. UIKit reserves the leading slot even ahead of higher-priority trailing items, so the selected-account drawer goes into a native overflow group. More → Menu still opens the drawer. An anonymous session keeps its direct drawer.

- **UIKit Profile sheet and header (local lane):** A Profiles result opens on the tab behind the sheet, without a second push animation. Notifications uses a dismissal completion for the horizontal account pill and reveals the destination during dismissal for the standalone rail bell. A viewed player keeps the native Select/Switch button before the account group on iPhone and directly after Back on the folded Duo rail. Profile Switch uses a page-relative native confirmation: Expo measures matching popup frames on both iPhone 18 Pro and folded Duo. On iPhone, the whole-screen share of pixels with any RGB channel differing by more than 16 dropped from 31.05% to 8.09%. Popup chrome and the chart behind it still differ. The native Profiles field exposes its active scope in its spoken label, not just its placeholder. Hosting the floating row inside the selected tab puts the page tools before the tab bar in iPhone snapshots for Songs, Song Detail and the viewed player. Spoken order remains unverified.

- **UIKit Compete guard and title (local lane):** All four fixture arms redirect an anonymous Compete launch to Songs and reach populated Compete with a selected player. In the selected comparison, pixels differing by more than 16 in any RGB channel are 2.24% on iPhone 18 Pro and 2.61% on folded Duo. The iPhone Profiles search pair has a named Searching indicator; the later screenshot on the SwiftUI arm is already empty, so only the indicator observation is comparable.

- **UIKit history charts (local lane):** Rank and Score History expose matching dates and values on the newest, previous and restored windows on iPhone 18 Pro and folded Duo. The shared viewport matches the reference tick gutters within 1 pt at default text and uses an 18 pt date band instead of reserving 22–24 pt; Rank History's date band grows at AX5. The viewport replaces the UIKit fades with the reference's 350 ms ease-out slide. Earlier Rank History recordings show 372/372 ms of visible plot changes for Back/Forward in iPhone UIKit versus 357/375 ms in SwiftUI, and 367/367 ms versus 335/332 ms on folded Duo. These are ~30 Hz samples, not exact durations. Score History paging preserves the chart frame and updates its accessible date range with and without Reduce Motion. Geometry tests cover retargeting and crowded dates; a rapid reversal on device remains unverified.

- **UIKit drawer deselection (local lane):** UIKit journeys verify that confirmation returns to anonymous Songs and the saved Songs tools reset and reopen without a tab change at default text and AX5 on both devices. Expo verified cancellation and confirmation in earlier pairs, and the repaired iPhone build; the latest folded Expo replay did not activate the confirmation reliably. Four taps 20 pt from the folded Filter button's centre open the sheet, outside its 38 pt glass frame. The floating tools stay constrained to their tab host when UIKit rebuilds the tab set. The Songs drawer row measures 48 pt at default text and grows at AX5 on both. The full AX5 drawer audit still reports one clipping issue without an element; it also reproduces on the pre-row-fix iPhone build and is not waived.

- **Live iPhone comparison (local lane):** Both builds showed the same leading Item Shop offers with and without SFentonX, and all three availability switches were on. The publication endpoint returned 1780 before and after each arm with pinning disabled. Both drew the Notifications title; UIKit's New header, first message wrap and row separator differed.

- **FentonPlatform consumer pilot (local lane):** UIKit uses shared observation, native Privacy Policy sheet placement and the shared native navigation controller. The cover-split pilot uses FentonUIKit pane containment while keeping the route and fold policy in Festival. The immutable pin is in `apple/Package.swift`; the split pilot's companion revision is local until accepted upstream. Settings and Licenses use the same usable midpoint on the flat Duo, separate at the hinge in book pose, and use an ordinary push in inner portrait. UIKit moved the open License page across the fold and Close returned to Settings. Expo also verified UIKit Close from Licenses in book pose; the SwiftUI replay rejected its Close target as off-screen. A separate Expo book-pose replay on both apps reached a full-width viewed Profile and used Back to restore the Lead rankings split. This is not a pose-wide accessibility audit. On folded Duo, Expo opened the Paths View picker and switched to loaded Text activations on both builds; an earlier XCTest tap had brought up the keyboard. The layout and Close fixes do not change picker behavior.

- **UIKit parity evidence (local lane):** Populated Player History uses separate score cards, shared Sort controls and the existing accessibility order. Closing Sort restores the floating action even when sorting changed while covered. Resizable sheets open expanded; UIKit Songs, Shop and History sheets use flat system grouped sections rather than nested page cards, respect the horizontal safe area and give choices and Reset full touch targets on iPhone and folded Duo. Filter disclosures use grouped-row spacing and line up expanded choices with the heading. A disabled Settings switch dims the label and prevents edits; split Close keeps its accessible name and follows app tint. The mixed-revision Explore ledger contains 596 image pairs, 436 with completed fingerprints. Both device families sample all 22 rendered routes and 58 of 251 Apple-applicable named control states; 64 states have a sample on at least one family. This is not a final-build or motion certification. Folded Duo Suggestions Filter opens and closes in both Expo recordings (SwiftUI opens it through More).

- **UIKit Search (local lane):** Paired Explore replays reached hint, loading, empty, All, scoped, failed and navigated on both iPhone 18 Pro and folded Duo. At the greater-than-16 RGB-channel threshold, hint differs on 0.92% / 1.12% of pixels and loading on 0.10% / 0.11%, respectively. The settled All captures (5.77% / 5.37%) predate the new row layout. In the Duo book pose, both keyboards are visible, with the field above them; the matched 951 × 669 hint frames differ on 0.06% of pixels. A separate UIKit inner-display journey checks the populated rows clear the hinge in row-major order. The iPhone fixture distinguishes no bands from a generic failure and confirms a scrape freeze retries the same query without a Retry button. Live Search for `Metallica` in All scope with the keyboard open shows the same four fully visible results on iPhone and two on folded Duo, anonymous and as SFentonX. The row pitch matches at 68 pt and the remaining top offset is 0.67 pt after removing the reference List's 2 pt row inset. All four arms ended at observed publication 1787 with pinning off; this is not proof that all payloads were from one publication. In the paired iPhone recordings, one down-scroll displaces the same first four results and reveals the next four in order. Stagger interruption and exact entrance timing remain unverified.

- **UIKit First Run and Rivals (local lane):** 17 of 42 guide slides use read-only native previews: Song List, Songs Sort, Navigation and Filter, Instrument Icons, Song Metadata, the three Songs Shop statuses, the four Item Shop lessons, Score History list and Sort, and both Suggestions Filter slides. The other 25 slides still use static substitutes. Both renderers keep catalogue artwork and illustrative Shop status without exposing the selected profile's score warnings in the examples; real Songs still shows the warning on a publication mismatch. Twenty fingerprinted Explore pairs include anonymous and selected Song List and Shop illustrations on iPhone 18 Pro and folded Duo. Compared with SwiftUI built with the same score correction, whole-frame differences above the RGB threshold are 6.08–10.18% on iPhone and 16.81–21.12% on folded Duo. The final four-arm Item Shop replay records all four lessons through Settings, with matching narration and no exposed sample rows. Its eight screenshot pairs differ on 7.99–9.44% / 13.06–15.86% of pixels, respectively. The recorded activity windows include pager movement and icon pulses; they do not isolate animation durations. Rivals uses native single-line label height and the shared subdued chevron tint; earlier iPhone Rivals/Rival Detail pairs differ on 1.87% / 1.44% of pixels at the same threshold.

- **UIKit Suggestions and Notifications comparisons (local lane):** With SFentonX and all nine chart switches enabled, both live iPhone builds show three identifiable Bass rows and one Drums row in the sampled viewport. Both exclude those charts when disabled, and both restore their original switches. Switch pitch is 58 pt; live card and row widths are respectively 370 and 338 pt. Observed publication 1787 was stable at the start and end of each arm, with pinning off. Compare eligibility and geometry, not whole-screen pixels when the mix differs. The matched iPhone multi-chart Notifications capture differs on 9.86% of pixels at the same greater-than-16 RGB-channel threshold. Folded rail and AX5 evidence are tracked separately.

- **Folded Duo live Compete and Rivals (local lane):** The UIKit Lead card showed song counts where SwiftUI from `master` hid them, truncating names. UIKit now fits each 350 pt card beside the rail; the corrected live capture matches all seven fully visible ranks, names, scores, and spoken counts and their frames within 0.01 pt. Six Lead Rivals rows matched in identity, order, counts and pitch. The UIKit capture included a Common Rivals scrape freeze above Lead, so the 108 pt vertical difference is not a same-state layout comparison. The anonymous drawers matched and omitted Compete and Rivals. Observed publication 1791 stayed unchanged with pinning off; that does not establish response provenance.

- **UIKit live Leaderboards (local lane):** The earlier blank anonymous UIKit captures were not layout comparisons. A settled production recheck on iPhone 18 Pro finds the same 11 visible rows with identical names, ranks, scores, order and accessibility frames in both apps, anonymous and as SFentonX. The selected case includes Your Rank. Different album art behind the list is not a layout failure and invalidates a whole-frame equality score.

- **UIKit live Profile and Statistics (local lane):** The anonymous iPhone picker puts
  the search field and All / Players / Bands in the same frames; the title frame and
  the selector's spoken name differ. With SFentonX injected in memory, the five summary
  values and the Lead rank-history data match. In the original UIKit capture, Full
  Combos wrapped and added 24 pt to the first row; the chart began 22 pt lower.
  The rebuilt UIKit app shows the full count and percentage on one line. A live
  recheck puts all five tile frames within 0.01 pt of the SwiftUI capture; the
  Lead chart starts 2 pt higher. On both device families, fixture coverage shows
  the full value at default and largest accessibility text. Songs Played
  applied the same nine score checks and revealed the same four fully visible songs.
  UIKit's chip circles in those rows were 12 pt farther right; the card pitch was
  0.67 pt taller. After correcting the empty trailing layout and single-line
  text rounding, the sampled gold Lead chip edges match exactly on both axes
  in both compact fixture rows on iPhone and folded Duo. The paired live captures
  used different artwork and observed publication 1791 with pinning off. They
  do not verify the production picker selection or a single response publication.

- **UIKit folded live Statistics (local lane):** More → Menu → Statistics with
  SFentonX shows the same five values and tile frames within 0.01 pt on both
  builds. Songs Played reaches the same three fully visible song rows and spoken
  statuses. In a live UIKit recheck, both chip bands in all three rows match the
  SwiftUI horizontal edges at 1× capture scale; the chip bands still differ by
  up to 2 pt vertically. The original UIKit index was 18 pt too tall and its
  centre was 23 pt low. The corrected frame is 22 × 398 pt at (358, 122) in both
  renderers. Different artwork precludes a whole-frame visual comparison.
  Loopback captures confirm the corrected capsule reaches both ends at default
  and AX5 on both devices; folded AX5 rail alignment and the final scroll landing
  still differ slightly.

- **UIKit Profiles sheet (local lane):** the native field and All / Players /
  Bands buttons match their live SwiftUI frames and order. Using the shared
  `UKSheet` removed the oversized UIKit title: the title's 3× foreground
  pixel mask matches SwiftUI on iPhone and folded Duo, at rest and with the
  search keyboard open. This is title evidence, not full-sheet pixel equality.
  Both iPhone 18 Pro and folded Duo pairs selected SFentonX through the live
  picker, restored the profile after relaunch and deselected it. Within each
  live pair, the field, three scope buttons and Close have identical accessible
  frames. Loopback journeys also verify
  that Statistics opens the restored account and Back on folded Duo returns to
  Songs, where the drawer can deselect it.

- **UIKit ranking guides (local lane):** Global Rankings, Compete Leaderboards and
  Your Rank use the same illustrative rows as SwiftUI, bringing the UIKit guide to
  20 of 42 native previews. Expo paired all three slides on both families. At the
  greater-than-16 RGB-channel threshold the differences are 6.20–6.64% on iPhone
  and 11.23–13.63% on folded Duo. Backdrops differ; on folded Duo the preview
  itself also begins about 6 pt lower in UIKit. The visible Global Rankings CTA
  stroke on iPhone repeats about every two seconds on both renderers. Folded Duo
  crops the CTA out of these stills, so they do not verify its pulse.

- **UIKit Statistics guides (local lane):** Global Statistics, Per-Instrument Stats,
  and Percentile Rankings reuse the native tiles, instrument header and percentile
  rows. The sample actions stay out of the accessibility tree. Expo's six exact-state
  pairs differ on 6.95–8.12% of pixels on iPhone and 10.20–13.34% on folded Duo above the same RGB
  threshold. Starting the UIKit fade with the pager removes the visible jump in
  the incoming percentile table. The 30 Hz instrument/table activity windows
  drop from 700/733 ms to 400/400 ms on iPhone (SwiftUI 434/466 ms), and from
  1,100/1,067 ms to 800/766 ms on folded Duo (SwiftUI 900/834 ms). These are visible
  changes in a preview crop, not isolated animation durations. Swiping to
  Percentile Rankings and going Back preserve the selected page; UIKit exposes
  just the settled narration before the pager. SwiftUI's settled default-size
  snapshot also lists its caption's title and description separately; spoken
  duplication was not measured. Select Player Profile and Drill Into Your Data now
  draw the example player and actual stat tiles, bringing UIKit to 25 of 42 native
  previews. Both renderers hide the illustrative Select button from accessibility;
  UIKit verifies narration and pager order at AX5 on both devices. In four paired
  Expo stills, Select drops from 16.96% to 8.67% differing pixels on iPhone and
  from 17.44% to 11.61% on folded Duo; Drill drops from 16.21% to 8.75% and from
  13.18% to 12.45%. Video samples show a 2 s Drill outline period on both devices
  and a 2 s Select period on folded Duo in both renderers; the iPhone Select crop
  did not isolate the pulse reliably. The sheet backdrops still differ.

- **UIKit Statistics Top Songs guide (local lane):** All six Statistics lessons now
  have native previews, bringing UIKit to 26 of 42 across the app. Highest and
  Lowest Rank Breakdown shows catalogue art, title, artist and year, with sample
  percentiles fixed to their slots. The mock-unavailable catalogue redacts the
  songs without hiding the example ranks. UIKit and SwiftUI keep the samples out
  of the accessibility tree; UIKit also keeps AX5 narration ahead of the pager.
  Expo shows two rows rotating and the sample labels staying in place. At 30 Hz,
  the observed gold-label fade/recovery windows are 600–667 ms in SwiftUI and
  666–667 ms in UIKit, not the nominal animation lengths. Reduce Motion kept cards
  fixed between captures. On matching Reduce Motion stills, 8.21% of iPhone pixels
  and 15.87–15.95% on folded Duo differ above the greater-than-16 RGB threshold.
  Gold labels are 1 pt lower in UIKit on iPhone and 14 pt higher on folded Duo;
  backdrop and folded narration layout are not visually identical.

- **UIKit Song Info score guides (local lane):** View Player Scores and Top Scores
  Per Instrument reuse the native score rows, the in-card View All action and the
  shared pulse, bringing UIKit to 28 of 42 native previews. The illustrations use
  sample data, not the selected player's scores. SwiftUI no longer exposes the
  decorative sample ranks, dates or CTA in the guide's accessibility tree.
  In matched Expo captures the iPhone illustration crops improved from 48.32%
  to 6.62% and from 40.74% to 16.67% differing pixels (any RGB channel delta
  above 16). Folded Duo still places the View All Scores button 16 pt lower
  and both renderers clip the Top Scores CTA out of the regular folded viewport.
  Native recordings show a 2 s border period in the visible cases and pager-plus-
  entrance change windows differing by at most 65 ms over the six paired transitions.
  The mixed-revision ledger now includes 630 paired stills: 460 with completed
  replay fingerprints and ten additional fingerprinted live Songs pairs with
  verified snapshots. Named-state coverage remains 64 of 251 Apple-applicable
  states (58 on both families). This does not certify full visual or motion parity.

- **UIKit Song Info chart, Paths and Shop guides (local lane):** All eight Song Info
  lessons now use native illustrations. The chart selection cycles through sample
  scores, the Paths example draws labels without creating menus, and the Shop
  examples use the catalogue preview without opening the store or fetching offers.
  An already-open UIKit Paths viewer updates its title and selectors between folded,
  inner portrait and book layouts even if the chart mode is unchanged. The iPhone
  Settings guide scrim preserves the blue of the Show buttons without making them
  hittable. Eleven additional exact-state Expo pairs bring the mixed-revision ledger
  to 641 (471 with completed replay fingerprints). The refined iPhone capture aligns
  the gold bar baseline at y=454 pt in both renderers and reduces the chart crop from
  9.58% to 4.39% differing pixels above the same RGB threshold. The refined Paths
  crop differs on 1.22% of iPhone pixels and 15.11%
  on folded Duo. The folded chart baseline is still 4 pt higher in UIKit.
  Recorded iPhone Shop discs cycle in about 3 s; folded Shop uses a titled capsule
  instead. Both folded captures now wrap "Item Shop" onto two lines, with UIKit's
  narration title 6 pt lower. UIKit keeps the guide Back chevron blue.
  Differently selected chart bars are excluded from still comparisons. Under Reduce
  Motion the selection crop was unchanged over at least 6.4 s in all four replays
  (67,200 iPhone pixels and 47,762 folded Duo pixels per renderer), and Back
  returned to the chart overview.

- **UIKit Suggestions guides (local lane):** The category and scrolling lessons
  bring native preview coverage to 36 of 42 lessons. They reuse native cards and
  bounded catalogue songs, not the selected player's scores or suggestions.
  The category keeps its heading inside a short viewport,
  and SwiftUI no longer exposes the decorative heading as a separate stop. Two
  fingerprinted Expo still pairs show the same category and songs; at the existing
  RGB threshold, the illustration crops differ by 9.02% on iPhone and 18.89% on
  folded Duo. The heading aligns on iPhone and remains 4 pt higher in the earlier
  folded UIKit recording. The recorded scroll speeds are about 29–30 pt/s; stills
  taken at different phases were excluded. Longer folded recordings show five
  headings returning after about 35 seconds in both renderers, with glide rates
  of about 30 pt/s. Back returns to Per-Instrument Filters and Next returns to More
  Suggestions in both; the original SwiftUI opening checkpoint temporarily
  reported the narration as not hittable. These samples do not establish exact
  fade timing or matching initial positions after re-entry.
  On iPhone, SwiftUI and UIKit recorded 28.17 and 28.70 pt/s, respectively.
  The same four observed headings returned in about 31–31.5 seconds. UIKit's
  Back and re-entry checkpoints passed; a shorter replay verified both steps on
  both renderers after the long SwiftUI recording timed out following Back. The
  Reduce Motion illustration crops on both families did not change over
  approximately eight seconds. The folded SwiftUI narration was present in the
  raw tree but was not reported hittable; the pixel comparison does not verify
  its VoiceOver focus.

- **Live folded Suggestions filters (local lane):** With the selected profile, both
  builds show three Bass, one Drums and one Lead result in the visible accessibility
  sample when both switches are on. With both off, the same sample contains one Lead
  result and no Bass or Drums. The captured switch values confirm each state and
  restoration of both installations' original preferences. Suggestions are compared
  by eligibility and visible structure, not the names or order of randomly picked
  songs. The public publication observation was 1799 with pinning off; this does
  not verify per-response provenance.

- **UIKit competition guides (local lane):** All 42 First Run lesson IDs now
  dispatch to native previews. The remaining six use shared Rank By choices and
  sample Compete, Rivals and Head-to-Head rows; illustrations never read the
  selected player's ranks or rivals. UIKit journeys on both device families cover
  the automatic experimental setting, ungated Settings replay, sample content and
  AX5 narration with an unavailable catalogue. On a folded Duo, both renderers
  keep the Head-to-Head category heading visible at AX5 without adding a narration
  stop. In Explore recordings, stable Rank By selections change roughly every
  five seconds on both families. Before centering the UIKit preview, its iPhone
  radio centers were 6 pt lower across the three observed matching choices,
  including in a settled Reduce Motion capture. With the centered card, both
  renderers draw "Rank By" at y=302 pt and the first choice at y=328 pt. The
  narration title differs by 2.09 pt instead of 14 pt. At short heights and
  accessibility sizes, the preview prioritizes showing the first choice over
  centering a cropped card. On folded Duo the first choice remains 16 pt lower
  in UIKit.
  In the matching iPhone Compete Hub leaderboard phase, the four visible sample
  name positions differ by at most 1 pt. The folded captures opened at different
  sample phases and are not a visual pair.
  The original SwiftUI Your Rivals illustration clips the first sample name; UIKit
  starts with the group heading and first row visible. The earlier 12–16 pt
  iPhone Head-to-Head offset came from comparing a fading frame with a settled
  one. With Reduce Motion and the same Closest Battles content, both category
  headings and the first song agree within 0.2 pt; the next two titles remain
  about 2 pt lower in UIKit. Folded Duo still presents different clipping:
  UIKit keeps the category heading visible, while the SwiftUI reference shows
  more of the third title without drawing the heading. These comparisons do not
  establish pixel or full-motion parity.

- **Live Lead Score History (local lane):** The same song has no personal history
  when anonymous in either renderer. With the selected profile, the newest window,
  one entry earlier and the restored window have matching date ranges, axes, best
  score, five score rows and pager availability on both device families. The chart
  frame matches within each family, the four pager targets are 44 by 44 pt, and the gap
  below the pager is 15 pt in every state. Both renderers observed publication 1799
  with pinning off; this is not per-response provenance.

- **Live Item Shop (local lane):** In the `fdae26230`-equivalent builds, SwiftUI
  and UIKit showed the same offers in order with no profile and with SFentonX
  selected; accessible offer frames matched on each device. Ten iPhone and
  eight folded Duo offers fit before filtering and after restoration; five fit
  with Available off. Both builds restored all three switches and the original
  order. Only the selected header opened Notifications. The fully visible
  iPhone aggregate row starts at y=192 pt, is 402 pt wide and measures 549.67 pt
  in SwiftUI vs 546 pt in UIKit. Neither folded app had a fully contained
  aggregate row. Matched Shop row crops over the flat backdrop differed by
  2.09–4.31% on iPhone and 2.22–4.24% on folded Duo before filtering (any RGB
  channel differing by more than 16). All arms observed publication 1801 before
  and after with pinning off; this is not response provenance. The replay
  re-injected the verified identity and did not retest persistence.
  An earlier folded fixture replay put the same New and Leaving rows over a fixed
  backdrop. Removing the invisible New marker from the UIKit accessory layout
  corrected the New bag's trailing inset from 35 to 26 pt. Both 44 pt bag targets
  now have the reference inset. With the corrected symbol sizes and chevron tint,
  accessory-crop differences fell from 7.49% to 2.96% for New and from 6.55% to
  2.72% for Leaving (any RGB channel differing by more than 16). The Leaving
  subtitle now truncates at the same word; text pixels still differ.
  A later loopback replay held the initial Shop read until the named 48 pt busy
  indicator was observed, returned a controlled error with Retry, then held
  the retry until its indicator appeared before releasing the exact two offers.
  Both renderers completed that sequence on both device families with motion
  disabled. UIKit's spinner was 13.3 pt below SwiftUI's on iPhone and 42 pt
  right / 24 pt above it on folded Duo. The shared UIKit gate now aligns to
  the result safe area without moving the scroll content. Held-load journeys
  put its single 48 pt busy indicator within 4 pt of the reference vertically
  and 2 pt horizontally on both families. At AX5, the folded empty message
  can scroll to reveal the full subtitle; the rail no longer covers it.
  In motion-enabled Expo recordings, an independent 1.25 s loopback hold let
  both renderers recover the same two offers after Retry. UIKit originally
  revealed the two offers together. With the shared entrance scope, the sampled
  interval between offer text onsets was 102 ms on iPhone and 113 ms on folded
  Duo (SwiftUI: 104 ms and 133 ms). The first offer still crossed the visibility
  threshold 16 ms earlier on iPhone and 63 ms earlier on Duo. These are sampled
  video crossings, not exact animation durations.
  A later unfolding replay found List cells retained under a Grid toolbar label.
  UIKit now reloads retained offer IDs when the presentation changes. The same
  replay reaches Grid, List and restored Grid without stale Detail actions.
  The native wide-display journey confirms a single full-card link in Grid and
  separate Detail and Shop link targets in List. The first reference and
  candidate screenshots used different framebuffer orientations and are not a
  matched visual pair.
  Matched 951×669 landscape Expo captures show that UIKit's Shop List now
  clears the book hinge: the trailing row start moved 56.33 pt and matches
  SwiftUI, with all measured List edges within 0.34 pt. The second Grid
  card ends 1.33 pt from the reference instead of 29.33 pt; its top is still
  3 pt higher. Flat layout geometry is unchanged. The native journey bends
  from flat to book and back in both modes, keeping the named links hittable.
  These are settled fixture frames, not matched animation timing.
  A later 669×951 inner-portrait replay paired Grid, List and restored Grid
  against exact SwiftUI `master` (`291d884e5`). Explore stored UIKit's frames
  sideways; the upright accessibility viewport and raw 3× framebuffer verified
  the quarter-turn correction (0.06% of pixels differed above 16 after sampling).
  Grid, List and restored Grid differ by 6.05%, 3.11% and 6.09% respectively.
  Explore reports the List Shop actions as Buttons in UIKit and Links in SwiftUI;
  labels and 44 pt frames match. A non-skipped native journey on the upright
  inner display finds those UIKit actions as Links in Grid, List and restored
  Grid. UIKit now feeds actual hinge and vertical bar signals into the shared
  orientation policy. Debug poses do not unlock rotation on a standard iPhone.

- **UIKit Apple parity evidence (local lane):** The mixed-revision ledger has
  940 device-matched pairs, 768 from completed Explore cases with build fingerprints. All 22
  rendered routes have samples on both families. Of 251 applicable named states,
  128 have a sample and 116 have one on both families. The Solo board shows low
  (24%), mid (50%), high (98%), full combo with and without accuracy, and no
  badge in the same six rows. The score right edge is identical within each
  device pair, including the empty slot. Both FC outlines have the same
  painted bounds and pixel counts; UIKit's italic lettering has more gold
  ink. UIKit's row wrapper was not hittable in Explore; the raw snapshots
  and painted pixels independently verify those samples. In matched Score History
  captures, Lead has the selected accessibility trait and its chart is named
  for Lead; Bass and Drums are available on both. A separate iPhone replay
  switches Lead → Bass → Lead with and without Reduce Motion. It updates the
  selected instrument and chart name, hides and restores the pager, and keeps the
  best-score row at y=603.33 pt in both apps. Without Reduce Motion the shared
  bar-ink samples nearly vanish between instruments; with it they stay above
  95% of their settled value. These samples are not exact animation durations.
  The corrected UIKit axis draws 250k/500k/750k for Lead and 200k/400k/600k
  for Bass, matching the fixture's Swift Charts ticks. Native switch journeys
  read these painted labels in both motion modes on iPhone 18 Pro and
  folded Duo, with named scales, no separate tick reading stops, and unchanged
  score-row position. The top 100% label centers on the plot edge. The
  corrected still pairs match at 342×220 pt on iPhone and 322×220 pt on folded
  Duo; the folded best score stays at y=569.33 pt. On iPhone, pixels
  inside that frame differ above 16 in any RGB channel on 1.62% of Bass and
  1.96% of Lead pixels (about 11.4–11.6% for the full frame); the two scopes
  are not interchangeable. In those recordings, the sampled 90% → 10%
  fall takes 116–117 ms in SwiftUI and 84–100 ms in UIKit. With Reduce
  Motion the sampled ink stays at or above 95.1% in all four iPhone
  transitions. Folded Duo's sampled fall is 116–117 ms in SwiftUI and
  100–117 ms in UIKit; with Reduce Motion it stays at or above 96.1%.
  Loopback Songs cases match
  the spoken score, accuracy and FC-only conditions; the whole-frame RGB
  differences above 16 range from 4.08% to 4.90% on iPhone and 4.49% to 5.09%
  on folded Duo. At AX5 the scrolled captures show readable stars and wrapped
  Last Played. The two date lines now start within 0.1 pt of one another on both
  UIKit devices, down from more than 63 pt. The pill still aligns with the Shop
  badge. This crop does not establish above-the-fold score visibility. The
  captures are samples, not identical pixels or proof of every state and timing.

- **UIKit Paths held switches (local lane):** Both device families reproduce
  the 48 pt UIKit pane ring against SwiftUI's 36 pt ring in Text and Image.
  UIKit now uses the shared medium ring without changing placement or phase
  timing. The corrected painted bounds match at 36 × 36 pt on both devices
  in both states. Explore checked the exact saved accessibility tree against a live
  held request: one named spinner, current selectors, no stale chart or error.
  The native audit and target checks pass for both holds on both devices.
  The sampled 90% → 10% arc fade is 166/167 ms for Text and 169/170 ms for
  Image on iPhone (SwiftUI/UIKit), and 169/172 ms and 169/168 ms on folded Duo.
  Separate live recordings during fixture-confirmed holds fit 798–800 ms
  rotations on both renderers for both forms and devices. Live 90% → 10%
  fades differ by at most 5 ms within a device/form pair. Still-backdrop
  replays can drop seconds of video frames during a hold; the live SwiftUI
  measurements use the fixture clock without querying accessibility.
  Neither those clips nor the held accessibility snapshots establish the
  full transition.

- **UIKit Paths AX5 selectors and offline state (local lane):** The named
  instrument artwork stays at its reference size rather than growing with its
  label. The View symbol uses the current body size and the foreground tint.
  At AX5 the iPhone's held Text and Image captures now match the SwiftUI
  painted glyph heights. Whole-frame differences above 16 in any RGB channel
  fell from 3.63% to 1.65% for held Text, 3.37% to 0.46% for held Image and
  3.94% to 0.79% for the settled chart. On the Duo cover, the View capsule
  now matches SwiftUI at 83⅓ pt for Text and 73 pt for Image, with 6 pt
  above and below both glyphs. The earlier 63 pt UIKit capsule let Text
  paint outside its bounds despite a passing audit. The corrected AX5
  held frames differ above 16 in any RGB channel on 0.15% of pixels for
  both Text and Image. The loopback fixture distinguishes a reset
  connection on Medium from a 404 and keeps Expert reachable. On iPhone
  and folded Duo, both renderers show "You're offline" and Retry in each
  failed form, with no stale chart; switching back to Expert restores its
  image. The corresponding folded offline frame differences are 0.72%
  for Text and 1.21% for Image.

- **UIKit Paths physical Duo layout (local lane):** Native `XCUIHinge`
  drives the same viewer from 180° flat to 90° book, 0° cover and back
  to flat, checking the angle, live window and lit panel independently.
  UIKit previously kept a stale View menu in book pose after presenting
  the viewer full screen. The window now publishes the layout even
  when the root is detached. Both renderers remove View and clear the
  hinge in book pose, fall back to Image on the cover and restore the
  selected Side by Side on return without opening a new viewer.
  On the flat inner panel, UIKit now matches SwiftUI's three 273 × 44 pt
  named selectors at the same positions, before and after refolding.
  The physical frame differences above 16 in any RGB channel are
  1.21% flat, 1.55% book, 0.22% cover and 1.23% flat return.

- **UIKit Songs paused Shop sort (local lane):** The retained list uses plain
  rows for the pause, failed read and Retry, ahead of the title-ordered songs.
  The Duo cover plate extends under the rail without moving its content into
  the rail. On iPhone 18 Pro and the Duo cover the paused pairs differ above
  16 in any RGB channel on 4.62% and 4.98% of pixels, down from 22.59% and
  31.82%; the disabled-selected Sort sheets differ on 0.55% and 1.04%. Both
  native journeys verify the named notices, their order, retained row order
  and a reachable 44 pt Retry at default size and AX5. The fixture replays
  also verify the saved mode across unavailable, validated-empty and
  recovered Shop feeds; the recovered groups differ on 1.76% and 0.83% of
  pixels in the earlier recovery build. A live 180° → 0° → 180° UIKit
  journey revealed notice text under the cover rail despite a correct cold
  launch. The notice and divider now follow the live safe area. The native
  framebuffer confirms readable notices and a reachable Retry on the
  951 × 669 pt inner display and the 466 × 678 pt cover without relaunching.
  A later cold-launch frame exposed a separate height error: the failure
  plate was measured for two lines before it inherited the rail inset, even
  though the final width needs three. The notice cell now fits its content at
  its live safe width and invalidates its size when the insets change. Native
  Duo runs require the three-line plate both cold and after a physical fold;
  the settled cold Explore frame shows all three lines.

- **UIKit Songs Sort visibility and largest text (local lane):** Both apps
  preserve the saved Item Shop sort when the Settings switch hides the choice
  across relaunch, and restore its selected trait and grouping when shown
  again. The earlier visibility replay's hidden sheets differ above 16 in any
  RGB channel on 0.61% of iPhone pixels and 0.68% of Duo pixels. The selected
  player with all charts does not get player modes; selecting Lead enables
  Score, Percentile and Stars, including through the native More menu on the
  cover. The paired Duo recordings index frame-change windows for More,
  Sort, Filter and Close; those windows are not isolated animation durations.
  Both device families now keep the inline modes at 52 pt pitch at
  default text and about 93 pt at AX5, with a named, selected or disabled
  button as appropriate. A two-line Reset keeps its text clear of the card
  corners and settles with the native 20 pt gap above the bottom safe area.
  At AX5 the shared Direction arrows now match the SwiftUI painted width
  of 40 pt and height within 1 pt. Ascending uses the same hyphenation and
  description line breaks on each device. Both native Songs journeys verify
  the named direction selection at default and AX5. The AX5 top frames
  differ by 0.75% on iPhone and 0.51% on the cover; the bottom frames differ
  by 5.00% and 4.51%, down from 5.46% and 5.55%. The folded UIKit title stays
  pinned, unlike the scrolled SwiftUI capture, and the first Reset glyphs
  still show a small rounded paint cut. These are settled frames, not
  animation measurements.

- **What's New lifecycle (local lane):** Seven fixture checkpoints on iPhone 18 Pro
  and the Duo cover show First Run holding the launch slot, the release notes opening
  after it closes, dismissal persisting through a real relaunch, and Settings Show
  opening the same notes again. Compact has Close and Dismiss; the Duo cover has
  the single rail Close. The original compact launch and replay sheet pairs differ
  by more than 16 in an RGB channel on 1.00% and 1.02% of pixels, respectively;
  the corresponding Duo cover figures are 0.37% and 0.27%. The compact Settings
  replay recordings show the same slide direction. Sampled screen changes span
  335/305 ms on Show and 165/133 ms on Close on iPhone, and 368/332 ms and
  128/167 ms on the Duo cover (SwiftUI/UIKit); these are not animation durations
  or easing measurements. Native Settings replay also exercises a synthetic
  slow install-channel answer: one named activity indicator and no notes
  while pending, then tester notes with Close still available. The painted
  ring is 48 × 48 pt and has identical bounds within both device pairs. The
  four motion-enabled native recordings fit an 800 ms revolution.
  The corrected UIKit sheet keeps the compact 46 pt Dismiss control and the
  reference note's line break on iPhone 18 Pro and the Duo cover; the compact
  AX5 journey also keeps its accessible note and dismissal order. In the
  corrected Explore pairs, the launch and replay sheets differ above the same
  threshold on 0.41% and 0.40% of iPhone pixels and 0.32% and 0.70% of Duo cover pixels.
  Closing the replay restores the same Settings Show row position within each
  arm; the renderers started at different scroll offsets on both devices.

- **UIKit Songs after launch sheets (local lane):** On iPhone 18 Pro, dismissing
  the cover returned an unknown hinge status without a rail or division. UIKit
  used to interpret that as a fold and draw the Duo field at the bottom until
  relaunch. The shell now ignores unknown hinge status, leaving one hittable
  native Filter Songs field above the list after First Run and What's New.
  On both iPhone 18 Pro arms the field now measures 370 by 44 pt at (16, 116).
  The matched post-dismiss frame's pixel difference fell from 27.11% to
  1.79% above the same channel threshold; the whole frame is not pixel-identical.
  The physical Duo retains its folded rail and filter; the standalone Duos
  pager still follows the active divide through flat, book, and back to flat.

- **UIKit physical Duo split reflow (local lane):** Returning from book to flat
  could report the final pane to accessibility while the inner framebuffer still
  clipped the Duos entry count, names and spotlight roster. The shared split host
  now lays out both existing FentonPlatform panes and their safe areas in one
  nonanimated update, without changing intentional navigation transitions. At
  the first sampled flat geometry, all four text readings match the SwiftUI
  reference; the selected row, page 2, footer clearance and six Close-edge taps
  still pass. This does not resolve the separate unattributed compact text audit.

- **UIKit Songs Sort persistence (local lane):** Explore observes Descending
  selected, Fixture Pulse before Fixture Orbit after Done, and the same order
  after relaunch on both renderers and device families. UIKit exposes
  `Title, descending` as the value; folded SwiftUI speaks the same state in
  the label (`Sort, Title, descending`), because the system toolbar can drop
  a separate value. The shared native journey now verifies the applied mode,
  tint and direction through a real relaunch and Reset on all four arms.
  The recorded open/close change windows (SwiftUI / UIKit) were 401 / 402 ms
  and 185 / 233 ms on iPhone, 390 / 403 ms and 185 / 208 ms on folded Duo.
  These are sampled frame-change intervals, not easing or exact durations.
  At AX5, the shared grouped text action now leaves corner clipping to the
  group. Fingerprinted iPhone and folded Duo captures show the full leading
  stroke of the second Reset line without moving or resizing the button.
  Native journeys verify the paint, Reset action, Shop Filter footer and
  sortable Score History on both devices.

- **UIKit grouped forms beside the Duo rail (local lane):** The folded sheet's
  safe area already supplies the rail-side gutter. The shared group form no
  longer adds 16 pt there; compact iPhone retains its original margins. The
  folded Sort direction control ends 40 pt before Close as in SwiftUI, and the
  selected-score Filter and Sort Reset journeys pass on both UIKit devices.
  Correcting the gutter alone reduced the folded selected-sheet difference
  from 3.55% to 2.94% of pixels with any RGB channel off by more than 16.
  Including separators within the row height and matching the group spacing
  and arrow tint reduced that further to 0.67%; iPhone improved from 2.64%
  to 0.60%. The matched direction frames differ by 1/3 pt vertically. Remaining
  differences include the selected checkmark, arrow rasterization, and Reset's
  placement (about 1 pt). The same corrected build's matched Shop Sort sheet
  differs on 0.69% / 0.88% (iPhone / folded Duo); Shop Filter on 1.42% / 1.50%.
  The expanded Songs Double Bass Filter now indents revealed labels by 20 pt
  without moving their switches, draws the dividers, and uses the smaller
  disclosure chevron. Matching the General heading tint, wrapped hint spacing,
  and the padding inside the tappable disclosure header brings the difference
  from 3.75% / 3.80% to 1.39% / 1.33%. The first revealed label is within
  0.5 pt vertically in both pairs; Year, Duration, and Item Shop start at the
  same heights. The default-size Double Bass, Year, and Stars journeys pass
  on both UIKit devices. At the largest text size the iPhone audit passes;
  the Duo reports the same unattributed hit-area finding as the pre-change
  UIKit build and is not certified. The native Score History Sort journey
  uses the Duo toolbar's overflow when necessary, then verifies
  the selected date direction, sorted rows, and retained form state on reopening
  on both device families in both renderers.

- **UIKit grouped form details (local lane):** A revealed bulk header uses the
  28 pt titled gap; closing it restores the 35 pt untitled gap. Interior
  dividers follow the choice labels. On the matched Duration Filter, pixels
  with any channel off by more than 16 fell from 6.35% to 1.78% on iPhone
  and 4.99% to 1.51% on folded Duo. The native Duration, Year, Stars, and
  shared accordion journeys pass on both UIKit devices. From the original
  four native recordings, the Duration switch's visible 10–90% blue ramp
  was 72/83 ms (SwiftUI/UIKit) on iPhone and 85/83 ms on Duo. Item Shop's
  was 85/84 ms and 66/83 ms. These sample the painted switch, not the
  complete disclosure animation. The independent folded SwiftUI AX5
  hit-region journey passes with neutral fixture settings. UIKit passes
  the independent folded Dynamic Type audit, but the collapsed-top
  hit-region result still has no identifier, label, or frame. The scoped
  pre-audit tree shows a 318 × 264⅓ pt Year button and only 12⅔ pt of
  the Duration button intersecting the viewport. The audit does not
  identify Duration or any other control; the finding remains open.
  The Shop Filter footer and wrapping disabled Shop Sort explanation now
  match the reference group placement and preserve a named disabled choice.
  The matching footer frames differ on 0.64% / 0.79% of pixels (iPhone /
  folded Duo); the disabled Sort frames on 0.60% / 0.96%, using the same
  RGB threshold. The native footer and disabled-row checks pass on both.

- **Songs Item Shop Filter lifecycle (local lane):** On iPhone 18 Pro and
  folded Duo, both renderers keep Available enabled, turn Not Available off,
  and show only Fixture Pulse after applying and relaunching. A failed feed
  pauses the saved filter and exposes Retry without hiding the catalogue.
  A validated empty feed instead shows No Results. Recovery reapplies the
  saved choice. Seven fingerprinted pairs per family differ above the RGB
  threshold on 0.55–4.66% of iPhone pixels and 0.56–5.19% of Duo pixels.
  In the iPhone recording, the Double Bass row moves before the Item Shop
  choice label fades in. At actual frame timestamps, 10–90% of that
  movement spans 156–184 ms in SwiftUI and 86–119 ms in UIKit. The label's
  10–90% ranges overlap (78–85 ms and 66–100 ms); it starts later relative
  to the 90% movement mark in UIKit. These are sampled paint thresholds,
  not exact durations or easing.

- **Songs Title and Artist indices (local lane):** On iPhone 18 Pro and the
  Duo cover, both renderers start Title at `#` and an index drag exposes
  Zenith Garden. Artist starts at `A` and the drag exposes Yonder Garden
  by Z Fixture Ensemble. Both apps report `Y` as the active section after
  either drag. The Title and Artist rail frames agree within 0.34 pt.
  The Title frames differ on 1.92–2.44% of iPhone pixels and 1.70–2.30%
  of Duo pixels above the RGB threshold; Artist differs on 1.94–2.35%
  and 1.69–2.26%, respectively. The corrected Year/Duration replay
  verifies that neither sort shows the index. Year offers 2000s, 2010s
  and 2020s in the iPhone sheet and Duo menu, and choosing 2010s lands
  the pinned heading at y=178 pt on iPhone and y=90 pt on Duo in both
  apps. UIKit exposes the full heading band to accessibility; SwiftUI
  exposes the text frame. Duration reports the selected sort. The four
  settled pairs differ above the RGB threshold by 0.04–2.41% on iPhone
  and 1.54–2.10% on Duo. These captures do not establish exact motion.

- **UIKit Settings Service Info (local lane):** The short idle description uses
  the same leading column as its title, with Idle still at the trailing edge when
  both fit. The dated Last Successful Publication is painted under its title and
  exposed as one static-text element. Native fixture journeys on iPhone 18 Pro and
  the Duo cover verify the one-line description, idle alignment, complete date and
  reading order. This does not settle the surrounding Settings row heights.

- **Floating Item Shop glyph (local lane):** UIKit now hosts the live Shop
  glyph instead of tinting its exported image. The iPhone 18 Pro recordings
  sample a 3,000 ms breath and the same gold-channel range in both renderers.
  With Reduce Motion both stay at the peak. The native AX5 journey exposes
  one named Shop link with a 44 pt target. Neighboring standard symbols
  and navigation glass are separate open visual differences.

- **Shop Retry under Reduce Motion (local lane):** Both offers first appear
  in the same recorded frame in all four loopback replays. Neither offer
  shows an intermediate 10–90% text-ink ramp. The frame gaps at reveal were
  123/17 ms on iPhone and 107/12 ms on folded Duo (SwiftUI/UIKit), so the
  recordings cannot exclude shorter fades. The settled recovery frames
  differ on 4.54%/4.61% of pixels above the same RGB threshold. This does
  not measure an in-flight scroll rush.

- **Shop Retry with motion (local lane):** In the no-input controls, two
  identified offers first reach 10% of settled text ink 120 ms apart in
  SwiftUI and 116 ms apart in UIKit on iPhone 18 Pro; on folded Duo the
  sampled gaps were 84 ms and 119 ms. Folded SwiftUI's first crossing
  follows a 35 ms frame gap, so the folded timing ranges overlap. The
  SwiftUI harness needed live accessibility to verify the spinner against
  the held request; Explore reused its earlier error snapshot. Tracking
  individual title shapes through the videos shows that the drag moved
  rows during entrance on both devices. In UIKit on both families and
  SwiftUI on folded Duo, the moving fourth and fifth titles first exceeded
  10% in the same sampled frame; they stagger in the no-input controls.
  On SwiftUI iPhone those moving titles first exceeded 10% 26 ms apart.
  Gesture timing relative to the stagger differed, so the runs do not
  establish a different rush policy.

- **First Run seen-state (local lane):** On iPhone 18 Pro and folded Duo, the
  native loopback journey closed the Settings replay after Song List and Sort
  Songs. Both apps resumed at Navigation after relaunch, with Song List no
  longer hittable. On folded Duo the same rail-aware runner tested the exact
  SwiftUI `master` app (`404702bc6`) and UIKit, and both only showed the optional
  Experimental Ranking Metrics slide when the corresponding setting was on.

- **Year quick-toggle evidence (local lane):** The expanded and collapsed
  Year headers overlap on both families, so both taps in each replay use one
  point. All arms end expanded. The switch's blue pixel signal drops below
  20% of its settled value for 483 ms (SwiftUI) and 516 ms (UIKit) on iPhone
  18 Pro, and 456 ms (SwiftUI) and 550 ms (UIKit) on folded Duo. These
  intervals include automation input spacing; the videos show close/reopen,
  not in-flight reversal. A native double tap in the overlap also ends
  expanded on both iPhone builds, without a comparable signal drop. The
  final state alone does not prove both taps reached the control.

- **UIKit Feedback (local lane):** Matched Explore samples on both families
  verify the untouched feature prefix, disabled Submit, no bug-only fields,
  and closing the untouched form. On iPhone 18 Pro, both apps keep one
  `[Feature]` prefix with ordinary typing, show “Add a description.” with
  Submit disabled, and retain the draft when the discard popover is dismissed.
  Explore blocked entry through Report an Issue; native journeys use loopback
  for that path. The shared sending plan now drives both renderers. On
  iPhone, the first substantial filing-title
  change follows the form's first substantial fade by 332 ms in SwiftUI and
  334 ms in UIKit. These are recording thresholds, not exact durations.
  Both UIKit families retain failed drafts and read the no-media indicator,
  title and explanation in order. The folded SwiftUI bar's full frame includes
  the rail, so its old assertion against the bar midpoint fails even though
  its status stays in the usable part of the sheet. UIKit now uses that safe
  area too. Its settled filing title is within 0.2 pt of the iPhone reference
  vertically and within 1.5 pt on folded Duo; the folded title centers at
  x=195.9 pt in both renderers. The safe-area grouped feature form reduced
  pixels above the same RGB threshold from 21.27% to 5.71% on iPhone and
  from 19.97% to 4.33% on folded Duo. The two iPhone captures after closing
  the form are 67 pt apart in Settings scroll position. For the aligned
  settings-content crop, 2.13% of pixels differ above the threshold. The
  folded captures exposed a real extra Filter Invalid Scores line. The revised
  UIKit switch row removes that wrap at default size without shrinking the
  switch's target; its AX5 description still scales and scrolls.
  The compact Photos picker presents over the form on both families. On the
  same iPad, a photo dragged from Photos onto Description highlights the sheet
  and attaches in both apps, including exact SwiftUI `master` (`291d884e5`).
  On Duo inner landscape, both local builds verify inline pick, removal,
  untick and Hide, then Uploading Media → Filing Request → Request Sent.
  Both keep one spinner at the same centre through the stage change.
  The bright title crop crosses 80% of its outgoing and incoming settled
  pixel counts 133 ms apart in SwiftUI and 137 ms apart in UIKit. These
  thresholds compare visible frames, not exact animation durations.
  On the actual 669×951 Duo inner portrait, both native journeys verify two
  attachments, removal and untick, and Hide retaining the remaining photo.
  Both also verify Uploading Media → Filing Request → Request Sent against the
  loopback service. The portrait bright-title crop crossed the same thresholds
  185 ms apart in SwiftUI and 135 ms apart in UIKit in one run each; the
  preceding frame gaps were 14/14 ms and 19/2 ms, respectively. This is a
  measured difference, not a repeatable timing fix or a full fade duration.
  Use regular fixture media files; simulator Photos retained older alias
  entries that could not be imported. On the actual 951×669 Duo inner
  landscape, both apps show the selected photo, its named 44×44 pt remove
  button, and Hide Photo Library together. The same attachment remains in
  each form on the 466×678 cover with the inline library absent. Native
  `XCUIHinge` journeys then verified 180° → 0° → 90° and 180° → 0° → 180°
  on lit cover and inner framebuffers without relaunching. UIKit retained
  the same 44 pt Remove button in the fresh inner tree before scrolling.
  Exact SwiftUI `master` (`404702bc6`) lost the attachment on both returns:
  the strip was absent before and after scrolling, and its untouched
  form no longer required a discard confirmation. No desktop-control
  permission was used. The fully open SwiftUI diagnostic kept the same
  model and one attachment from inner to cover, then showed a different
  model with zero attachments on the inner return, before any scroll.
  After moving draft ownership to Settings, both physical SwiftUI retests
  retain one attachment in the same model throughout. The named 44 pt
  Remove button is present in both fresh inner trees before scrolling,
  and Cancel still prompts before discarding the media-only draft. On the
  repaired build the inner-display picker still attaches and unticks
  photos, Hide retains the remaining attachment, and the loopback upload
  still proceeds from Uploading Media to Filing Request. The iPhone
  still presents the compact system Photos picker over the form.
  Both folded AX5 Feedback headers stay reachable after scrolling.

- **Folded Paths at AX5 (local lane):** The first Text activation card is
  taller than its scroll viewport in both renderers. The native journey
  reveals the timestamp inside the table and reads all of `00:02:750` at
  45.2 pt in both apps (Large baselines: 15.6 pt SwiftUI, 17.3 pt UIKit).
  Close and all three 44 pt selectors remain reachable; the reading order
  and scoped accessibility audit pass. No renderer change was needed.

- **UIKit live Songs metadata (local lane):** On each family, six common
  unobscured anonymous rows exposed neither score nor accuracy. With SFentonX
  and instrument icons off, two common rows per family exposed the same Score
  and Accuracy. With Score off, three common rows per family still exposed
  matching Accuracy and no score. All four apps restored their three Settings
  values and rendered populated Songs. The folded apps began with different
  icon preferences; their restored captures are not like-for-like comparisons.
  All four observed publication 1801 before and after with pinning off. The UIKit
  notification badge appeared in a matched frame without a SwiftUI badge;
  notification state was not controlled in this replay.

- **UIKit live Compete and Rivals (local lane):** On iPhone 18 Pro, SFentonX sees eight
  fully visible Compete ranking rows with matching data, order and frames, including Your
  Rank. The six visible Lead Rivals rows match names, ahead/behind counts and row sizes.
  The Common Rivals freeze card pushes those rows 10.33 pt lower in SwiftUI than in the
  captured UIKit build; its Retry Now target fits inside the row in SwiftUI. The anonymous
  drawers expose the same actions and omit Compete and Rivals. Publication 1789 was
  observed before and after the pair with pinning off; these were not pinned reads.

- **UIKit live folded Lead rankings (local lane):** Ten visible rows have
  the same order both without a selected account and with SFentonX. The
  account button identifies the anonymous arm, and the native More menu names
  SFentonX in each selected arm. Publication 1803 was observed before and
  after with pinning off. The footer was outside the measured viewport.

- **UIKit live Duets rankings (local lane, 2026-11-21):** Against SwiftUI
  `master` (`404702bc6`), 15 hittable iPhone rows and 11 folded Duo rows
  match in identity, order, spoken label and settled frame with and without
  an account selected. Before settling, the selected iPhone SwiftUI rows
  were still moving; the repeat waited for consecutive matching frames.
  Publication 1808 was observed before and after, with pinning off.

- **UIKit live song Duets (local lane):** The Reaper board on iPhone 18 Pro
  has six hittable rows with matching order, button roles and spoken labels
  for anonymous and SFentonX. Neither arm in either app shows a personal
  footer. After the shared gap fix, the first row aligns, and the next five
  start 1 pt lower and end at the same position in UIKit for both identities.
  Publication 1814 was observed at both iPhone endpoints with pinning off.
  Folded Duo shows five matching rows in the same order and the same 1 pt
  pattern on the last four; both apps expose the selected identity under
  More and neither adds a personal footer. The first folded batch crossed
  publications; the settled repeat observed 1816 at start and finish with
  pinning off and confirmed the same five rows for both identities.

- **Duos row stars (local lane):** In the iPhone 18 Pro and folded Duo loopback
  comparisons, wire counts 6, 5, 1 and 0 draw five gold, five white, one
  white and no stars. The row labels expose the matching counts and omit
  stars for zero. The zero-star row was scrolled clear of the footer fade
  on folded Duo to verify the artwork is absent. The iPhone 18 Pro player
  profile All Gold fixture shows five gold stars in identical positions in
  the Lead Avg Stars tile, with the same spoken value. The completed folded
  Duo replay also paints five gold stars and exposes `5 gold stars` in each
  171×71⅓ pt tile; the scroll landing differs between renderers. The folded
  song-board Band Size action now matches the reference's blue icon, switches to white under Increase Contrast,
  and announces Trios when picked. The global Band Rankings rail uses the
  same policy but was not separately measured.

- **Duo Song Detail → Duos split (local lane):** Native hinge journeys
  measured an actual 951×669 pt inner landscape window. UIKit and both
  SwiftUI builds opened the trailing board with one title, the same first
  row and a named system Close. Closing restored full-width Song Detail
  and cleared the selection. The first row starts at x=450 pt and is
  401 pt wide in UIKit and corrected SwiftUI, versus x=408 pt and 443 pt
  wide in the frozen reference, which excluded the rail twice. Its y
  differs by ⅓ pt between UIKit and corrected SwiftUI. The UIKit personal
  footer now uses the same section fit as SwiftUI: both place the full
  combined member names on their own line in a 401×72⅓ pt footer,
  with one named jump action that reaches the highlighted rank-29 row.
  Both framebuffers show the same name, rank, score and accuracy. Keeping
  pagination and spotlight focus local to the board preserves the selected
  Song Detail action, page 2 and the rank-29 target through 180° → 90° →
  180° on UIKit and corrected SwiftUI. At 90° the divider moves to
  x≈496 pt. Both native rails close at all six button-relative edge taps
  within the 44 pt target and restore full-width Song Detail.
  On SwiftUI the departing page could consume Jump before page 2 loaded,
  leaving 73 pt of rank 29 under the footer even though it was hittable.
  Matching the reveal to the loaded request restores the same page-2
  landing as UIKit. Both now keep 6 pt of clearance above the footer in
  flat, book and flat return. Measuring and drawing the name with the
  preferred body font keeps the whole roster on one line in the 339⅓ pt
  book pane. Both footers stay 72⅓ pt tall and show the same rank, score
  and accuracy. At an early UIKit flat-return checkpoint, the footer
  and Band Size glyph still clip after accessibility reports settled
  geometry. The later frame restores the whole footer and the glyph's
  original painted bounds. These snapshots do not establish transition timing.
  The compact band-board AX5 journey passes separately on UIKit and
  frozen SwiftUI. It reveals the lazy Duos choice in the sheet, measures
  clearance from pinned chrome (including the UIKit Band pager's 6 pt
  inset), and reads both names, rank, score and accuracy from the
  rendered tall card before running the accessibility audit. At default
  size, UIKit still reports an unattributed `Text clipped` result, also
  reproduced on the pre-change binary. Shortening the footer roster
  without changing the ranked rows or selected rank does not clear it.
  The frozen SwiftUI build passes the separate default-size clipping audit.
  In the corrected default-motion iPhone comparison, both standalone boards
  land the first page-2 card at y=216 pt and rank 29 clears the footer by 6 pt.
  The settled Open pair differs above 16 in any RGB channel on 1.71% of
  the frame, down from 18.63% against frozen SwiftUI. The sampled movement
  windows (645 ms SwiftUI, 697 ms UIKit) also include scrolling; they are
  not fade durations.
  The iPhone recordings exposed a separate UIKit reload flash: the
  unchanged song header dipped to 3% of its original artwork chroma when
  page 2 entered. Keeping the header out of the row entrance restores
  99.97% on iPhone and 99.48% on Duo versus about 100% in SwiftUI, with the
  rows still animating. Settled paired frames differ above 16 on 1.52% of
  pixels after Open on iPhone and 2.14% on Duo.
  On iPhone a separate Solo reload could bring the scrolled-away header back
  and remove the pinned title. The shared UIKit song board now restores its
  offset after swapping the ranked rows for the temporary result area.
  Both renderers keep the bar title, land on the first row of page 2 and
  expose the unchanged header name alongside a named Retry if a page fails.
  The final UIKit candidate also passed both physical Duo split and pager
  journeys. In controlled Explore replays, page 3 started before page 4's
  held failure returned: 13.79 s (SwiftUI) and 10.04 s (UIKit) on iPhone;
  13.81 s and 9.86 s on the Duo cover. On both families the matching rank-51
  accuracy and pager value "3 of 4" persisted after the failure, with no
  spinner or stale Retry. The settled pairs differ above 16 in any RGB
  channel on 0.83% of iPhone pixels and 2.81% of Duo cover pixels.
  At AX5, UIKit's first Duos card displayed the spoken full-combo
  description in the badge instead of the percentage alone. The shared
  UIKit band badge now draws one line, as SwiftUI does, without changing
  the spoken card. The measured card shrank from 672 pt (iPhone) and
  735 pt (Duo cover) to 546 pt on both; the SwiftUI reference is 545⅓ pt.
  Bounded native drags and screenshot OCR verify the percentage on both
  devices. The tall card still needs scrolling, and this check does not
  clear the separate default-size audit.

- **Duo full-width boards (local lane):** In the Expo fixture capture after
  Jump, UIKit's first Duos column took 823 pt and the second ran under the
  rail; Explore timed out after observing the page-2 transition. With
  self-sizing columns, both ranks in each pair are fully visible. The
  physical UIKit and SwiftUI journeys agree on rank order, 411 pt flat
  columns, a book gutter at x≈456–496 pt, and a stable 835×48 pt footer
  showing season, score, five stars and accuracy. UIKit's pager now moves
  from x=650 to x=681 pt (badge center) flat → book and returns without
  changing page; it stays centered in a single split pane. Band Rankings'
  AX5 floating pager is exposed after loading and clears the physical
  divide in both poses. Frozen SwiftUI's flat pager sits 21 pt farther left:
  the root probe reports an already rail-free 867 pt width plus the 84 pt
  rail inset. Corrected SwiftUI measures the actual board and matches
  UIKit's x≈650 pt flat and x≈681 pt book centers for both the framed
  Duos pager and the AX5 floating pager. The completed Expo replay against frozen
  SwiftUI `404702bc6` shows the same y=206 pt landing after Jump and four
  complete rows in both apps. The full-width footer shows `S10`, `80,500`,
  five white stars and `96.5%` in Jump and Open. Respectively 3.43% and
  2.85% of frame pixels differ by more than 16 in an RGB channel. The
  earlier 51 pt native frame difference did not reproduce after the
  matched wait. The recordings use Reduce Motion; they do not establish
  default transition timing.

- **UIKit floating page tools (local lane):** The native Paths and Quick
  Links circles on iPhone 18 Pro and the Duo inner portrait display remain
  44 pt and operable at AX5. Their symbols grow from Large through XXXL
  and then hold at AX5; the frozen SwiftUI iPhone 18 Pro shows the same size
  progression. This does not alter the Duo rail or certify
  identical navigation glass or Large Content Viewer gestures.

- **UIKit song board header and pinned title (local lane):** The band board now
  uses SwiftUI's 12 pt space below the header. On iPhone and folded Duo the
  first matched Duos fixture row starts at the same position, and the next
  four hittable rows are 1 pt lower in UIKit with the same spoken names.
  UIKit journeys on both devices verify the title at standard size and AX5.
  Folded long-title journeys also verify that Song Detail, Solo, Duos and
  Player History show the native bar title only while the heading is scrolled
  away. This does not certify the side-by-side variant on the inner display.

- **UIKit inline service freeze (local lane):** The shared row now fits the message,
  countdown and Retry in that accessibility order. On iPhone 18 Pro and folded Duo,
  the default Retry Now frame matches SwiftUI at 65.67×44 pt; the row height differs by
  0.17 pt. At AX5 the full 206×52.67 pt target sits beneath the countdown on both and
  is 5.33 pt higher in UIKit. Completed Expo fixture pairs differ on 2.20% / 1.78%
  of pixels at Large and 11.96% / 9.49% at AX5 above the same RGB threshold. Native
  journeys verify action containment and order on both devices. This is not a second
  production replay or an exact AX5 match.

- **UIKit Quick Links (local lane):** The iPhone sheet uses 52 pt default rows and fits Bands in the tall chooser. At AX5 the wrapped Global Statistics row measures 155.33 pt and the single-line Lead row 93.33 pt, matching the reference; the nested Lead Rank History choice remains reachable. Rendered text confirms continuation lines return to the leading edge. Folded Duo instead uses a native menu: the system draws 42 pt default rows on both apps. UIKit removes the extra group title that clipped the AX5 choices and exposes the instrument in the full accessibility name. The paired Explore captures now put the AX5 Lead Rank History row at y=456 pt with 186 pt height in both apps. Whole-frame differences above the same RGB threshold are 2.77% at Large and 1.50% at AX5. The folded journeys verify artwork, nested jump and selected state. The full visible action names still differ from SwiftUI's short indented labels.

- **UIKit Privacy Policy (local lane):** At `28f0e6f43`, default-size native journeys and
  completed Expo pairs on iPhone 18 Pro and folded Duo cover the top, the Contact heading
  followed by its separately named, hittable Link, and Settings after Close. Contact captures
  differ on 13.00% and 12.13% of pixels above the RGB threshold, respectively. Scroll positions
  differ, so those figures are not typography scores. On both families, the AX5 journey
  verifies that the rendered body grows and selecting a word offers Copy without opening a keyboard.

- **UIKit Intensity and folded Search (local lane):** Three matched Song Detail captures per
  family verify levels 1–7: 62×20 pt meters, the same spoken values in row order, and the correct
  color at every bar center. Sharing SwiftUI's horizontal gutter removes the 1 pt offset in
  the trailing meters. Whole-frame differences above the RGB threshold are 1.26–1.27% on iPhone
  and 0.93% on folded Duo; the folded Paths icon tint still differs. A separate matched
  fixture with raw Bass `99` shows no Bass meter or leaderboard in either app, and the
  other three meter labels, order and frames match per family. Whole-frame differences
  are 1.47% on iPhone and 1.03% on folded Duo. This is the omitted-chart case, not the
  explicit unavailable meter. A separate UIKit-only control gallery on both
  families supplies an invalid value and shows one named "Difficulty unavailable"
  element; it is not a SwiftUI/UIKit comparison. The folded Search replays dismiss the keyboard
  while dragging the results, reveal the same next eight songs in order, and reopen the
  keyboard with one matching result after replacing the query. The first fully visible row
  lands 9.67 pt lower in the UIKit scroll sample; pitch stays 68 pt. On both families,
  a separate loopback replay shows Searching during a confirmed held query, the exact
  replacement result before release, and that result unchanged after release. The
  spinner is structural evidence only; its phase and timing were not matched.
  The mixed-revision ledger contains 676 pairs (506 with completed fingerprints,
  15 structure-only), with 64 of 251 applicable named states sampled on at least
  one family and 58 sampled on both.

- **UIKit folded Song Detail rail (local lane):** On the same Shop song, both apps show
  Item Shop and Paths directly when anonymous, and Item Shop plus More with a selected
  account. Their direct 38×38 pt system frames and the selected More → Paths row's 250×42 pt
  frame match. The named Paths action opens the sheet on both UIKit devices. UIKit now
  renders blue symbols instead of white on the rail, but the dominant Paths blue differs
  (sRGB 32/177/255 vs 80/165/255). The matched fixture captures differ on 0.96% of
  pixels anonymously, 0.50% selected and 1.63% with More open above the same RGB threshold.

- **Live Song Detail and Paths (local lane):** Twelve fingerprinted pairs cover the
  same song, anonymous and after selecting the profile through the live picker, on
  iPhone 18 Pro and folded Duo. All nine visible Intensity meters match labels, order
  and frames. The anonymous Lead preview matches six fully visible rows on iPhone
  and three on folded Duo; the selected view instead shows the Score History chart.
  Lead Expert Image and Text match selector frames and the three fully visible Text
  activations. The visible Image crop has no pixel above the greater-than-16 RGB
  threshold in any pair; whole-frame differences are 0.09–0.10% in Image and
  2.25–2.38% in Text. Selected arms observed publication 1793 at both ends with
  pinning off; this does not establish response provenance. In these selected
  captures, the chart and pager frames match, but UIKit's best scores start 10 pt
  lower on both families. The UIKit chart now removes the unused detail gap.
  Matched Expo fixture captures put the first score 15 pt below the pager in
  both renderers (previously 25 pt in UIKit) on the newest, preceding and
  restored windows on both families. Selecting a bar still inserts a named
  detail row 10 pt below the pager; paging clears it and restores the 15 pt gap.

- **Android + Windows (2026-09-28):** same rules as Apple — platform-native design researched per platform, Fluent second, multiple form factors (Android: phone, book foldable, passport foldable, tri-fold, tablet; Windows: desktop/tablet across window-size configurations), and the same dev → unit → UX tests → accessibility → screen reader flow. The Windows host is far more powerful: run **many parallel lanes on both Android and Windows**, while this Mac continues Apple lanes and oversees. Both machines commit/push when work is ready: Windows lanes push directly to GitHub via `tools/git_integrate.py` (gh file-stored token, set up 2026-09-28); the Mac pulls/rebases as usual.


1. **Liquid Glass & native navigation components**, plus docs/agent updates.
2. **Instrument features and missing pages** — UX match to web, Apple HIG first, Fluent second.
3. **Profile pages** (selected and unselected) → other missing pages → refinement. *Features first, then full UX parity.*
4. **Shared animated background & seamless transitions.**
5. Testing phases: unit, UX and accessibility tests with every change (operator, 2026-10-08) → whole-app accessibility audits when the *app* is complete → VoiceOver testing after that.

Platform order: **iPhone (iOS 26.5) → iPhone Duo → iPadOS → macOS → iPhone on iOS 17 (no Liquid Glass)**. Android/Windows run in parallel on the Windows host (resumed 2026-09-28) via `tools/win_relay.py`.

- **UIKit port (operator, 2026-10-31):** port iOS/iPadOS to Swift logic + UIKit, UX identical on iPhone, iPad and iPhone Duo, tests updated, performance measured A/B against the SwiftUI app as Fenton-HASS-Native did. macOS is sidelined meanwhile. Work runs on `claude/uikit-port` (lanes branch from it, the orchestrator merges); the port app `FestivalMobileUIKit` installs beside `FestivalMobile`. Rules, seams and lanes: [uikit-port.md](.agents/platforms/apple/uikit-port.md). Wave 1 (Design, Background, Shell, Perf) started 2026-10-31; wave 2 (Songs, Leaderboards, Profile, Rivals, Settings) follows.

---

## 3. Testing phases

| Phase | When | What |
|---|---|---|
| **Build** | Every commit | `swift build --build-tests`, iOS build (via `lane_integrate.sh`) |
| **Unit** | As we go | Swift Testing for new Core logic (target 95% non-UX); run only new/changed tests while iterating |
| **Visual smoke** | While building UI | `tools/ios_sim.py shot` screenshots compared to the web app at the same viewport |
| **UX tests** | Every UI change | XCUITest journeys + hosted snapshot states per control (target 90% UX coverage) |
| **Accessibility tests** | Every UI change (operator, 2026-10-08) | Name/role/state, reading order, target size, text scaling for what changed ([strategy](.agents/testing/strategy.md#accessibility-tests-with-every-change)) |
| **Accessibility audits** | App complete (per platform) | Whole-app audits, contrast over artwork, in-app a11y toggles |
| **VoiceOver** | After accessibility | Scripted VoiceOver walkthroughs per page |

---

## 4. Work breakdown

Legend: ⬜ not started · 🟨 in progress · ✅ landed · ⛔ blocked

### Wave 0 — Foundation (orchestrator)
- ✅ Split `SongScreens.swift` into feature folders; add `AppRoute` for all 24 web routes, `AppRouteDestination`, `FestivalTabStack`, placeholder screens (`9a5754a`)
- ✅ Shared design primitives: `festivalGlass` (Liquid Glass + pre-26 fallback), `FestivalSectionHeader`, `InstrumentIcon` + bundled icons
- ✅ Deployment targets iOS 17 / macOS 14
- ✅ `tools/ios_sim.py` (serialized sim + deep links), `tools/lane_integrate.sh`, `FestivalBackgroundHost` seam (`2ff8338`), `festivalRootChrome` seam (`915fde4`)

### Wave 1 — parallel lanes (iPhone, iOS 26.5)

**Lane A — Shell & Liquid Glass chrome** (Opus) — ✅ landed `4b1f11c`…`0f4ebd9`
- ✅ Conditional tabs mirroring web `BottomNav`: Songs · Suggestions* · Leaderboards / Compete* · Statistics* · Settings (*when a profile is selected)
- ✅ Profile button **top-right** on every tab root (notifications slot reserved beside it)
- ✅ Apple-style hamburger drawer (leading) with expanded options — Item Shop, Bands, Rivals, Manual, Licenses, profile-specific actions
- ✅ Liquid Glass judgment pass → `.agents/design/apple/liquid-glass.md`; apply to Settings sections and other glass containers
- ✅ Modals: dark glass backgrounds, native sheet detents, Title Case white section headers (`festivalSheet` style)
- ✅ Settings persist across cold starts (verify every setting)

  - Follow-ups: drawer swipe/VoiceOver dismissal and tab re-tap untested (no tap tooling → Lane T); band tab rules unit-tested only

**Lane S — Songs, Song Detail, Shop** (Sonnet) — ✅ landed …`eaecd6c` (follow-up running: scrubber `#` labels, keyboard icons)
- ✅ Native toolbar controls on Liquid Glass nav bar: search, sort, filter (Item Shop button removed → drawer)
- ✅ Song rows as Liquid Glass; tighten row spacing to match web
- ✅ Instrument icons inside the instrument status circles
- ✅ Right-side section index scrubber for Title/Artist/Year sorts; animate out for sorts where it doesn't make sense
- ✅ Instrument selection moved into Filter (only when a profile is selected), like web
- ✅ Search pill to native iOS standard; decide chevrons (HIG: no disclosure chevrons inside card rows)
- ✅ Song Detail: intensity card uses instrument icons instead of text
- ✅ Remove offline/warm-cache disclosure UI (online-only)

**Lane P — Profile + Statistics tab** (Sonnet) — ✅ landed `4f3dfae`, `8324dc2`, `3eba1af`
- ⬜ Fix: selected profile survives app close / cold start
- ✅ Player profile page `/player/:accountId` — viewed (unselected) and selected states, select/deselect action
- ✅ Profile selection sheet redesign: native, dark glass, "Find Player"/"Find Band", centered "Enter at least…" hint, Title Case headers

**Lane L — Leaderboards** (Sonnet) — ✅ landed `f50dce9`…`65e8607`
- ⬜ Leaderboards overview: top-10 cards per visible instrument (+ band types), metric picker
- ✅ Full rankings (paginated) and band rankings
- ✅ Song leaderboard page native navigation pass; rows navigate to player profile

**Lane B — Shared background & transitions** (Opus) — ✅ landed `8cd7f00`…`47345fa`
- ⬜ One animated background hosted by the shell — no restart/jitter across tabs or pushes; Item Shop uses the same one
- ✅ Song Detail: animate from the carousel to that song's album art, hold still; animate back on pop/tab change
- ✅ Carousel loads independently of the Songs tab

**Lane D — Agent docs architecture** (Opus) — ✅ landed `7c8b6eb`…`0b01884`
- ✅ Split every multi-platform doc by platform, then form factor (`.agents/<area>/<topic>/{spec,ios,ipados,duo,macos,android,windows}.md`)
- ✅ Router tables with direct pointers at every level; workflow docs for the lane model
- ✅ Remove tandem-research requirements; encode testing phases

### Wave 2 — remaining pages

**Lane T — Simulator driver tooling** (Sonnet) — ✅ landed `8d8a6ac`
- ✅ `ios_sim.py drive`: scripted tap/swipe/type/scroll/screenshot/accessibility-tree via an XCUITest driver, under the simulator lock

**Lane R — Rivals & Compete** (Sonnet) — ✅ landed `6bfa5da`…`8a3ab84`
- ✅ Compete hub · ✅ Rivals hub · ✅ All rivals · ✅ Rival detail · ✅ Rivalry (read-only endpoints verified)

**Lane G — Suggestions** (Sonnet) — ✅ landed `36da85d`, `2e76e59`, `1b81517`
- ⬜ Port suggestion algorithms to Core (unit-tested) · ⬜ Suggestions screen + filter sheet

**Lane N — Bands** (Sonnet) — ✅ landed `917ada3`…`7d91e9d`
- ✅ Band detail (members + instruments, summary, statistics, rank history, best/worst songs) · ✅ Player bands (All/Duos/Trios/Quads, paginated) · ✅ Bands landing (no band search — it writes; shows selected player's bands + Band Rankings links) · ✅ Per-song band leaderboard (paginated, in-place band-size switcher)
- **New finding:** `/api/bands/{bandId}` (the web's Band Detail source) also writes on a GET — `GetBandConfigurations` → `EnsureBandTeamConfigurations` rebuilds `band_team_configurations` on a cache miss (`GlobalLeaderboardPersistence.cs:4192-4206`). Not yet in `service-safety.md`'s table; treated as blocked like band search/sync-status. Band Detail instead reads `GET /api/rankings/bands/{bandType}?teamKey=` (confirmed pure), which already returns `members[].instruments` and (Duos+combo only) `configurations`. Consequence: `bandId` is a one-way hash (`BandIdentity.CreateBandId`), so a bare `bandId` link can't be resolved without `bandType`/`teamKey` carried from the originating row — `AppRoute.band` gained additive optional `bandType`/`teamKey` for this; a bare-`bandId` link (e.g. a future universal link) shows an explicit "open from a band list" state.
- Minimal additive edit to Leaderboards' `RankingsSupport.swift`/`LeaderboardsScreen.swift`/`BandRankingsScreen.swift`: `BandRankingRow` now also passes `bandType`/`teamKey` so its existing `.band` links resolve to full detail instead of the fallback state.
- Simplified vs. web: no instrument-combo filter/picker, no rank-history chart (list of recent snapshots instead), best/worst songs show raw `songId` (no catalog title cross-reference).
- `service-safety.md`'s endpoint table needs a `/api/bands/{bandId}` blocked row (Lane D/orchestrator; this lane only adds new `.agents/pages/*` files per lane rules).

**Lane M — Settings completion, Licenses** (Sonnet) — ✅ landed `169f9f3`…`30bf405`
- ⬜ Every web Settings section · ⬜ Licenses

**Lane X — Player history, notifications** (Sonnet) — ✅ landed `1f31d52`, `01c0aca`, `8bfc96a`
- ✅ Player history (sort sheet, Swift Charts line) · ✅ Notifications sheet + bell (unread dot, seen state, deep links)
  - Follow-up (Lane S): entry points to Player History from Song Detail / solo leaderboard
  - Simplified: notification copy covers player-scoped kinds only (no band kinds / coalescing)

**Lane F — First-run experiences (FREs)** (Sonnet) — ✅ landed `1930d0f`, `cbd1d0c`, `fdb1f41`
- ⬜ Core seen-state store: per-slide `{version, hash, seenAt}`; show **only unseen, gate-passing slides** (new info without replaying old)
- ✅ Native glass carousel + per-page slides/demos (songs, suggestions, player, song info, compete, rivals, shop, leaderboards)
- ✅ Settings: view again per page (all slides), reset, enable toggle · ⬜ Applied app-wide via one route/tab seam

**Lane Q — Quick Links** (Opus) — ✅ landed `b68af1d`…`4fa8bd3`
- ⬜ Feasibility + native design decision (HIG + Fluent) → `.agents/controls/quick-links/` · ⬜ Reusable `Common/QuickLinks` API (toolbar jump menu, active section, VoiceOver rotor) · ⬜ Adopt on Leaderboards
- 🟨 Adoption: Songs/Song Detail (Lane S), Player/Statistics/Band/Settings (Lane P2), Compete/Rivals/Rivalry/Rival Detail (Lane R2)

**Lane R2 — Rivals follow-ups** (Sonnet) — ✅ landed 2026-09-28
- ✅ Replaced `RivalNavigationBridge` singleton with typed `RivalScope` carried directly on `AppRoute.allRivals(scope:)`/`.rivalDetail(rivalId:name:scope:)`/`.rivalry(rivalId:mode:name:scope:)` · ✅ Common Rivals (`RivalCommonRivals.intersect`) + cross-instrument Combo/Pro-Drums-family scope (`RivalCombo`), ported to Core with unit tests · ✅ Find Rival (`FindRivalSheet`, reuses the allowlisted account-search GET) · ✅ Quick Links on Compete/Rivals/Rivalry/Rival Detail · ✅ Re-checked rival detail endpoints: live 200 outside an active scrape window; 503 during one now carries `x-fst-public-read-freeze-reason: scrape`

**Lane P2 — Profile / Statistics / Band / Settings follow-ups** (Sonnet) — ✅ landed
- ✅ Global ranks via `GET /api/rankings/{instrument}/{accountId}` (verified pure read; live probe found its own `instrument` field comes back blank, unlike the list endpoint — tolerated) · ✅ Profile sheet dismiss → push on active tab (new `\.openRoute` hook) · ✅ `FST_DEBUG_PROFILE` in-memory only (no more shared-`UserDefaults` clobbering) · ✅ Quick Links on Player/Statistics/Band/Settings (`top-songs`/`refresh-profile-name`/`export` left out — no such sections exist yet) · ✅ Band song rows show catalog titles/artist/art, link to Song Detail
- Found: a custom `@Entry` environment action set by the presenter never actually fires when read from inside `.sheet(isPresented:)` content in this SwiftUI setup (proved via `tools/ios_sim.py drive` — swapped the handler for a visible, already-proven `@State` side effect and it silently never ran, for both the new `\.openRoute` and the pre-existing `\.openDrawer`). Fixed by passing the dismiss-then-push closure directly into `ProfileSelectionSheet`'s init instead of through environment; flagged for other lanes in `.agents/controls/profile-selection/ios.md`

**Lane S follow-ups** — ✅ landed …`bb77ed4`: avatar-rightmost toolbar on Songs, Quick Links on Songs (Duration/Shop sorts) + Song Detail, row visual order + path column order consumers, `Song.maxScores`

**Lane D2 — FRE live demos** (Sonnet) — ✅ landed `789ff77`…`bdcf36e`
- ✅ Live native mini-demos for all 31 non-Songs slides (Song Info 8, Player History 2, Statistics 6, Suggestions 4, Leaderboards 3, Compete 3, Rivals 3, Item Shop 4) — every one of the 42 catalog slides now resolves to a live demo, unit-tested (`FirstRunDemoCoverageTests`)
- New: `firstRunPulse`/`firstRunStagger` reduce-motion-aware helpers, `FirstRunDemoPool` shared static sample data — see `.agents/controls/first-run/ios.md`
- **Open issue (not this lane's files):** launching directly into a non-default tab (e.g. `--tab statistics`/`--tab leaderboards`) with `FST_DEBUG_FIRST_RUN=force` reproducibly shows the first-run sheet chrome (close/skip/done) but with **zero** slides in the `TabView` (`PageIndicator: page 1 of 0`) — confirmed on 5/5 attempts across two pages. `--tab songs` (the default/first tab) shows all 9 slides correctly every time. Suspect a `TabView(selection:)` initial-tab race (transiently rendering the first `ForEach` tab before honoring the debug-selected one) in `FestivalRootView.swift`/`FirstRunModifier.swift`/`FirstRunCarouselView.swift` — none owned by this lane. `FirstRunSlideEvaluator`/`FirstRunCatalog`'s own unit tests all pass, so the slide-selection logic itself is not implicated; screenshots: `/tmp/laneD2/{statistics_a,leaderboards,leaderboards2}.png` + matching `.tree.txt` dumps.

**Lane G2 — Suggestions follow-ups** (Sonnet) — ✅ landed `f2c4cf6`…`c6d1b53`
- ✅ `near_max_5k`/`10k`/`15k` + decade variants, using `Song.maxScore(for:)`; fixed-seed determinism test (see `.agents/pages/suggestions/ios.md` "Tests" for why literal cross-language byte parity isn't the achievable bar here) · ✅ `visibleInstruments` passed from `FestivalRootView`/`AppRouteDestination` into `SuggestionsScreen`, duplicated `@AppStorage` reads removed
- ⬛ Rival-driven families (`song_rival_*`/`lb_rival_*`) still unported: verified the web needs a combined `GET /api/player/{accountId}/rivals/all` read (`buildRivalDataIndexFromRivalsAll`) that `FestivalAPI+Rivals.swift` doesn't expose yet (only per-instrument reads) — not a service-safety block, just a missing native read; follow-on for whichever lane adds it. Band suggestions still deferred (needs band identity).
- Coverage: SuggestionGenerator.swift 96.08%, SuggestionFilterSettings.swift 100%, SuggestionModels.swift 96.92% (llvm-cov). 53 `SuggestionGeneratorTests` (was 47), all Core tests green (313 total in the package).

**Lane G3 — Rival-driven suggestions** (Opus) — ✅ landed `9c71219`
- ✅ `RivalDataIndex.build(from:)` (new `FestivalCore/SuggestionRivalData.swift`) ports the web's `buildRivalDataIndexFromRivalsAll` from `FestivalAPI.rivalsAll(accountId:)`'s `RivalsAllResponse` (Lane K) · ✅ `SuggestionGenerator.setRivalData(_:)` + all ten `song_rival_*` pipelines (`gap`/`protect`/`battleground`/`spotlight`/`slipping`/`dominate` plus the `near_fc`/`stale`/`star_gains`/`pct_push` cross-pollination variants), mirroring the web's two injection paths (join the startup shuffle vs. splice to the front) · ✅ `FestivalSession+Suggestions.swift` loads `rivals/all` alongside the catalogue whenever the generator is (re)built, best-effort (a failed/unavailable read only skips the rival families) · ✅ rival name/delta badge on `SuggestionCategoryCardView`
- **Finding:** `lb_rival_*` ("Leaderboard Rivals") is dead code on the web itself — `suggestionFilterConfig.ts` reserves the filter type and key prefix, but `buildRivalDataIndexFromRivalsAll` always leaves `leaderboardRivals` empty and no web pipeline ever produces an `lb_rival_*` key. Not ported; documented in `.agents/pages/suggestions/ios.md`.
- `SuggestionCategoryType` gained `.songRivals`; the filter sheet's existing `SuggestionCategoryType.allCases` iteration picked it up with no UI changes, verified by the existing generic filter tests.
- 75 `SuggestionGeneratorTests` (was 53) + `RivalDataIndex` tests; Suggestions-Core line coverage 96.13% (SuggestionGenerator.swift 95.71%, SuggestionModels.swift 97.14%, SuggestionFilterSettings.swift 100%, SuggestionRivalData.swift 97.06%). Verified live (`ios_sim.py drive`): "Dominate {rival}" and other rival categories render with the name/delta badge against the live public service.
- Open: no mid-session re-injection of freshly-updated rival data into an already-built generator (the web's `useSuggestions.ts` re-calls `setRivalData` when its query refreshes; native only calls it once per generator build) — the splice-path code exists and is unit-tested, just not exercised by any current caller.

**Lane K — Service client consolidation + scrape-freeze UX** (Opus) — ✅ landed `7f6e7cb`…`b01585f`
- ⬜ One typed request path for every public GET (Rivals/Bands/History/Notifications/Rankings migrated) · ⬜ One error vocabulary · ⬜ Shared `ServiceStatusView` with scrape-freeze auto-retry (`Retry-After`) adopted across screens · ⬜ `add-endpoint` skill + architecture rules

**Lane K — Service client consolidation & scrape-freeze UX** (Opus) — ✅ landed
- ✅ One request path: `FestivalAPI.send` gate (keyless guard, 30 s timeout, cancellation) + shared `mapStatus`; pinned `read(_:)`, publication, operational and Rivals reads all use it (Rivals' private `URLSession` removed)
- ✅ `ServiceIssue` vocabulary (`scrapeInProgress`/`unavailable`/`syncing`/`notFound`/`offline`/`other`) + capped `ServiceRetryBackoff`; `FestivalAPIError.publicReadFrozen`
- ✅ `Common/ServiceStatusView` / `ServiceStatusInline` / `.serviceStatusOverlay` ("Scores are updating" countdown, announcements, Reduce Motion) adopted on every service screen; `FST_DEBUG_FORCE_FREEZE=1`
- ✅ `GET /api/player/{id}/rivals/all` exposed as `rivalsAll(accountId:)` (pure read verified; typed model + fixture) for the Suggestions rival families
- Docs: architecture "one request path" rule, service-safety freeze semantics, `skills/add-endpoint.md`, `controls/service-status/`

### Wave 3 — UX tests (started for completed features)

**Lane Z — Bugs found by UX tests** (Sonnet) — ✅ landed `a445a3f`…`8716205`
- ⬜ Leaderboards row IDs shadowed by card ID · ⬜ Quick Links jump lands before target (see also Lane U3's independent repro below: tapping any row but the first activates the row *above* it) · ⬜ FirstRun pulse ignores still-background flag

Coverage so far (SwiftPM hosted+logic): Shell 71.8%, Leaderboards+QL 83.6%, Background 81.0%, History+Notifications 72.7%, First-run 78.8%, Licenses 67.7% — gap is mostly device-only branches; iOS app-target `xccov` measurement still to run.

**Lane U4 — UX tests: Profile, Statistics, Bands, Settings + Suggestions hosted** (Sonnet) — ✅ landed `ee9dcef`…`8d59248`
- ✅ 43 hosted snapshot tests (`PlayerProfileRenderTests`, `StatisticsRenderTests`, `BandsRenderTests`, `SettingsRenderTests`, `SuggestionsRenderTests`): every declared control state for these five features, all passing; combined SwiftPM UX coverage 94.2% across the 13 new files (Suggestions specifically 93.0%, up from 8.3%)
- ✅ `tools/mock_service.py` extended with `/api/rankings/{instrument}/{accountId}`, `/api/player/{accountId}/bands`, teamKey-filtered `/api/rankings/bands/{bandType}` (`selectedBandEntry`), band rank history/songs and per-song band leaderboard routes (none existed before)
- ✅ XCUITest journeys: `ProfileStatisticsJourneyTests` (search→view→select→Statistics→deselect) and `BandsJourneyTests` (2: Band Rankings row→Band Detail→song; Player Bands paging) pass on-device; `SettingsJourneyTests` (3: relaunch persistence, reorder sheet, reset) `XCTSkip`'d — consistently hung the shared simulator's 300s lock budget under heavy concurrent-lane load, root cause inconclusive (not the carousel-idle issue the other two files needed fixing)
- **Found (fixed independently by Lane Z2 during this lane's work, confirmed via rebase):** `SongsUITestSupport.selectViewedPlayer`/`viewFixturePlayer` were stale against `ProfileSelectionSheet`'s dismiss-then-push navigation — selecting a different profile from Songs pops back to the Songs tab root itself, not the pushed player page
- Named the Profile journey file `ProfileStatisticsJourneyTests` (not `ProfileJourneyTests`) to avoid colliding with Lane Z2's own class of that name

**Lane Z2 — Wrong-account profile bug** (Opus) — 🟨 running in `~/repos/FestivalNativeApps-lanes/wrongacct` (viewing a searched player could show another account's data; client-side)

Coverage (SwiftPM hosted): Songs 91.3%, Song Detail 92.6%, Item Shop 94.5%, Rivals/Compete 87.8%, Suggestions 8.3% (→ U4)

**Lane U3 — UX tests: Rivals & Compete** (Sonnet) — ✅ landed
- ✅ `RivalsRenderTests.swift` (29 hosted tests) + `CompeteRenderTests.swift` (6): every declared control state (no-profile, loading, empty instruments, song/leaderboard tab, Common Rivals + Combo, per-section 503/empty, All Rivals loaded/empty/unavailable/combo/common/unknown-category, Rival Detail categorized/no-songs/unavailable/nil-scope-fallback/leaderboard-scope, Rivalry ordering, Find Rival's 5 search states)
- ✅ `RivalsMockService.swift`: Rivals reads bypass the injectable `HTTPTransport` (raw `URLSession` at `FestivalAPI.baseURL`, confirmed still true after Lane K's consolidation moved it to the shared `fetchJSON` gate — still not the injectable transport), so hosted tests launch the real loopback `tools/mock_service.py` as a subprocess (`--port 0`, also added) instead of an in-memory actor
- ✅ `tools/mock_service.py` extended with `/api/player/{id}/rivals/*`, `/api/player/{id}/leaderboard-rivals/*` and `/api/rankings/{instrument}` (see `.agents/testing/fixtures.md`)
- ✅ `RivalsJourneyTests.swift` (5 XCUITest journeys via `ios_sim.py uitest`, batched): Compete → drawer → Rivals → View All Rivals → row → Rival Detail → Rivalry drill-down; Quick Links menu; Find Rival search → select; two `DebugLaunchRoute` scope-carrying deep links. 4/5 pass outright; the 5th (`testCompeteQuickLinksMenuListsBothSections`) passes via `XCTExpectFailure` around a real found bug (below)
- ✅ Added missing `fst.rivals.row.<id>`/`fst.all-rivals.row.<id>`/`fst.rivalry.view-profile` identifiers; confirmed on-device via `drive`'s `tree:` dump that they reach the accessibility tree (not shadowed the way Leaderboards' row identifiers are)
- Coverage: this lane's Rivals/Compete `FestivalUI` files combined 87.8% (1940/2211 lines); below the 90% UX target mainly on `FindRivalSheet.swift` (66%), whose remaining gap is the real search-result-tap navigation push, provable only on-device (see `coverage.md`)
- **Real bug found:** `QuickLinksMenu` (`Common/QuickLinks/QuickLinksToolbar.swift`) activates the row *above* the one actually tapped, reproduced independently on both Compete and Rivals via `ios_sim.py drive` — a shared-component bug affecting every page with Quick Links, not fixed by this lane (out of scope; flagged via `spawn_task`)
- Rebased mid-lane onto Lane K's API-client/`ServiceStatusView` consolidation (landed concurrently); full rebuild + full `swift test` re-run confirmed everything still compiles and passes unchanged

**Lane U2 — UX tests: Songs, Song Detail, Paths, Shop, Suggestions** (Sonnet) — ✅ landed `6920322`…`d26bcaf` — landed `6920322`, `1775788`
- ✅ Triaged the legacy monolith: 34 tests migrated into `SongsJourneyTests`/`SongDetailJourneyTests`/`ShopJourneyTests`, 7 deleted (broken by the instrument-picker-into-Filter and offline-disclosure-removal redesigns), shared helpers into `SongsUITestSupport` (a namespaced `enum`, not an `XCTestCase` extension, so it can't collide with Lane U's own helpers extracted from the same file in parallel)
- ✅ New `SuggestionsJourneyTests` (no-profile guard, filter draft, best-effort incremental load) and `SongSectionIndexScrubberRenderTests` (0→3 hosted cases, previously untested)
- **Found and fixed two real bugs while running the migrated tests against the device:** `SongsScreen`'s card row silently lost its VoiceOver `.isButton` trait when `b84cfa4` combined it with an invisible `opacity(0)` `NavigationLink` (SwiftUI drops fully-transparent children's traits from `.accessibilityElement(children: .combine)`); and the Songs UITest helpers still targeted the pre-redesign inline profile-preview sheet (`fst.profile.open`/`fst.profile.select`) instead of the current shared-chrome button (`fst.shell.profile`) and pushed Player Profile page (`fst.player.*`) — both fixed.
- ✅ **Fixed by Lane Z2:** viewing a searched player's profile could display a *different* account. The cause was not the load task: every search result sat in one Form row, so one tap fired all of them and the last result's profile landed on top. See `.agents/platforms/apple/architecture.md` ("List rows hold one action", "Per-entity screens").
- Coverage (SwiftPM hosted, `apple/Sources/FestivalUI/Features/*`): Songs 91.3%, Song Detail 92.6%, Item Shop 94.5% (all above the 90% UX target); Suggestions 8.3% (primary gap — needs hosted snapshot tests, not just the XCUITest journeys added this pass); shared Quick Links 76.6%.
- ✅ Full 41-test XCUITest device pass (a representative subset verified; operator's new ≤5-minute-per-lock-hold rule means the rest needs several more short batches) · ⬜ Suggestions hosted snapshots · ⬜ `apple_xccov_gate.py` iPhone device coverage

**Lane U — UX tests: shell, leaderboards, background, history, notifications, first-run, licenses** (Sonnet) — ✅ landed `bf30198`…`7b85419`
- ⬜ Hosted snapshot per declared control state · ⬜ Per-feature XCUITest journeys against the loopback mock (batched on the shared simulator) · ⬜ Per-feature UX coverage → `.agents/testing/apple/coverage.md`

Not yet assigned:
- ✅ Statistics = selected player's profile page (assigned to Lane P)
- (none — Wave 2 fully assigned)

### Wave 3 — quality gates (iPhone)
- ✅ UX tests per completed feature (XCUITest + hosted snapshots, ≥90% UX coverage)
- ✅ Unit coverage ≥95% non-UX
- ✅ Accessibility pass (whole app) · ⬜ VoiceOver pass

### Operator bug batch (2026-09-28)

| Lane | Items | Status |
|---|---|---|
| **W1** (Duo shell) | Never navigate away on profile/band selection (remove all `selectionRevision` path resets) · Duo: Select Profile in rail · Leaderboards → Profile → Back rail jitter | ✅ (jitter reduced; intermittent 2–3 frame residual, see `.agents/design/apple/duo.md`) |
| **Z2** (wrong-account) | Root cause: all search results in one Form row → one tap fired every row's button (also Find Rival); `.id(accountId)` resets; profile graphs (rank history + percentiles); selection updates in place | ✅ `061bba5`…`77a098f` |
| **M2 — Modals & loading** (Sonnet) | Close/Done trailing app-wide · profile search purple bg (hardcoded `appBackground` fill) · Notifications Done · white spinner, no subtitle (`FestivalLoadingView`) · form-sized sheets on Duo unfolded/iPad | ✅ `06543ab`, `dc73e42` (follow-ups: Suggestions/PlayerHistory sheets use custom Cancel/Apply footers — harmonize to toolbar placements; Songs/Profile spinners → S2/Z2) |
| **A2 — Nav-bar accessories** (Opus) | Research iOS 26 accessories · Search placement · Select Player accessory · Quick Links decision · page sweep · Apple global search | ✅ decision record [nav-accessories.md](.agents/design/apple/nav-accessories.md). Superseded by issue #92 (2026-10-04/05): iPhone page tools + bell/avatar in the system tab-bar accessory (Duo/iPad: trailing top-bar groups), a Search tab and the pinned "Filter Songs" field; Suggestions + Rivals-root toolbar order fixed. Open: result-count announcement; hosted snapshots per global-search state |
| **S2 — Songs polish** (Sonnet) | Section headers (real `Section`), bigger chip icons (70%), no status badges (+ `statusAmber` token), `MarqueeText`, first-paint art gate (≤900 ms), compact Duo-safe scrubber | ✅ `93eb2d1`, `ff51d31` (follow-ups: inset cards beside scrubber; MarqueeText in Song Detail header + Suggestion cards; re-run SongsJourneyTests) |
| **L2 — Leaderboards spotlight** (Sonnet) | Selected player highlighted in top 10 / spotlight row below (per-account rank read), jump-to-page on Full Rankings, pinned "You" footer on song leaderboards | ✅ `23dbd60` (band spotlight deferred: no native band identity) |
| **H — Hosted snapshot fidelity** (Opus) | Hosted harness renders full pages nearly blank → fix harness, add content assertions, re-measure coverage | ✅ root cause: tinted Liquid Glass blanks `cacheDisplay`; see [hosted-snapshots](.agents/testing/apple/hosted-snapshots.md) |

**Lane H — Hosted snapshot fidelity** (Opus) — ✅ landed `1d5aa82`, `51a03ce`: tinted Liquid Glass made captures transparent → tests force Reduce-Transparency fallback, `nativeHostedSettle`, `assertRendersContent`; blank/spinner captures 33 → 3; UX 66.8% → 70.4%; 597 tests.

**Lane C — Apple cleanup + gates** (Opus) — ✅ landed `19c8f8f`…`1ccd78d`: coverage gate recursive-glob fix (UX gate was silently classifying ~1 of 104 FestivalUI files) · logic coverage 93.90%→95.81% · Rivals Common Rivals 503 fix · Compete honest empty state · Songs scrubber card inset · MarqueeText in Song Detail/Suggestions · Suggestions/PlayerHistory sheets to semantic toolbar placements · shared `FestivalApp` UITest launch helper (migrated 14 call sites) + found/fixed `MarqueeText` not honoring `FST_DEBUG_STILL_BACKGROUND` (root cause of Songs/Suggestions journey hangs) · retired `tools/apple_native_matrix.py` (stale single-file assumption, unused) · fixed `test_contrast_gate` for the color-only chip design · un-skipped all 3 `SettingsJourneyTests` (confirmed simulator contention, not a bug)

### PWA reference lab (operator, 2026-09-28): "research is good, repro is better"

Install the real PWA on every platform, record pages/animations/navigations, compare with native builds, and feed gaps back to lanes.
- 🟨 **PWA-Apple** (Opus, Mac): Safari Add to Home Screen on iPhone 26.5 / iPad / Duo folded; macOS Add to Dock; scripted drive + video; `.agents/testing/pwa-reference/apple.md` + `apple-gaps.md`
- 🟨 **FST-pwa-winandroid** (Windows host): Edge app on Windows (window-size presets), Chrome install on every `FST_` AVD (phone, book/passport fold, tri-fold, tablet); `windows.md`, `android.md`, `*-gaps.md`
- Rule added to `AGENTS.md` change loop: reproduce against the installed PWA before implementing.

### Global search (operator, 2026-09-28) — all platforms, all layouts

Web: a magnifier in the shell header on every page opens one search over songs (local catalogue), players and bands. Spec: [global-search/spec.md](.agents/controls/global-search/spec.md) (contract `global-search`, `fst.global-search.*`). Safety: players via `GET /api/account/search` (allowed); **band search writes → Bands scope shown but unavailable, with explanation and a Band Rankings link**; songs are local.
- ✅ **R-search** (Opus, docs only): web behavior spec, Android/Windows per-layout designs, contract entry, this plan.

| Lane | Owns (edit) | Tasks | Test plan |
|---|---|---|---|
| **A2** (Apple, Opus) — ✅ (see [global-search/ios.md](.agents/controls/global-search/ios.md)) | Apple files only; records `ios.md`/`ipados.md`/`macos.md` under `.agents/controls/global-search/` | Search action in every page's chrome on iPhone 26 / pre-26, Duo folded + unfolded, iPad, macOS; shared engine for songs + players; Bands explanation; routes onto the current tab | Swift Testing for the engine (debounce, cancel, late result, <2 chars, empty → Retry, freeze, no band request); XCUITest open/search/tap/Back per layout; hosted snapshots per state |
| **win-search** (Windows) — ⬜ ready | `Festival.Core/ViewModels/GlobalSearchViewModel.cs`, `Domain/GlobalSearchResults.cs`, `Pages/SearchPage.xaml(.cs)`, `MainWindow.Search.cs`, the `TitleBar.Content` + compact button in `MainWindow.xaml`; `AppRoute.Search` via `win-shell` | 1. Model + tests · 2. Title-bar `AutoSuggestBox` + mixed suggestions · 3. Search page (SelectorBar All/Songs/Players/Bands, grouped list, Retry, InfoBar) · 4. Compact (<720 epx) button · 5. Ctrl+E / Ctrl+F accelerators · 6. Narrator notification · 7. UIA journeys ([windows.md](.agents/controls/global-search/windows.md)) | xUnit ≥95% on the model/results; `uiwin.py drive` at `compact`, `medium`, `wide`, `snap-left` (+683 epx): Ctrl+E, type, arrow + Enter on a suggestion, submit → page, scopes, Bands InfoBar, Back; fixture log shows no `/api/bands/search`; Axe.Windows scan of the page |
| **and-search** (Android) — ⬜ after the Android foundation | `search/GlobalSearchModel.kt` + UI `search/GlobalSearch*.kt`; one shell call site via the shell owner | 1. Model + JUnit · 2. Compact action → `ExpandedFullScreenSearchBar` · 3. Medium docked · 4. Expanded persistent `SearchBar` + docked panel · 5. Fold/tabletop/tri-fold clamping + continuity · 6. Ctrl+K / Search key / Ctrl+F + shortcuts helper · 7. Predictive back + TalkBack ([android.md](.agents/controls/global-search/android.md)) | JUnit ≥95% on the model; Compose UI tests by `testTag`; `device.py drive` on phone, book fold (folded/unfolded/tabletop), passport, tri-fold (3 states), tablet, resizable presets, each with a fold/resize mid-search continuity check; TalkBack walkthrough |

### Wave 4+ — other form factors

**Lane W — iPhone Duo research + adaptive layout architecture** (Opus) — ✅ landed
- ✅ Research + decisions: `.agents/design/apple/duo.md` (per-pose layout, list/detail pages, toolbar rules, root plan, baseline breakages B1–B8), `.agents/platforms/apple/duo.md` (SDK APIs, vertical bar, reserved regions, hinge, simulator limits)
- ✅ `App/Layout/DeviceLayout(+Environment).swift`: pure `LayoutSignals → DeviceLayout` + `\.deviceLayout`, published at the root (behavior-neutral); 14 unit tests
- ✅ `ios_sim.py pose` / `shot --pose --display` / `drive --pose` / `shutdown`; driver `back` taps the vertical-bar `BackButton`
- ⛔ **Pose/rotation cannot be scripted** (no simctl/XCTest hinge; `XCUIDevice` rotation ignored on the outer display). Unfolded, partially folded and rotated-outer captures need the operator to set the pose in Device Hub; then `shot --pose …` verifies it.

**iPhone Duo bespoke layout** — ready to launch once Lanes U/U2/U3 finish (they assert against the shell). Decisions: [design/apple/duo.md](.agents/design/apple/duo.md). Each lane rebases on the previous lane's seam; Duo captures always use `--device duo --pose …` and end with `ios_sim.py shutdown --device duo`.

| Lane | Owns (edit) | Ordered tasks |
|---|---|---|
| **W1 — Duo shell** (Opus) | `App/FestivalRootView.swift`, `App/Shell/*`, `App/Layout/*` | 1. Extract `FestivalShellContent` reading `\.deviceLayout` · 2. Regular section set from `usesRegularSectionSet` (Duo only; iPhone-landscape decision → orchestrator) · 3. Drawer insets by `overlayInsets`, never covers a leading vertical bar/camera (B5) · 4. Root chrome: profile symbol + title in vertical bars, bell `visibilityPriority(.high)` (B1) · 5. Folded captures ×4 rotations (operator rotates in Device Hub) |
| **W2 — Duo list/detail** (Opus) | new `App/Layout/ListDetailStack.swift`, `App/Layout/ListDetailPolicy.swift` (+ tests); `SongNavigationRoot.swift` handed over from Lane S | 1. Pure `ListDetailPolicy.split(section:path:)` + tests (fold/unfold keep state) · 2. `ListDetailStack` (`NavigationSplitView` list + detail `NavigationStack`, empty-selection placeholder) · 3. Songs → Song Detail · 4. Full Rankings → Player · 5. Rivals/All Rivals → Rival Detail · 6. Unfolded + partially folded captures (operator unfolds) |
| **W3 — Duo page polish** (Sonnet) | `Features/Leaderboards`, `Features/SongLeaderboard`, `Features/Songs` (scrubber only), `Features/{Statistics,Suggestions,Settings,Profile}` layout-only edits | ✅ landed `e0e887f`: 1. ✅ Pagination footer → `.bottomBar` symbol items when `.verticalBar` (B2) · 2. ✅ Instrument/sort capsules audited — already `Menu` + `Label`, nothing to convert · 3. ✅ Scrubber margin beside a trailing bar (B4, confirmed via fresh capture) · 4. ✅ Regular-width 2-column grids for Leaderboards overview + Statistics/Profile (Settings gets readable-width instead, per design doc) · 5. ✅ Row accessibility frames inside the content area (B6, rankings/leaderboard `List`s) · Also: rail overflow decision (Bell+Profile visible, hamburger overflows) formalized as `RootChromeRailItem` + test; found and fixed reappear-reload jitter in `PlayerProfileContent`/`InstrumentGlobalRankView`/`SuggestionsScreen` (same `.task(id:)`-restarts-on-reappear quirk as pre-W1 Leaderboards) |
| **W4 — Duo UX tests** (Sonnet) | `Apps/iOSUITests/Duo*.swift`, `Tests/FestivalUITests/Duo*HostedTests.swift` | 1. Replace `testDuoOuterFourRotations` with pose-guarded journeys (`--pose`) · 2. Hosted snapshots per pose by injecting `\.deviceLayout` · 3. Vertical-bar item visibility/overflow assertions · 4. Duo coverage row in `.agents/testing/apple/coverage.md` |
| **AP — Apple polish** (Opus) | `Design/StarRating.swift`, `Resources/Stars.xcassets`, `FestivalDesign/FestivalText.swift`; foreground styles in Profile/Statistics/Rivals/Compete/Suggestions/Bands/Notifications/Search/Common/Design | ✅ `42a5448` `StarRating(stars:gold:style:size:)` + web `star_white`/`star_gold` · `509a219` Suggestions + Band Detail stars · `e6559db` removed "This Is Me"/"Public Profile" subtitle + seal · `8b0297b` white-text rule (`FestivalText`, [architecture.md](.agents/platforms/apple/architecture.md#text-colour-rule-operator-rule-2026-09-28)). Left for owners: SF stars in `Songs/SongProfileMetadataPills.swift` (A2), `FirstRun/Demo/*` (PS), `SongLeaderboard/SongBandLeaderboardScreen.swift` (PB/PD); Stars attribution in `Settings/LicenseManifest.swift` (PS); white-text sweep of Songs/SongDetail/Shop/Leaderboards/Settings/FirstRun/WhatsNew |

Order: W1 → (W2 ∥ W3) → W4. Blocker for native evidence: operator time in Device Hub (unfold, partial fold, 3 outer rotations).

- ⬜ iPadOS · ⬜ macOS · ⬜ iPhone iOS 17 classic tab bar
- 🟨 Android / Windows — Windows host is `sfenton-music` (2026-10-02; `sfenton-primary` left the mesh); release-machine workers and `tools/win_relay.py` lanes run there
  - **Lane AND — Android foundation** (remote) — ✅ `800e20f`…`e16ad03` (pushed from Windows): Compose architecture, request gate, typed routes, DataStore profile, adaptive shell (bar/rail/permanent drawer), shared background, Songs + Song Detail live (list-detail on expanded); 74 tests, logic 96.8%, UI 87.3%.
  - **Android feature lanes** (Remote Control sessions `FST-and-*`, launched 2026-09-28): `and-shell-search` (adaptive shell per posture/size + global search) · `and-leaderboards` · `and-profile` · `and-rivals` (incl. Compete) · `and-suggestions` (Kotlin generator + seed parity) · `and-bands` · `and-settings` (Settings, Licenses, first-run, notifications, Quick Links) · `and-songs` (Songs parity, Item Shop, Paths). Each integrates itself via `tools/git_integrate.py`.
  - ✅ `and-rivals` (`68704f5`…`427c8ed`): Rivals hub (Song/Leaderboard, Common + per-chart), All Rivals, Rival Detail, Rivalry, Find Rival (`allowLiveFallback` from Find Rival only), Compete (ranking scopes + combo boards); hinge-split half-open, tablet 2-col; 53 tests, 92–100% logic / 87–100% UI. Follow-ups: device-drive journeys, Passport/TriFold/Resizable shots, half-open gap ~17 px left of fold, Rank By picker, native combo full board, TalkBack.
  - ✅ `and-profile` (`da539e0`…`8fc36cf`): profile sheet (Players/Bands, band search never requested), player page with Select/Switch/Deselect that never navigate away, overview + per-instrument stats (client-side), global rank, lazy rank-history/percentile charts, Statistics tab, score history; `SelectedProfileStore` persists across cold starts (device-verified); phone/book/passport/tri-fold/tablet shots; 21 tests, profile files 93–98% (charts 65%, Canvas). Gaps → follow-up: Song Detail → score history entry, player-page Quick Links, top songs, tap-to-filter tiles, hinge padding, TalkBack.
  - ✅ `and-settings` (`31453e6`…`b6a8436`): Settings (every web section with native meaning, DataStore, `SettingsRegistry` reset policy), Licenses (generated manifest, `licenses --check` now in CI), first-run (Apple semantics, 42 live demo slides), notifications (bell, New/Older, seen state), Quick Links per form factor (sheet / menu / persistent pane / hinge split); 442 tests, logic 97.3%, UI 85.0% app-wide. Open: tablet/fold content drawn under the status bar (→ shell), Songs/Paths consumers of settings, passport/tri-fold/resizable evidence, TalkBack.
  - ✅ `and-songs` (`6afe1ef`, `5c49cde`, `2bcdca0`, `cf20670`): Songs parity (Shop sort/filters, per-chart score/FC filters, paused states, drafts, corrupt-filter Reset, marquee, section index), Song Detail parity (Shop badge, Paths, band links, own-row highlight, Show My Rank, score-history link), CHOpt Paths sheet, Item Shop page (list/grid); 190+ tests, logic 97.5%, UI 87.5% app-wide. Follow-up lane `and-songs2`.
  - ✅ `and-leaderboards` (`7981850`…`3ee2432`): Overview (top-10 per visible instrument + bands, persisted Rank By, ≤4 concurrent reads), selected-player spotlight, anonymous rows inert, Full/Band Rankings (25-row pages, pickers, shared pager, Your Page jump), song leaderboard selected-score footer; grid ≥340 dp cards, supporting pane ≥840 dp, hinge-exact half-open split; 41 tests, logic 97.8%, UI 91.1% app-wide. Open: Quick Links + rank-history on overview, band spotlight, paging not in route, song footer ignores leeway, TalkBack.
  - ✅ `and-bands` (`f9cd1ae`…`ad33432`): Bands landing (no-search explanation, selected-player preview, rankings cards), Player Bands, Band Detail (members, stats w/ Rank By, rank history, best/worst songs), song band leaderboard; lookups only via `?teamKey=`, bare bandId → "Band Not Available" with no request; fold/hinge/tri-fold/tablet panes; 43 tests, Bands logic 96–100% / UI 91–100%. Entry points handed to and-songs2 (Song Detail) and and-profile2 (player page). Not built: combo filter, Select Band Profile, Quick Links.
  - ✅ `and-shell-search` (`e0c7f8b`…`b6513a1`): NavigationSuiteScaffold shell (bottom bar / centred rail / permanent drawer), global search (full-screen phone, docked ≥600 dp, fold-aware, Ctrl+K/Ctrl+F, TalkBack counts, never band search), content clipped below the top bar, M3-Expressive-style floating toolbar slot (`ui/common/FloatingToolbar.kt`), Quick Links as menu/bottom sheet (no side pane), drawer honours Hide Item Shop, first-run position in dots' stateDescription; 7/7 device journeys on all AVDs; logic 97.9%, UI 93.2% app-wide. Open: embedded Song Detail pads status bar itself, Songs filter → `RegisterPageFind`, floating toolbar hide-on-scroll, TalkBack pass. Note: `SelectedPlayer.validated` now uses the shared `[A-Za-z0-9_-]{1,128}` rule, so `search_journey.py`'s 32-hex remap is likely obsolete — verify in the device-testing lane.
  - ✅ `and-profile2` (`f3ffb60`…`025e656`): player-page Quick Links, top/bottom songs, tap-to-filter tiles, Bands section, combined bar+line Rank History with swipe/paging, headers above cards, fade-in, native sheet search, hinge-aware grid; instrumented journeys 5/5 on phone + book half-open; logic 97.9%, UI 93.1%.
  - ✅ `and-suggestions` (`e50082d`…`d85cf82`): Kotlin generator with exact Apple parity (228 + 27 remix pages via the Windows fixture), screen + filter, hinge-aware two-column half-open layout; 99.0% logic / 96.8% UI. Follow-up: consolidate onto `SelectedProfileStore`.
  - **Original Android foundation brief:** port Copilot foundation → tooling (build/emulator/screenshot, one emulator at a time) → Compose architecture + request gate + typed routes → adaptive shell (bar/rail/list-detail) → Songs + Song Detail live → JUnit ≥95% logic
  - **Lane LAB — Device lab** (remote) — ✅ `7ddc2b3` (pushed from Windows): 6 `FST_` AVDs boot (phone, book/passport fold w/ real postures, tri-fold approximated, tablet, resizable); `tools/android/device.py` + `tools/windows/uiwin.py` with FIFO locks (300 s); TalkBack on AVDs, Axe.Windows/Accessibility Insights/PresentMon/FlaUI installed. Original scope: SDK/tool updates; `FST_` AVD matrix (phone, book fold, passport fold, tri-fold, tablet, resizable); `tools/android/device.py` + `tools/windows/uiwin.py` with global locks (one emulator / one desktop driver at a time, ≤5 min holds), window-size presets for Windows desktop/tablet
  - **Lane WIN — Windows foundation** (remote) — ✅ `9b37ab4`…`7868ab6` (pushed from Windows): **C# NativeAOT** chosen with measurements (C++/WinRT 173 ms/88 MB vs C# AOT 182 ms/92 MB first frame/WS; animation ≤1% core); background stepped to 30 Hz (15%→3–4% core, 1% GPU); 240 fps scrolling p99 5–8 ms; Mica shell, request gate, typed routes, persisted settings, Songs/Song Detail/Settings live; 214 tests, logic 99.5%, VM 100%.
  - **Windows feature lanes** (Remote Control sessions `FST-win-*`, launched 2026-09-28): `win-leaderboards` (overview/full/band rankings, song leaderboard, spotlight) · `win-profile` (selection, profile page + graphs, Statistics, history) · `win-rivals` (hub, all, detail, rivalry, Find Rival) · `win-suggestions` (C# generator port w/ seed parity) · `win-bands` · `win-settings` (Settings, Licenses, first-run, notifications, Quick Links idiom) · `win-songs` (Songs parity, Item Shop, CHOpt Paths). Each integrates itself via `tools/git_integrate.py`.
  - ✅ `win-suggestions` (`74a3863`…`17ea7c0`): exact parity with Apple generator (swiftc on Windows compiles unmodified Apple sources; 6 seeds × 228 pages), 828 Core tests.
  - ✅ `win-settings` (`d234d24`…`97b77bb`): all web Settings sections + Accessibility, Licenses from NuGet graph, first-run (ContentDialog, replay), notifications bell/flyout, Quick Links (menu < 1150 epx, pane ≥ 1150); 99.6% lines.
  - ✅ `win-leaderboards` (`d56f75f`…`bd71f1c`): overview + spotlight, full/band rankings w/ pinned "your rank", song leaderboard; 3-col grid wide; idle 0.03% CPU; found anonymous production ranking rows (fixed on Apple too, `2e90438`).
  - ✅ `win-bands` (`be040ba`…`8719acf`): landing, player bands, band detail (safe `?teamKey=` read only), per-song band leaderboard; 99.3% band-file coverage; fixed tooling that killed other lanes' app windows; found bare `/api/rankings/bands/{type}/{teamKey}` writes (now in service-safety; Apple never used it).
  - ✅ `win-songs` (`549b9ea`…`5e9422e`): Songs parity, Song Detail (Shop, Paths dialog, your-score, history), Item Shop page; 829 tests; idle 0.01% CPU; `AppSettings` init→set fix.
  - 🟨 `win-search` (`FST-win-search`): global search (title-bar AutoSuggestBox, Search page, compact button, Ctrl+E, Narrator).
  - ✅ `win-profile` (`71d09bc`…`46648e8`): profile flyout, player page = Statistics (select/switch/deselect in place, rank history + percentiles), score history, persisted selection; 830 tests; 7 journeys pass (Debug).
  - ✅ `win-rivals` (`3789228`…`6bd8cd3`): hub (Common/combo/family), All, Detail, Rivalry, Find Rival, typed scope; 7/7 journeys on AOT; idle 0.01% CPU.
  - ⬜ **Rivals live fallback (all platforms):** pass `allowLiveFallback=true` on rival detail **only when opened from Find Rival** (web: `RivalsPage.tsx:263` route state → `client.ts:490`; verified read-only, `c873ce1`) — carry the flag in the typed `RivalScope`/route.
  - ✅ `win-shell` (`3881458`…`2d46afe`): NavigationView Auto (LeftMinimal <641, rail 641–1007, expanded ≥1008; 9 pages × 7 configs), occlusion pause (covered 0.3–2.2% core), per-worktree Debug data dir, AppStateFiles reset registry, UIA foreground/--isolate; 848 tests.
  - 🟨 `win-infra` (`FST-win-infra`): Release/AOT automation switch, coverage gate for async partials, CI windows-latest job, title bar <720, search VM reuse, rivals live fallback, Quick Links everywhere.
  - 🟨 `win-a11y` (`FST-win-a11y`): **Windows accessibility phase** — Axe.Windows 0 errors per page, keyboard order/focus, Narrator names + announcements + manual script, high contrast/text scaling/animations off/transparency off.
  - ⬜ **Windows infra backlog** (now assigned to win-infra) (next shell/infra lane): Release/AOT UI automation — first-run dialog has no test-launch opt-out (`--first-run=off` for automation) and UIA tree walk fails while it's open; plus:
  - ⬜ Wire `tools/windows/tests` + `tools/android/tests` into CI (windows-latest runner).
  - ⬜ Windows coverage gate: async-only Rivals/Notifications client partials report uncovered (compiler-generated exclusion) — fix in next shell/infra pass.
  - 🟨 `win-shell` (`FST-win-shell`): compact NavigationView, occlusion pause, per-lane Debug data dir, UI-automation foreground robustness, reset registry.
  - **Original Windows foundation brief:** port Copilot foundation → **C# vs C++/WinRT measured decision** → tooling → MVVM + request gate → NavigationView shell (Mica, split Leaderboards/Rivals) + composition-thread background → Songs + Song Detail live → tests
| 2026-10-01 | Orchestrator | Versions `YYMM.DD.NN` on all platforms (first `2610.01.01`; day added same day, two-part tags removed): `version-bump.yml` tags `<platform>/v…` on master merges that touch an app and dispatches its build (the only build/release trigger); TestFlight notes per build; in-app What's New generated per platform as `WhatsNew.json` (one section per released version, from `Release-Note[-Platform]` trailers) on iOS/macOS/Android/Windows; stale-baseline rebuilds; tracker carries trailers into merge commits and tags `<platform>/released/<v>` |

---

## 5. Known issues / decisions

- **iPhone floating page tools (owner, SFenton/festival-report-tracker#632, 2026-10-13):** the tab-bar accessory is gone on iPhone. Page tools are individual 44 pt Liquid Glass circles above the tab bar (`FloatingPageTools.swift`, web `MobileFloatingActionButton` motion), Notifications shares a header pill with Profile, and titles are leading (`festivalTitleDisplayMode`). Duo, iPad and Mac keep bar items ([page-tools-and-nav-chrome R28](.agents/patterns/page-tools-and-nav-chrome.md)).
- **Apple loading placement (SFenton/festival-report-tracker#624):** page/result indicators use the canonical `FestivalLoadingView(placement: .fill)` and the existing empty-state fold policy ([load-transition](.agents/patterns/load-transition.md) R13). Ordinary phone, flat Duo, tablet and Mac region centres remain unchanged; active vertical/horizontal folds use the larger usable side. Inline/card indicators and Paths are unchanged.
- **Android loading regions (#624):** page gates and reload spinners share `LoadingRegion` and the existing `HingeSide` policy; lazy spinners measure the result area rather than a viewport fraction. Song Details keeps its scroll viewport and supplies chrome padding only to the gate's spinner. Other platform checks remain in their own worker lanes.

- **App versions and What's New (operator, 2026-10-01):** every platform is `YYMM.DD.NN` (UTC date + daily counter) from `<platform>/v<version>` tags; only a version bump starts a build; user-visible changes carry `Release-Note:`/`Release-Note-<Platform>:` trailers and nobody hand-edits `WhatsNew.json`. See `.agents/workflow/release-machine.md#versions-notes-and-whats-new`.
- **Release machine (operator, 2026-09-30):** issues filed in private `SFenton/festival-report-tracker` are triaged and implemented autonomously (Mac worker for Apple surfaces, branch `report/<n>`), merged once `apple-ci` + `inventory` pass, and released by gated pipelines. Only the iOS App Store pipeline is active (blocked on ASC key/Distribution cert); Android/Windows/macOS/iPadOS release workflows are disabled scaffolds. See `.agents/workflow/release-machine.md`.
- **Operator decision (Duo rail, 2026-09-28):** folded Duo with a profile (5 tabs) keeps **Bell + Profile** visible in the vertical rail; hamburger moves into "…".
- **Operator decisions (Duo, 2026-09-28):** (1) **UI scripting allowed** for Device Hub poses — operator grants macOS Accessibility permission (agents never change security settings); (2) ~~split Leaderboards/Rivals tabs **only on Duo unfolded + iPad**~~ superseded by the owner in #337: every phone pose, Duo unfolded included, keeps the phone tabs (Compete; Statistics from Profile); only iPad/Mac list Leaderboards/Rivals; large iPhones keep portrait tabs in landscape.

- **Slim simulators (owner, 2026-10-25):** every FST simulator boot is slimmed with simslim inside its devcap hold (`ios_sim.boot_exclusive` → `tools/sim_slim.py`, profile `tools/simslim/ui.json`: only Photos kept), as Fenton-HASS-Native does; `FST_SIM_SLIM=0` opts a run out and CI runners stay stock. Rules: [capacity](.agents/platforms/apple/capacity.md#slim-simulators). Raising the shared slot count is a separate decision.
- **One simulator booted at a time (`ad76e5e`):** `ios_sim.py` shuts down other FST simulators before booting a device (Duo lane had both iPhone and Duo booted).
- **SwiftUI sheet environment trap:** environment actions set by the presenter weren't visible inside `.sheet` content in practice; pass closures into sheets explicitly (see `.agents/controls/profile-selection/ios.md`).

- **Simulator lock budget:** UX lanes' XCUITest batches held the lock 10+ min and starved feature lanes. Rule: ≤5 min per lock hold with a hard timeout, batches split; `ios_sim.py uitest` (Lane U) enforces it.

- **Toolbar order rule (`c53b5cb`):** profile avatar is rightmost on tab roots, with the bell in one capsule. Tab roots with their own actions compose `FestivalRootTrailingItems` last and use `.topBarTrailing` (see `.agents/controls/app-navigation/ios.md`).
- **Band detail GET writes:** `GET /api/bands/{bandId}` rebuilds band team configs on cache miss → blocked; band detail resolves via `/api/rankings/bands/{bandType}?teamKey=`.
- **Test-ID families are implicit:** `verify_product.py` accepts `fst.<page-or-control-id>.*` for every declared page/control.
- **Not ported (by design / blocked):** Settings Export ZIP + profile-name refresh (POST-only); live Service Progress and `/api/version` (not on the verified-read allowlist); "select as band profile" (needs session band identity).

- **Scrape freeze UX (Lane K):** a 503 carrying a score-update `x-fst-public-read-freeze-reason` now shows "Scores are updating" with an automatic `Retry-After` countdown on every screen (see `.agents/platforms/service-safety.md#public-read-freeze`).
- **Rivals detail endpoints re-checked (2026-09-28):** `/rivals/{combo}/{rivalId}` and `/leaderboard-rivals/{instrument}/{rivalId}` return HTTP 200 for the sample account outside an active scrape window (verified live, both via `curl` and a loaded `RivalDetailScreen` in the simulator). They still 503 during one — now with an explicit `x-fst-public-read-freeze-reason: scrape` response header (`Retry-After: 30`) instead of the earlier bare 503 — while the list endpoints (`/rivals/{instrument}`, `/leaderboard-rivals/{instrument}`) keep returning 200 through the same freeze. The app's existing `ServiceUnavailableView` + retry already handles this correctly; no code change needed, just confirmation the condition is transient (scrape-scoped), not a permanent block.
- **Load ceiling:** ~9 concurrent lanes pushed load to 170+ on the 10-core Mac; don't add lanes above ~100 load.

- **Simulator queue stall (fixed `c3b55f3`):** XCUITest waits for app idle before each action; the always-animating carousel never idles, so a 10-step `drive` held the sim lock 8+ min with 7 jobs queued. `drive` now sets `FST_DEBUG_STILL_BACKGROUND=1` by default (`--animate` opts out) and enforces `--timeout` (180 s).

- **Manual is deprecated** (operator, 2026-09-27): not ported. Route, drawer item, placeholder screen, contract entries and docs removed.

- **Leaderboards follow-ups:** ✅ selected-player spotlight ported (Lane L2, see `.agents/pages/{leaderboards,full-rankings,song-leaderboard}/ios.md`) — no band spotlight yet (no native selected-band identity); still no rank-history chart, no band-combo filter on the overview; per-card loads are sequential. Hosted-harness blank pages: fixed by Lane H (forced glass fallback, settle + `assertRendersContent`).
- **Background follow-ups:** the brief's plan of drawing once behind transparent pages failed (the iPhone TabView keeps an opaque layer over anything drawn behind it), so each page draws a synced mirror of one shared state. Open issues: a cancelled swipe-back on pages without a `visible` flag briefly fades; going back fades rather than shrinking the art into its tile; the tap-and-push flow is unverified.

- **Build contention:** 7 lanes on a 10-core Mac hit load 169; SwiftPM builds are serialized via `~/.fst-build.lock` (Lane T adding it to `ios_sim.py build`). Keep ≤7 concurrent lanes.
- **Test-ID families** are registered per page in `contracts/product.json` (`fst.<page>.*`), so new controls don't need registry edits.

- **Live service:** rankings, songs, account search and `/leaderboard/{song}/all` return 200 keyless to native user agents (re-probed 2026-09-27; see `.agents/platforms/service-safety.md`). Keep the no-`X-API-Key` and no-side-effect-endpoint rules from `AGENTS.md`.
- **Instrument icons** are copied from the web app's `public/instruments/` (the operator's own site), downscaled to 144 px.
- **iOS 17 runtime** is not installed on this Mac; iOS 17 is compile-checked only until Wave 4.

---

## 6. Log

| When (PT) | Lane | Change |
|---|---|---|
| 2026-09-27 | Orchestrator | Read Copilot history (11 checkpoints, 7 operator messages); designed lane model; landed foundation `9a5754a` |
| 2026-09-27 | Orchestrator | Launched Wave 1 lanes A, S, P, L, B, D in parallel worktrees |
| 2026-09-27 | Lane A | Landed tabs, root chrome, drawer, Liquid Glass doc, Settings glass, festivalSheet, settings persistence |
| 2026-09-27 | Orchestrator | Launched Lanes T (sim driver), R (Rivals/Compete), G (Suggestions); Statistics folded into Lane P |
| 2026-09-27 | Lane D | `.agents` split by platform/form factor, routers, `check_docs.py` (CI-enforced), single `service-safety.md` |
| 2026-09-27 | Orchestrator | Unblocked public reads (`b17eac2`), per-page test-ID families, serialized builds (`c972417`) |
| 2026-09-27 | Lane L | Leaderboards overview, full/band rankings, native song leaderboard with rows → player |
| 2026-09-27 | Lane B | Shared synced background, song-art zoom transitions, ~4.4% CPU animating / 0% held |
| 2026-09-27 | Orchestrator | Launched Lanes N (Bands), M (Settings/Manual/Licenses); Remote Control enabled for this session |
| 2026-09-27 | Lane T | `ios_sim.py drive` — scripted tap/swipe/type/tree/screenshot via XCUITest driver (~11–24 s/run); build lock |
| 2026-09-27 | Orchestrator | Launched Lane X (history, first-run, notifications) |
| 2026-09-27 | Orchestrator | Dropped deprecated Manual (route, drawer item, contracts, docs) per operator |
| 2026-09-27 | Orchestrator | Split FREs into dedicated Lane F per operator (versioned/hashed seen state, replay settings) |
| 2026-09-27 | Orchestrator | Launched Lane Q (Quick Links) per operator |
| 2026-09-27 | Orchestrator | Unstuck simulator queue: frozen carousel for drives + drive timeout (`c3b55f3`) |
| 2026-09-28 | Lane S | Native toolbar search/sort/filter, glass rows, instrument-icon chips, A–Z scrubber, instrument filter moved to Filter, icon intensity card, offline banners removed |
| 2026-09-28 | Lane X | Player history + notifications (read-only endpoints verified); FirstRun types handed to Lane F |
| 2026-09-28 | Lane R | Compete hub, Rivals hub/all/detail/rivalry; 18 tests; combos + Find Rival deferred |
| 2026-09-28 | Lane P | Fixed profile persistence (tautological publication check after relaunch); player profile page shared with Statistics tab; native profile sheet |
| 2026-09-28 | Lane N | Bands landing, Band Detail, Player Bands, Song Band Leaderboard; found `/api/bands/{bandId}` also writes on a GET (treated as blocked, band detail reads the rankings board by `teamKey` instead); `AppRoute.band` gained additive `bandType`/`teamKey` |
| 2026-09-28 | Lane N | Bands: detail, player bands, landing, per-song band leaderboard; found `/api/bands/{bandId}` GET writes |
| 2026-09-28 | Lane M | Settings: visual/path column reorder, diagnostics, version; Licenses; Manual reverted (deprecated) |
| 2026-09-28 | Lane Q | Quick Links: feasible; toolbar Menu + VoiceOver rotor (iPhone), inspector later (iPad/Mac); adopted on Leaderboards |
| 2026-09-28 | Lane S | Scrubber `#` labels, keyboard icons (`Song.sig`), Player History links from Song Detail |
| 2026-09-28 | Orchestrator | Avatar-rightmost toolbar rule, implicit test-ID families, app versioning; launched Lanes R2, P2 |
| 2026-09-28 | Lane F | FREs: 44 slides / 9 pages, versioned+hashed seen state (only new slides show), gates, Settings replay; 36 Core tests |
| 2026-09-28 | Orchestrator | Launched Lane D2 (FRE demos) and Lane U (Wave 3 UX tests for completed features) |
| 2026-09-28 | Lane G | Suggestions: full generator port (seeded PRNG, 11 families + decades, 61 tests, ~96% Core coverage), filter sheet, incremental loading; fixed direct-landing load hang |
| 2026-09-28 | Lane S | Toolbar order, Quick Links (Songs/Detail), settings consumers, `Song.maxScores` — lane complete |
| 2026-09-28 | Orchestrator | Launched Lane G2 (Suggestions follow-ups) and Lane U2 (UX tests for Songs/Detail/Paths/Shop/Suggestions) |
| 2026-09-28 | Lane D2 | FRE live demos: all 42 catalog slides now render a live native mini-demo (was Songs-only, 9/42); found a likely pre-existing TabView initial-tab race in debug launch + force mode for non-default tabs (see Lane D2 entry above) |
| 2026-09-28 | Lane D2 | Live demos for all 42 FRE slides (coverage test enforces no fallback) |
| 2026-09-28 | Orchestrator | Fixed empty FRE carousel on non-default launch tab (`.sheet(item:)`, `95d799e`); native FRE copy; demo slot clipping |
| 2026-09-28 | Lane R2 | Rivals follow-up: removed `RivalNavigationBridge`, typed `RivalScope` on `AppRoute`; Common Rivals + Combo/Pro-Drums scope ported to Core; Find Rival search; Quick Links on Compete/Rivals/Rivalry/Rival Detail; re-verified rival detail endpoints live (200 outside an active scrape freeze; new `freeze-reason: scrape` header explains the earlier 503) |
| 2026-09-28 | Lane R2 | Typed `RivalScope` on AppRoute (singleton removed), Common/combo rivals (22 tests), Find Rival, Quick Links on Compete/Rivals; 503s explained (scrape freeze) |
| 2026-09-28 | Orchestrator | Launched Lane K (client consolidation + freeze UX) and Lane U3 (Rivals/Compete UX tests) |
| 2026-09-28 | Lane G2 | Suggestions follow-ups: `near_max_5k/10k/15k` + decades ported; `visibleInstruments` seam closed; verified rival-suggestion data needs a combined `/rivals/all` read not yet in `FestivalAPI+Rivals.swift` |
| 2026-09-28 | Lane G2 | near_max families (+decades), visibleInstruments seam; Suggestions Core coverage 96–100% |
| 2026-09-28 | Orchestrator | Sim lock budget rule for UX lanes; `/rivals/all` read assigned to Lane K |
| 2026-09-28 | Lane K | One keyless request path (Rivals off its own URLSession), `ServiceIssue` + `ServiceStatusView` scrape-freeze countdown on all service screens, `rivals/all` exposed, add-endpoint skill |
| 2026-09-28 | Lane K | One request gate + `ServiceIssue` across 20+ screens; scrape-freeze countdown UX; `rivalsAll`; Rivals API coverage 71%→96.7% |
| 2026-09-28 | Orchestrator | Launched Lane G3 (rival suggestions) and Lane W (Duo research + layout architecture) |
| 2026-09-28 | Lane P2 | Global ranks via per-account rankings (live #1 / Top 0.01%), sheet dismiss→push on active tab, in-memory debug profile, Quick Links on Player/Band/Settings, band song titles; Suggestions filter in reset registry |
| 2026-09-28 | Orchestrator | Enforced one booted simulator at a time (`ad76e5e`) |
| 2026-09-28 | Lane U | UX tests for shell/leaderboards/background/history/notifications/first-run/licenses; flaky artwork test fixed; `ios_sim.py uitest` (5-min holds); found 3 bugs |
| 2026-09-28 | Orchestrator | Launched Lane Z (bug fixes from UX tests) |
| 2026-09-28 | Lane W | Duo research (27.1 SDK: vertical bar, `ReservedRegion`, `onHingeChange`, `ArrangementView`), per-pose decisions, `App/Layout` model + env, pose/display tooling, folded baselines (B1–B8), W1–W4 plan |
| 2026-09-28 | Lane W | Duo research (APIs, poses, cutouts), `DeviceLayout` model + env, `ios_sim.py pose/--pose/shutdown`, folded baseline breakages, W1–W4 lane plan |
| 2026-09-28 | Lane G3 | Rival-driven suggestions: `RivalDataIndex` from `/rivals/all`, all ten `song_rival_*` pipelines, rivals loaded alongside the catalogue (best-effort), rival badge on category rows; found `lb_rival_*` is dead code on the web itself; 75 tests, 96.13% Suggestions-Core coverage |
| 2026-09-28 | Lane U2 | Triaged Songs/Shop/Detail legacy UITests (34 migrated, 7 deleted), added Suggestions journeys + section-index hosted tests; found and fixed the Songs-row `.isButton` trait loss and stale profile-flow test IDs; flagged (unfixed) a Player Profile wrong-account-data bug; Songs/Detail/Shop hosted coverage 91–95%, Suggestions 8.3% (open gap) |
| 2026-09-28 | Lane U3 | Rivals/Compete UX tests: 35 hosted snapshot tests, 5 XCUITest journeys, `mock_service.py` Rivals/rankings routes, missing row accessibility identifiers; found a shared `QuickLinksMenu` off-by-one row-selection bug (flagged, not fixed by this lane) |
| 2026-09-28 | Lane G3 | All 10 `song_rival_*` suggestion families (`lb_rival_*` is dead code on web); Suggestions Core 96% |
| 2026-09-28 | Lane U2 | Legacy UITest monolith 4921→1797 lines (7 deleted, 34 migrated); Songs/Detail/Shop ≥91% hosted coverage; fixed VoiceOver button trait on song rows; found wrong-account bug |
| 2026-09-28 | Lane U3 | Rivals/Compete: 35 hosted + 5 journeys, 87.8% |
| 2026-09-28 | Lane Z | Fixed Leaderboards row ID shadowing, Quick Links landing short, FirstRun pulse vs still flag; all journey batches pass |
| 2026-09-28 | Orchestrator | Operator decisions recorded; launched Z2 (wrong-account bug), U4 (Profile/Bands/Settings UX tests), W1 (Duo shell) |
| 2026-09-28 | Orchestrator | Operator bug batch triaged into W1, Z2 (+graphs), M2, A2, S2, L2; rule: selection never navigates away |
| 2026-09-28 | Lane M2 | Modal standard (trailing Close/Done, semantic placements), purple sheet bg removed, `FestivalLoadingView` app-wide, form sheet sizing on regular width |
| 2026-09-28 | Lane L2 | Selected-profile spotlight on Leaderboards overview cards, Full Rankings (+ native jump-to-page footer) and Solo leaderboard (highlight + footer, no extra network read); `RankingSpotlight` pure decision logic + tests; band spotlight skipped (no native selected-band identity); found macOS hosted-snapshot harness renders full-screen pages blank (flagged, not fixed) |
| 2026-09-28 | Lane L2 | Leaderboards selected-player spotlight + song leaderboard "You" footer |
| 2026-09-28 | Orchestrator | Launched Lane H: hosted snapshots render full pages nearly blank (coverage may overstate visual evidence) |
| 2026-09-28 | Lane H | Hosted harness: tinted Liquid Glass made whole `NSHostingView` captures transparent and sleeps captured spinners; forced Reduce-Transparency fallback, in-process accessibility text, `nativeHostedSettle`, `assertRendersContent` on 65 full-page tests (+Settings, Player Profile). Blank captures 33→3 (sparse empty states). SwiftPM UX 66.8%→70.4% recursive; gate's Swift UX glob is non-recursive (flagged). Found Common Rivals hides its 503 error (known issue) and 4 Rivals tests 404ing on a hyphenated mock id (fixed) |
| 2026-09-28 | Orchestrator | Windows host online: SSH verified, toolchains inventoried, `tools/win_relay.py` bundle relay (no GitHub creds on Windows) |
| 2026-09-28 | Orchestrator | Operator: parallelize Android + Windows heavily on the Windows host; launched remote Lane LAB (device lab); GitHub auth on Windows pending operator (`gh auth login --insecure-storage`) |
| 2026-09-28 | Orchestrator | GitHub auth on Windows verified over SSH; Windows `origin` → GitHub; `tools/git_integrate.py` for Windows-host lanes (`ee20551`) |
| 2026-09-28 | Lane S2 | Songs polish: removed instrument-chip star/check/minus/exclamation marks (color-only status, new `statusAmber` token keeps Inconsistent FC distinct from No score), enlarged chip icons to web's ~71% proportion; Duration/Item Shop section headers are now real `List` `Section`s instead of a card-styled row (fixed the opaque-bar-behind-header look); fixed the Duo A–Z scrubber sizing itself to its own letters instead of the full List height (B4: no more creep past `#`/`Z` or row overlap when the large title collapses); ported web's `MarqueeText` (`Design/MarqueeText.swift`, unit-tested `MarqueeTiming`) so long title/artist/year/duration rows scroll instead of wrapping; gated Songs' first reveal on the first ~12 rows' artwork decoding (bounded 900ms, native-only — web has no equivalent). `fst.songs.navigation-notice`'s "Selected profile changed" text needed no Songs-side change (root-only, Lane W1) |
| 2026-09-28 | Lane Z2 | Wrong-account profile fixed at root (one Form row fired every result Button); per-entity `.id` hardening across Profile/Rivals/Compete; select/deselect stays in place (journey); profile Rank History + Percentiles graphs (Swift Charts, pure-read history endpoint) |
| 2026-09-28 | Lanes S2, Z2 | Songs polish landed; wrong-account bug root-caused (single Form row) + profile graphs |
| 2026-09-28 | Lane H | Hosted harness renders real content; content assertions on 65 full-page tests |
| 2026-09-28 | Orchestrator | `win_relay launch/wait`: Windows lanes as monitorable Remote Control sessions (probe verified); launched Lane C (cleanup + gates) |
| 2026-09-28 | Lane U4 | UX tests for Profile/Statistics/Bands/Settings/Suggestions: 43 hosted tests (94.2% combined coverage, Suggestions 8.3%→93.0%), `mock_service.py` Bands/ranking fixtures, 3 XCUITest journeys passing (2 files) + 3 skipped (Settings, simulator-load hang); confirmed Lane Z2's independent fix for stale dismiss-then-push assumptions in `SongsUITestSupport.swift` |
| 2026-09-28 | Lane U4 | 43 hosted tests + Profile/Bands journeys; mock_service band/ranking routes; Settings journeys hand-off to Lane C |
| 2026-09-28 | Lane LAB | Device lab landed from Windows (first direct Windows→GitHub push) |
| 2026-09-28 | Lane W1 | Duo shell: `ShellPresentation` (split tabs only on Duo inner display/iPad), cutout-safe drawer, rail profile symbol + bell/profile priority, selection never navigates (`FestivalTabPolicy.adapt`), rail Select Profile, pop-jitter fixes, `ios_sim.py pose --set` UI scripting (awaiting operator Accessibility grant), `drive --record` |
| 2026-09-28 | Lane WIN | Windows foundation landed from Windows; C# NativeAOT decision with evidence |
| 2026-09-28 | Orchestrator | Launched 7 Windows feature lanes as Remote Control sessions (`FST-win-*`); web source cloned read-only on Windows |
| 2026-09-28 | Lane C | Coverage gate recursive-glob fix (UX gate was silently classifying ~1 of 104 FestivalUI files as 97%); logic coverage 93.90%→95.81%; Rivals Common Rivals 503 fix; Compete honest empty state; Songs scrubber card inset; MarqueeText in Song Detail/Suggestions; Suggestions/PlayerHistory sheets to semantic toolbar placements; shared `FestivalApp` UITest launch helper (14 call sites) + found/fixed `MarqueeText` not honoring `FST_DEBUG_STILL_BACKGROUND` (root cause of Songs/Suggestions journey hangs); retired `tools/apple_native_matrix.py` (stale single-file assumption post-monolith-split, unused elsewhere); fixed `test_contrast_gate` for the color-only chip design; un-skipped all 3 `SettingsJourneyTests` (confirmed simulator contention, not a bug — individually 68–282s) |
| 2026-09-28 | Lanes W1, C | Duo shell + Apple cleanup landed; master green (`671ff23`); launched W2, W3 |
| 2026-09-28 | Windows lanes | win-suggestions + win-settings landed; launched win-shell |
| 2026-09-28 | Windows lanes | win-leaderboards landed; anonymous-ranking-row quirk fixed on Apple + documented |
| 2026-09-28 | Lane W3 | Duo page polish landed (`e0e887f`): rail overflow decision (Bell+Profile visible, hamburger overflows, `RootChromeRailItem`), B2 pagination → `.bottomBar` items, B6 row accessibility clearance, regular-width 2-column dashboard grids (Leaderboards/Profile), Settings readable-width; found and fixed reappear-reload jitter in Statistics/Player Profile and Suggestions (`.task(id:)` restarting on `NavigationStack` reappearance even with an unchanged id) |
| 2026-09-28 | Lane W3 | Duo rail/page polish landed; orchestrator fixed last non-standard spinners (`e5c41a4`) |
| 2026-09-28 | Windows lanes | win-bands landed; new blocked endpoint recorded (`1536971`) |
| 2026-09-28 | Orchestrator | Operator: global search on every page/platform/layout → R-search research lane + A2 Apple scope |
| 2026-09-28 | Orchestrator | Global search spec landed + operator decisions; win-songs landed; launched win-search; verify_product root-ID rule (`78736f3`) |
| 2026-09-28 | Windows lanes | win-profile landed; mock history accuracy scale fixed (`72b147e`) |
| 2026-09-28 | Orchestrator | Operator: repro the installed PWA on all platforms → launched PWA-Apple (Mac) + FST-pwa-winandroid (Windows); AGENTS.md change-loop rule |
| 2026-09-28 | Windows lanes | win-rivals landed; mock Connection: close; rivals live fallback verified safe |
| 2026-09-28 | Android | Foundation landed from Windows (`e16ad03`, docs conflict resolved); launched 8 Android feature lanes as Remote Control sessions |
| 2026-09-28 | Lane A2 | Tab-bar accessory: global Search on every iPhone page (iOS 26.1+) + profile Select/Deselect; system search tab rejected (5 tabs → "More"); Apple global search (sheet, ⌘K/⌘F, toolbar fallback incl. Duo rail/iPad/Mac, Bands blocked); Songs inline filter; Suggestions/Rivals toolbar order; journeys green |
| 2026-09-28 | Windows | win-shell landed; mock server backlog 5→128 |
| 2026-09-28 | Lane W2 | Duo list/detail landed; SongsJourneyTests regression (19/21 failing on master) sent to A2 |
| 2026-09-28 | Orchestrator | Windows Remote Control lanes now appear as peer sessions → orchestrator can message them mid-run |
| 2026-09-28 | Windows | win-search landed (global search on Windows) |
| 2026-09-28 | Windows | Launched win-infra + win-a11y (Windows enters accessibility phase) |
| 2026-09-28 | Android | and-suggestions landed (3-platform generator parity) |
| 2026-09-28 | Android | and-rivals landed (incl. Compete); combo rankings endpoints recorded as pure reads; mock ranking/band accuracy scale fixed (`0212604`) |
| 2026-09-28 | Apple tests | Wall-clock flakes fixed: Retry-After countdown (`\.serviceRetryClock`) and artwork dwell (`ArtworkBackground(clock:)`) run on an injected `ManualTestClock` in tests, with no wall-clock deadlines; see [hosted-snapshots](.agents/testing/apple/hosted-snapshots.md) |
| 2026-09-28 | Android | and-profile landed (selection persists across cold starts) |
| 2026-09-28 | Android | Launched and-profile2 (player-page Quick Links, top songs, tap-to-filter tiles, hinge padding, chart coverage, device journeys) |
| 2026-09-28 | Android | and-settings landed; notifications endpoint recorded as pure read; `licenses --check` in CI |
| 2026-09-28 | Lane PWA-Apple | Installed-PWA lab landed (`caaf562`, `4407d0d`): iPhone/iPad/Duo PWA captures, 22-row gap table (`.agents/testing/pwa-reference/apple-gaps.md`). Incident: one off-screen tap opened a public player page on production (blocked stats + sync-status GETs, no POST/headers); driver now refuses off-screen taps, rule in service-safety. macOS PWA blocked on Screen Recording/Accessibility permission |
| 2026-09-28 | Orchestrator | Launched Apple gap lanes PD (Song Detail pinned header/cards, Item Shop rows), PB (Leaderboards density, Full Rankings floating pager), PS (Settings First Run Guides + Service Info, What's New). Songs gaps (#3–5), drawer highlight (#11), background art (#12/#20) queued behind A2 |
| 2026-09-28 | Android | and-songs landed; shell status-bar overlap fixed (`2c1f471`, screens must not add their own status-bar inset); launched and-songs2 (Quick Links, profile sorts, invalid-score fallback, shop pulse, Settings consumers, all form factors) |
| 2026-09-28 | Android | and-leaderboards landed (Android UI coverage 91.1% app-wide); mock `--large-rankings` for pager captures |
| 2026-09-28 | Windows | win-infra landed: automation mode (`--automation`, Release marker), 30 journeys pass on NativeAOT Release, coverage gate measures async/lambda lines (905 tests, logic 99.41% / UX 98.30%), CI workflow (`native.yml`), DPI-correct title bar, Quick Links host, Find Rival live fallback. **CI blocked: GitHub Actions billing** (every job refused; operator action) |
| 2026-09-28 | Orchestrator | Operator bug batch triaged: iPhone → A2 (floating tab-bar accessory with Search + Filter/Sort + Quick Links; scrubber shift), PB (Rankings subtitle size, header outside card), PS (settings row spacing, CHOpt default-view navigation picker, no "Slide X of Y"), PD (Item Shop button pulse); new Apple lanes AP (star image assets + `StarRating`, white-text rule, remove "This Is Me") and W4 (Duo half-fold dual-source layouts: Songs+Suggestions, Song+history, Shop+suggestions, Compete boards/rivals, unfolded portrait). Android → and-shell-search (rail centering, hamburger, tablet search button, M3 floating toolbar slot, Quick Links menu/bottom sheet, drawer Item Shop hide, FRE text), and-songs2 (Paths sheet bottom selectors, shop pill pulse), and-profile2 (remove "This Is Me"), new and-boards2 (header outside card, bottom-anchored pager, filters in top bar). Windows → new win-chrome (badge clipping, scrim sliver, chrome inherits background, header outside card, FRE text, This Is Me, stars). Decision: Android nav rail stays on the leading edge (M3) |
| 2026-09-28 | Android | and-bands landed; entry points routed to and-songs2 / and-profile2 |
| 2026-09-28 | Lane PS | Settings gaps landed (`7051bb0`…`e513a31`): web section order, First Run Guides, Service Info (`/api/service-info` + `/api/version`, both verified pure reads), native What's New (web changelog, hash-gated, replayable), navigation-style CHOpt Default View picker, subtitle spacing, shared white-text tokens, `StarRating` in first-run demos. Open: curated native changelog vs web-verbatim |
| 2026-09-28 | Android | and-boards2: Rankings pickers float in the phone toolbar, pager anchored above it (`a4d5cee`); worktree `reset --soft origin/master` hazard documented |
| 2026-09-28 | Apple (AP) | `StarRating` + Stars.xcassets landed for other lanes; This Is Me removed; white-text rule (`FestivalText`) applied to AP-owned features |
| 2026-09-28 | Orchestrator | Apple follow-up queue: Suggestions per-category metadata (web varies by category), Profile Avg Stars + 4/3/2-star tiles, curated native changelog (drop web-only items), Songs/drawer/background gaps after A2 |
| 2026-09-28 | Android | and-shell-search landed (Android UI coverage 93.2% app-wide) |
| 2026-09-28 | Orchestrator | Operator: the Licenses page must not list or mention the star images (entry reverted). No lane should add bundled-art entries to Licenses without operator approval |
| 2026-09-28 | Windows | win-chrome landed (`c6c5ff4`…`cb81dd1`): bell badge unclipped, full-window scrim (no bright sliver), Mica removed — title bar + docked pane transparent over the art, overlay pane in-app acrylic with solid fallback, Leaderboards headers above cards, first-run pips only, "This Is Me" removed, web star images, white secondary text (`FSTDeemphasisTextBrush` timestamps only); 913 tests, 0 Axe errors on touched pages. Open: 100/200% DPI badge check, gold avg-stars |
| 2026-09-28 | Orchestrator | Operator bug batch 2 triaged. Cross-platform rules: instrument headers outside cards (Leaderboards: icon + name only, bands name-only), "View all" below top ten/eleven as purple button, no "Item Shop: …" chip, filter sheets apply live (no Cancel/Apply), content fades in as it loads (`festivalFadeIn`), drawer = Songs/Leaderboards/Item Shop with Settings at bottom (no Bands/Licenses). iPhone chrome: header has global Search + profile avatar as separate buttons; page controls float as separate glass buttons (→ A2). New lanes: AP2 (Mac: fade-in modifier, native profile search sheet, combined bar+line Rank History with paging, Suggestions cards, What's New sheet, star tiles), and-polish (end-aligned floating toolbar, no empty "Select a song" pane, equal-width search scopes, fade-in, Suggestions), win-polish (Windows equivalents) |
| 2026-09-28 | Orchestrator | Duo bugs: Songs dead space between scrubber and rail → W4; search sheet loses title/Close on focus → A2 (global) + AP2 (profile sheet). Decision: modal Close stays in the sheet's own toolbar (HIG), not the Duo rail |
| 2026-09-28 | Orchestrator | Operator batch 3 triaged. A2: integrate `cd8db04` now, then Songs section headers (match web; no content under sticky headers), #–Z rail centred, scroller collapses nav bar, bottom inset for floating buttons (right-aligned, clear of rail), bigger inline title, top scroll-edge scrim, bell hidden without selection, large-detent sheets, Sort sheet (white titles, "Sort By", inline ↑/↓), search sheet hint/grabber/no extra X. PD: no "View full" + "No scores recorded yet" when empty, real Item Shop pulse, bottom bounce. New lane AM (background crossfade to song art instead of grow, transition stutter, song→leaderboard→back jitter, bounce audit, marquee everywhere). Android/Windows: bell hidden without selection, marquee audit, empty-instrument subtitle "No scores recorded yet" |
| 2026-09-28 | Orchestrator | Operator: check every reported bug for cross-platform repro from now on. Batch 4 (Songs): Year sections = decades + no Year scrubber, Duration buckets Under 1 Minute…Over 10 Minutes (operator deviation, recorded in songs/spec.md). Repro: Apple (year sections + scrubber), Windows (single-year groups + jump), Android (decades already; scrubber/duration buckets) → A2, and-songs2, win-polish. Cross-platform re-audit of batches 1–3 running |
| 2026-09-28 | Orchestrator | Cross-platform audit of operator batches 1–3 (36 items): Apple repros mostly because A2/PB/PD work isn't integrated (told to integrate now); Android repros → and-polish/songs2/boards2/profile2; Windows repros → win-polish + new FST-win-pwa. Decisions (all platforms): anonymous player routes hidden + redirect to Songs (web parity); `/bands` with no id → "Band not found"; default Rank By = Total Score; empty instrument = "No scores recorded yet"; score then gold accuracy badge for FC. PWA-Windows/Android lab landed (`9841516`…`cd70934`; gap tables in `.agents/testing/pwa-reference/{windows,android}-gaps.md`). Apple Service Info spinner fixed (`179ab8d`) |
| 2026-09-28 | Android | and-profile2 landed |
| 2026-09-28 | Lane AP2 | Apple polish 2 landed (`ff7fe7b`…`a39ded5`): `festivalFadeIn` with web timing on 7 pages, native profile search sheet (title/Close stay while focused), no Public Profile, combined bar+line Rank History with swipe/buttons, headers above cards, Suggestions per-category metadata + live filter, full-height What's New with opaque Dismiss bar, Gold/5–1-star + Avg Stars tiles; 433 Core + 364 UI tests. Open: Settings opens What's New as a plain sheet; recycled Suggestions cards may re-fade |
| 2026-09-28 | Windows | win-a11y landed (`8f4cbca`…`21c5b0a`): Axe 0 errors on all 29 surfaces × 3 sizes (+AOT), 45/45 keyboard journeys, 4 contrast themes + 150/225% text + animations/transparency off verified; fixes: ItemsRepeater keyboard reach, section accelerators, Narrator announcements/landmarks, HC crash on launch, /statistics deep link, AOT Suggestions crash. Open: contrast-theme status colours, operator Narrator walkthrough (script in `.agents/testing/windows.md`) |
| 2026-09-28 | Orchestrator | API session limit stopped all Mac lanes (A2, PB, PD, W4, AM) mid-work; resumed after reset with "integrate first" |
| 2026-09-28 | Lane W4 | Duo phase 1 landed (`bbb2f8d`, `8bbf7a0`, `e133c36`): `DualSourceLayout` (split at fold half-open, 58/42 flat, inner portrait only) + `HorizontalCarousel`; Compete (boards/rivals), Rivals (list/rivalry), Profile+Statistics (overview/graphs), Suggestions (categories/shop picks); scrubber double inset fixed; empty "Select a Song" pane removed. Songs/Song Detail/Shop/Leaderboards secondaries built, wiring waits on A2/PD/PB. Evidence via `FST_DEBUG_DUO_POSE` (Device Hub poses need the Accessibility grant). Open: Leaderboards rail clearance double inset, unfolded scrubber shot |
| 2026-09-28 | Lane PB | Leaderboards gaps landed (`2363aa0`, `880e48e`, `ecb0293`, `09ec8e3`): headers above rows (icon + name; bands name-only), one-line glass rows with accent score, purple "View all rankings (N)" below top ten/spotlight, fade-in; Full/Band Rankings floating glass pager + instrument pill, "N ranked players" subtitle; Duo rail double inset fixed; 48-page pager journey (`--large-rankings`). Debug `fullRankings` route default → Total Score (orchestrator). Open: `accentBlueBright` (#4C7DFF) token |
| 2026-09-28 | Orchestrator | Operator: **shelve Duo portrait dual-source layouts** — inner display in portrait (half-open or flat) uses the normal portrait layout; restore separate Leaderboards/Rivals tabs; gate `DualSourceLayout` off (kept for later). Songs/Song Detail/Shop/Leaderboards secondaries will not be wired. → W4 |
| 2026-09-28 | Orchestrator | Operator: let running Windows-host lanes finish (and-songs2, and-boards2, and-polish, win-polish, win-pwa), then **no new work on `sfenton-primary`** until the operator frees it. Android/Windows follow-ups are queued, not launched |
| 2026-09-28 | Android | and-songs2 landed (`8e796ee`…`3f847d02`): Songs Quick Links, profile/chart sort modes, invalid-score fallback + warnings, CHOpt threshold filter, shop pulse (row outline, badge, Detail pill), live Sort/Filter, compact Paths sheet, Song Detail web order/header/row eleven/instrument switcher, decade Year + minute Duration buckets; driven on phone, book half, passport, tri-fold, resizable; 557 tests, logic 97.9%, UI 94.0%. Session closed (Windows host freeze) |
| 2026-09-28 | Orchestrator | Operator batch 5 (iPhone): sort → scroll to top (A2 Songs, PD history/boards); sticky Songs section titles with no rows visible beneath (A2); new Lane AP3 — profile push animation problems, web-clickable per-instrument stat links, 2-column adaptive stat grids with in-card chevrons. **Queued for Android/Windows (host frozen):** sort resets scroll to top on every sortable list; sticky section headers without show-through (Windows ListView sticky headers currently show-through risk); profile per-instrument stats clickable like web (Android has tap-to-filter tiles — verify coverage; Windows unverified); 2-column stat grid + chevrons on phone/compact; check profile push animation |
| 2026-09-28 | Android | and-boards2 closed (`a4d5cee`…`9f78e731`): Bands header → Band Rankings, white FestivalLoading; session closed |
| 2026-09-28 | Windows | win-polish closed (`83fa3d05`…`61d2d0cc`): Song Detail (no chip, breathing Item Shop button, headers above cards, row 11, purple View all, pinned header, icon intensity, gold FC badge), Leaderboards (name-only headers, counts, Total Score default, icon heights), fade-in everywhere, live filters, web drawer, bell gating, combined Rank History, gold avg stars, marquee, decade/minute sections; 1010 tests, logic 99.42% / UX 98.33%. Open: Leaderboards wide-preset Axe clipping, band rank history still a list |
| 2026-09-28 | Orchestrator | Operator: pictures sent to the operator use **live service data**, selected player **SFentonX** (`195e93ef108143b2975ee46662d4d0e1`); rule in `.agents/testing/strategy.md`; repo screenshots stay fixture-only |
| 2026-09-28 | Orchestrator | Android/Windows backlog kept in [`.agents/workflow/android-windows-backlog.md`](.agents/workflow/android-windows-backlog.md) while the Windows host is reserved |
| 2026-09-28 | Android | and-polish closed (`76f6f8e`…`f2dfc6d`): right-aligned floating toolbar (page actions only), search in the top bar at every size, web-sidebar drawer, bell gating, ⋮ overflow on narrow panes, profile-only route redirect, `/bands` "Band not found", full-width list until selection, equal search segments, Suggestions web cards + live filter, fade-ins, splash, CHOpt drag handles, white spinners; logic 97.9% / UI 94.0%; live SFentonX captures |
| 2026-09-28 | Orchestrator | Operator: two **populated** columns when width allows (Android foldables, Duo, Windows, iPad) — Apple → W4, Android/Windows → backlog; Android tablet drawer (no title, aligned first item, transparent) and top-aligned foldable rail icons → Android backlog. Master red: two Songs hosted tests after A2's `503bcc0` → A2 |
| 2026-09-28 | Windows | win-pwa closed (`74989e34`…`22a2a3d6`): profile-only route redirect, `/bands` "Band not found", window title, 42 live first-run demos, What's New (web hash verified), Songs shop pulse + Has FC + Filter hidden anonymously, Shop art grid, Settings web order + radio CHOpt + spacing, compact Paths + Karaoke notice, white spinners; 1068 tests, logic 99.42% / UX 98.31%. **All Windows-host lanes closed; leftover emulator/mock servers stopped; host released to the operator** |
| 2026-09-28 | Lane AM | Motion landed (`920c52f`, `a7cfe03`, `cbcc644`, `24c1d64`): background crossfades to song art (web 300 ms ease; grow effect + per-frame blur removed), marquee fixed (measured wrong width, now sizes like Text, cheap loop, still under Reduce Motion/UI tests) and applied to ~12 more one-line names; transition drops identical with background on/frozen/off (simulator effect), jitter already fixed by PD (`c309c39`), no shared bounce left. Orchestrator: `CADisableMinimumFrameDurationOnPhone` (120 Hz) + Suggestions fixed footer slot. Open: real-device transition timing; Compete first load 650–770 ms in Debug |
| 2026-09-28 | Lane AP3 | Profile landed (`6532edd`…`56945fe`): clean push (Select button from first frame, stable tile keys, fixed-size loading placeholders, chart opens at final width, lazy chart build, sheet closes before push), web-clickable stats (Songs filtered, Song Detail, Full Rankings; select-first), 2-column adaptive grid with chevrons; 452 unit + 3 journey classes pass; live SFentonX media. Open (Songs owner): stars/percentile filters, Score/Stars/Percentile sorts, Song Detail instrument param; shared: Quick Links dock flicker during push, global search sheet pushes while closing |
| 2026-09-28 | Lane A2 | Nav chrome landed (through `4e49ae7`): header Search + avatar on every page, right-aligned floating glass page tools, bell gated, full-height live-apply Sort/Filter ("Sort By", purple ↑/↓), web drawer with current-page highlight, pinned opaque-backed Songs section titles, centred stable rail, sort→top, decade/minute buckets, fade-in rows, anonymous meter removed, anonymous route redirect; master hosted tests green again. Open → Lane A3: Songs journeys triage (3/21 baseline), rail test via `--large-catalogue`, Quick Links double-render + search sheet push glitches, result-count announcement, 375 pt title check |
| 2026-09-28 | Lane PD | Song Detail/Shop landed (`5d35456`…`2f780a3`): pinned nav title + art on scroll, cards with headers above (icon, name, entries / "No scores recorded yet"), row 11, purple View full, gold slanted FC badge, no Item Shop chip, pulsing toolbar bag, compact Shop rows with primed art, web-like Paths sheet, live history sort → top, no bottom bounce, no Back jitter, fade-ins; master full `swift test` green (853 tests). Open: `#EF4444` brand token, `score-accuracy/ios.md` deviation note, band leaderboard cards on Song Detail |
| 2026-09-28 | Orchestrator | Operator play session: Windows NativeAOT Release + Android debug APK from master installed and launched on the Windows host (FST_Book_Fold windowed emulator); no development there |
| 2026-09-28 | Orchestrator | Operator batch 6 + Windows host released back to development. 42-item cross-platform matrix in `.agents/workflow/android-windows-backlog.md` (§ batch 6); lanes: Apple AP4 (Settings/FRE/What's New/Licenses) + AP5 (Profile/Song Detail/Leaderboards/general); Windows win-shell2 + win-detail2; Android and-shell2 + and-songs3 + and-profile3 |
| 2026-09-28 | Orchestrator | Release build of master signed (team 3Q9X8JX23S, automatic signing) and installed on the operator's physical iPhone 18 Pro; recipe in `.agents/platforms/apple/build-and-run.md` |
| 2026-09-28 | Orchestrator | Operator batch 7 (iOS, ~37 items) → A3 (Songs/Search/Shell/Shop/Notifications/sheets), AP4 (FRE deep port, Service Info, Settings Quick Links, Licenses), AP5 (song/instrument leaderboards, pager, profile cards, chart paging, Compete, Rivals freeze, FC badge, pills); cross-platform rows 7.1–7.23 in the backlog for Android/Windows lanes. Capitalization rule: Title Case for all UI labels on all platforms (`.agents/design/README.md`) |
| 2026-09-28 | Windows | win-detail2 closed (`f280c74e`…`839b61d9`): batch 6 done 6.11–6.13, 6.15–6.18, 6.26, 6.27, 6.31, 6.35–6.39, 6.41, 6.42 (no-repro 6.22, 6.25, 6.40); batch 7 done 7.1, 7.3, 7.5, 7.8–7.11, 7.13, 7.15, 7.16, 7.22 (no-repro 7.6); Winterfest Wish live check: 10,009 entries → 7 at +1.0% leeway; 1180 tests, logic 99.39% / UX 98.24%. Open: 7.12 (shell), Full Rankings link page, Score/Stars sorts in Songs links, Paths column drag, mock `/leaderboard/{song}/all` |
| 2026-09-28 | Orchestrator | Operator: recover right-side list space (scroll indicators stay; rail inset only when the rail shows) → A3 (iOS); backlog row 7.24 for Android/Windows |
| 2026-09-29 | Android | and-shell2, and-songs3, and-profile3 closed. Batch 6 essentially complete on Android (shared `FestivalLoadGate`/`FestivalEmptyState`/`festivalSheetTop`, What's New, two populated columns, tablet drawer/top-aligned rail, InstrumentSelector, score history on the song page, web Songs filter, Paths notes/overdrive, web pager, split profile cards, percentile/star links, ChartScale axes); batch 7 rows done in scope. Winterfest Wish Lead live: 12,438 → 7 valid. Coverage logic ~98% / UI ~93–94%. Open: hinge-spanning Intensity/History cards, Song Detail band previews + `?instrument=`, band identity features, device.py launch-after-install drops extras, TalkBack pass |
| 2026-09-29 | Windows | win-shell2 closed (`38bf929b`…`65525206`): batch 6 6.1–6.10, 6.14, 6.21, 6.30, 6.34, 6.41, 6.42; batch 7 7.3, 7.9, 7.10, 7.16, 7.18–7.21, 7.24; sticky headers, two-column Songs/Full Rankings ≥1100 epx, band rank chart, player sorts, What's New launch fix, art-retry fix; 1198 tests, Axe 0. Open: web-parity Songs filter (6.32/7.17), two-column Rivals/Band Rankings, Paths journeys broken by removed IDs, stale `fst.song-detail.shop-badge` |
| 2026-09-29 | Orchestrator | Launched FST-win-next (web-parity Songs filter, two-column Rivals/Band Rankings, Paths journey + stale IDs, accessibility pass) and FST-and-next (device.py launch-extras fix + record step, hinge-aware cards, Song Detail band previews/`?instrument=`, TalkBack/ATF accessibility phase) |
| 2026-09-29 | Windows | win-next closed (`ad9cad99`…`bc38a654`): web-parity Songs filter (FilterModal order, Instrument Selector + per-level toggles, v2 settings migration), two columns for Band Rankings/Band Detail and All Rivals/Rival Detail, Paths journeys + stale ID fixed, web background presets, a11y pass 2 (31 pages × 3 sizes, 96 mode runs, 0 Axe errors, 30/30 keyboard); 1215 tests. Open: operator Narrator run, 7.4/7.7 web pager/leaderboard unification, Over CHOpt filter |
| 2026-09-29 | Android | and-next closed (`ed955edd`…`e4b81c1c`): device.py cold-start fix + record/logcat/shell steps + `talkback_walk.py`; hinge-aware Intensity/History; Song Detail band previews (last), Quick Links, `?instrument=` focus, Over CHOpt tile; Quick Links on Band/Compete/Rivals; passport/tri-fold/resizable captures; **accessibility phase**: 16 ATF journeys 0 errors (phone + book half), 13 real TalkBack walks, fixes (48 dp rows, AA buttons, reading groups); logic 97.9%, UI 94.7%. Open: TalkBack on passport/tri-fold/tablet + sheets, rail profile read twice, band-identity features |
| 2026-09-29 | Orchestrator | Rivals fixtures anonymized (real gamertags/account IDs → synthetic; Apple 888 + Windows 1215 tests green; `cad92f3a`); Android LoadGate/EmptyState test IDs registered; song band leaderboard reads (`?accountId=`) recorded as pure reads |
| 2026-09-29 | Orchestrator | Launched FST-win-unify (7.4/7.7 one leaderboard design + web pager, Over CHOpt filter, HC colours, a11y rerun) and FST-and-a11y2 (TalkBack on passport/tri-fold/tablet + all sheets, 7.4/7.7 check, 200% text, performance pass) |
| 2026-09-29 | Lane AP5 | Profile/Song Detail/Leaderboards batch 6+7 landed (`85bc94af`…`8db34bd7`): separate stat cards in web order + Percentiles table, percentile/star links, shared `InstrumentSelector` (all web modes; Score History, Paths, Suggestions), Suggestions respect instruments, no "Your score" text, history on the song page (old deep links scroll to it), Paths notes/overdrive, one purple button, bold selected rows, load gate on Profile/Song Detail/Leaderboards, one row design + web pager, truncating names, stable chart paging, chevrons. No-repro 6.8, 6.25. Deferred: rival detail during freeze (needs short in-memory rivals cache like web ~10 min), load gate on Compete/Rivals, Solo audit contrast issue, offscreen-score journey fixture port |
| 2026-09-30 | Orchestrator | Release machine: `tools/release/` (ASC client, iPhone-only archive/upload), `apple-ci` + `ios-release-build` on fst-apple JIT runners, disabled platform scaffolds; first autonomous issue (tracker #3 → PR #1) merged |
| 2026-09-30 | Orchestrator | App Store screenshots: `tools/appstore_showcase.py` (Epic-Games-only public catalogue cached outside the repo, synthetic StageDiver + fictional rivals) and `shoot` → Songs/Suggestions/Statistics/Compete/Rivals at 1320×2868 on the new `promax` sim alias with `ios_sim.py shot --clean-status-bar` |
| 2026-09-30 | Orchestrator | Release machine is Actions-only: store calls in `store-release.yml`; `apple-ci`, `ios-release-build`, `macos-release` moved off fst-apple JIT runners to hosted `xcode-27`; signing/store credentials only in the master-only `store-release` environment (`tools/release/store_secrets.py`); Windows Store MSIX build + Manual-publish submission client |
| 2026-10-01 | Apple | Issue #27: first-run demos now rotate to new data like the web (5 s ticks, 400 ms fade out → swap → fade in, per-demo rise; bar select 2.5 s/300 ms); only the visible slide in an active scene ticks; Reduce Motion keeps rotation as one cross-fade. Core `FirstRunDemoRotation` + `FirstRunDemoRotationUITests`; details in `.agents/controls/first-run/ios.md` |
| 2026-10-01 | Apple | Issue #31: Song Score History fades the chart and best-score rows out and back in on instrument switch (0.15 s / 0.25 s; instant under Reduce Motion) while the card keeps its size (measured width passed in, pager slot reserved, height pinned during the swap). Core `ScoreHistorySwap` + `SongScoreHistoryModel.reservesPager`; mock `fixture-history-multi`; journeys on port 18831; details in `.agents/pages/player-history/ios.md` |
| 2026-10-01 | Apple | Issue #18: Item Shop list rows (iPhone, and iPad/macOS list mode) now render the shared Songs `SongRowView` (glass card surface, marquee title/artist line) with a `SongRowShopOffer` decoration (New/Leaving badge, bag slot, chevron, red/gold pulse); `ShopRowPolicy` + `Song(shopOffer:)` for unmatched offers; grid cards unchanged. Details in `.agents/pages/shop/ios.md` |
| 2026-10-01 | Apple | Issue #15: forgiving tap areas. Dock Quick Links (a `Menu`) only answered taps on its glyph and the selected-profile monogram (custom bar view) on its 36 pt capsule; `FloatingPageToolLabelStyle` puts the 50 pt square hit shape inside every dock label and the monogram renders as a cached image bar button (round, ±20 pt hits like Search/bell). `NavButtonHitRegionTests` + `NavButtonHitRegionJourneyTests`; rule 13 in `.agents/design/apple/nav-accessories.md` |
| 2026-10-01 | Apple | Issue #37: shared leaderboard row columns. Core `LeaderboardRowColumns` fits each section (season/difficulty ≥ 520, stars ≥ 768, widest rank/score/rating label incl. pinned/spotlight rows); `LeaderboardColumnSlot` + `.leaderboardSectionColumns` size rows on Song Detail cards, Solo chart + footer, Leaderboards cards, Full/Band Rankings and Compete. `LeaderboardRowColumnsTests` + `LeaderboardRowColumnsHostedTests`; [.agents/controls/leaderboard-row-columns](.agents/controls/leaderboard-row-columns/spec.md) |
| 2026-10-01 | Apple | Issue #38: Compete leaderboard cards show songs played/total only when the longest name fits beside them (hidden template row measured at ideal width vs the card width, decided per card so columns stay aligned); otherwise every row hides them and VoiceOver reads them as the row value. Shared songs width in `LeaderboardRowColumns`. `LeaderboardRowColumnsTests` + `RankingSongsFitHostedTests`; [.agents/controls/leaderboard-row-columns/ios.md](.agents/controls/leaderboard-row-columns/ios.md) |
| 2026-10-02 | Orchestrator | Operator rescope: Opus owns **macOS → iPadOS → iPhone Duo**; iPhone/Android/Windows are Copilot sessions on the mesh (issues/PRs). Installed the `apple-hig` skill (`justinwetch/HIGAgentSkills@77f32a4`) to `~/.claude/skills/apple-hig` and `/duo` to `~/.claude/commands/duo.md`; AGENTS.md now requires it for Apple UI decisions and `/duo` for Duo. This Mac no longer has SSH access to `sfenton-primary` (operator removed it); my last Windows-host sessions (FST-win-unify, FST-and-a11y2) are no longer managed from here. Unintegrated iPhone Songs WIP from Lane A3 pushed as `origin/lane/apple-songs3` (not merged; iPhone is Copilot-owned) |
| 2026-10-02 | Orchestrator | Launched Lane MAC (macOS shell: sidebar, toolbar, Settings scene, Commands, window sizing; every page at Mac widths; `tools/mac_app.py` window-only shots) and Lane IPAD (regular-width sidebar shell, keyboard/pointer, two populated columns, adaptive grids, Split View/Stage Manager reflow). Both must route design decisions through `apple-hig` |
| 2026-10-02 | Lane MAC | macOS parity shell landed: own Mac shell (`FestivalUI/Mac/**`) with the web sidebar + player footer, one shell-owned Search/bell/profile toolbar group, Settings window (⌘,), Go/Profile/View/Help menus (⌘1…, ⌘[, ⌘R, ⌘K/⌘F, ⇧⌘P), two populated list/detail columns (Songs, Full Rankings, Rivals; topmost auto-select, one Back), per-column width class (two card columns from 720 pt), 1400 pt page cap, Sort popover / Filter sheet, row context menus, restoration off + frame autosave. `tools/mac_app.py` (build/launch/resize/command/shot/quit, window-only captures). HIG decisions in `.agents/design/apple/macos.md`. Open: Settings panes, draggable divider, hover/focus polish on glass rows, Mac VoiceOver/FKA (Automation Mode needs operator auth) |
| 2026-10-02 | Lane MAC | macOS shell landed (`6037de3b`…`ed13fb29`): web-order sidebar with player footer, Settings window (⌘,), shell toolbar group + page tools, Go/View/Profile/Help menus (⌘1…, ⌘[, ⌘K, ⌘R), 1280×820 default / 760×540 min with no reopen prompt, Sort popover + Mac-sized sheets, context menus, two populated columns (Songs, Full Rankings, Rivals), two card columns ≥720 pt, 1400 pt page cap; `tools/mac_app.py` (launch/resize/command/window-only shot/quit); 27 live SFentonX shots. Open: Settings panes, draggable column divider, glass-row hover/focus polish, uncaptured shared pages, VoiceOver/Full Keyboard Access (needs operator Automation Mode auth) |

| 2026-10-02 | Lane MAC2 | macOS polish landed (`fcc57f75`, `5e850461`, `aa6c3aa2`, `5c573fdb`, + capture-pass fixes): Settings window of six panes (General/Songs/Paths/Guides/Service/About, last pane restored, pop-up choices); draggable list/detail divider (340–680 pt, remembered, slider for assistive tech); row hover tint + focus ring + Return on whole-row buttons; Songs rows on one line when they fit (web desktop row); Edit › Copy (selected song/player), File › Close ⌘W, View › Enter Full Screen ⌃⌘F, Song menu (Paths, Item Shop), Profile › Find Rival; Bands rows and Player Bands pager fixed; split container a11y identifiers no longer hide row IDs. `mac_app.py command settings:<pane>`, `song:<…>`, `menus`. Open: list arrow-key navigation, Quick Links/Rank By menu commands, Rivalry/Band Detail captures, FKA/VoiceOver verification (operator auth) |
| 2026-10-02 | Orchestrator | Lane MAC2 landed (`fcc57f75`…`881b031e`): six-pane Settings window, draggable remembered column divider, hover/focus/Return on rows, one-line Songs rows in single-column widths, File/Edit Copy/View Full Screen/Song menus, Player Bands pager fix (all platforms), split a11y-ID fix (iPad counterpart → IPAD). Stopped tracking `default.profraw` (`0055fd66`). Launched Lane MAC3 (arrow-key list navigation, Quick Links/Rank By menus, Rivalry/Band Detail captures, idle CPU + occlusion pause, Release sanity) and Lane DUO (apple-hig `/duo` workflow stages 0–3 on the main journey; stops at Decide for operator choices; HIG-compliance fixes allowed) |
| 2026-10-02 | Lane DUO | `/duo` stages 0–3 on Songs → Song Detail → Song Leaderboard + shell (`281e3756` Item Shop restored to the Duo rail/overflow, `ea711a84` duo-notes). Operator decisions: **D1 two columns (list + detail) on the inner display in portrait, half-open or flat (HIG; supersedes the earlier one-column portrait note)**; D2–D9 accepted as recommended. Lane continues with Build/Verify. Device Hub poses still need the Claude app's Accessibility grant (restart) |
| 2026-10-02 | Lane MAC3 | macOS keys/menus/perf landed (`09e5a572`, `bd922427`, `98da3853`, `3ca5c720`, `f0014a13`): arrow keys in Songs, Full/Band Rankings, Rivals, Leaderboards and Item Shop (one focus stop; ↑/↓, grid ←/→, Home/End, Return, Escape; split detail follows; rows from page data so lazy rows are reachable; accent/gray by focus); Go › Quick Links ▸ + Next/Previous Section ⌥⌘↓/↑, View › Rank By ▸ (checkmarks), View › Scroll to Selection ⌘J, top-page-only publishing; carousel/pulses/marquees pause on window occlusion (Songs 53–61% → 0% CPU covered); pushed Mac pages now get their column layout (were zero-width compact); Band Detail two columns; first-run copy says click/sidebar; Release build ad-hoc 61 MB universal, window in 1.3–1.7 s. `mac_app.py command key:…`, `minimize`/`restore`. Open: Rivalry populated capture (service `post-process` freeze 503), focused-state/menu-enabled checks in a key window (operator), shared Shop pulse clock |
| 2026-10-02 | Lane MAC3 | Mac finish landed (`09e5a572`…`f0014a13`): arrow-key/Home/End/Return/Esc navigation in all lists and the Shop grid with the detail following; Go › Quick Links (⌥⌘↓/↑) and View › Rank By / Scroll to Selection (⌘J) menus; pushed pages no longer zero-width (player/band pages full width); background/pulses/marquee pause when occluded (0% CPU covered vs 45–55%); Release ad-hoc universal build, window in 1.3–1.7 s. Open: Debug idle CPU 53–61% on Songs and 51 main-thread stalls ≥100 ms on scroll stress (perf follow-up; shared code), per-row Shop pulse timers, populated Rivalry capture, operator key-window menu check |
| 2026-10-02 | Lane DUO | Journey 1 built (`6006de6d`, `56b80405`, `1690be28`, `ed96148a`): split when both size classes regular (inner portrait flat/half), regular tab set, fold/unfold restores the open song, rail priorities (Search with Bell/Profile; Item Shop/Paths before Quick Links; Next high); 656 Swift tests green; folded verified live, inner portrait via hosted renders only (needs Device Hub poses). Journey 2 decisions J1 (split instrument/Rank By toolbar items; instrument as titled item or in-content pill), J2 (drop songs-played column when narrow), J3 (Duo split-column width class via `DeviceLayout.column(width:)`) — recommended; open: Songs/song-leaderboard row a11y frames under the rail |

| 2026-10-02 | Lane IPAD | iPadOS parity landed (`6741a5bd`, `203e6148`, `a313078e`): **FestivalTablet** app target (`com.sfenton.festivalscoretracker.ipad`, every orientation, multitasking; iPhone app untouched) + `FestivalTabletUITests`, `ios_sim.py --device ipad` selects it. Regular width = native selectable sidebar with the web sidebar rows (Item Shop as `FestivalSection.shop`) and footer (player + Deselect or Select Profile, Settings); compact (⅓ / Slide Over / narrow window) = iPhone tabs + drawer by size class. Songs, Full Rankings and Rivals = one three-column split (sidebar \| list \| detail) from a 1000 pt window, top row auto-selected, unchosen detail dropped when it collapses; per-column `DeviceLayout` (two card columns only ≥ 600 pt); ⌘F/⌘K/⌘1–9/⌘[/⌘R; pointer highlight. HIG citations in `.agents/design/apple/ipados.md`. 10 iPad journeys (sidebar, Item Shop, footer, two populated columns, rotation reflow, chosen detail survives, Full Rankings split, narrow window → tabs, ⌘ digits), hosted sidebar renders, driver `resize:`/`fill`/`systemTree:`/`systemTap:`/`systemHold:`. Live SFentonX shots `~/FestivalShowcase/native-ipad/`. Open: exact ½ tiling (iPadOS snaps drag-resizes), multiple windows, menu-bar `commands`, Full Keyboard Access audit |
| 2026-10-02 | Lane IPAD | iPad shell landed (`6741a5bd`, `203e6148`, `a313078e`): separate **FestivalTablet** target (`com.sfenton.festivalscoretracker.ipad`) because the App Store iPhone app is iPhone-only/portrait-locked; regular-width web sidebar with player/Settings footer, compact → iPhone tabs; three-column sidebar|list|detail (Songs, Full Rankings, Rivals) from 1000 pt with auto-select; ⌘F/⌘K/⌘1–9/⌘[/⌘R + pointer; 10 iPad journeys green. Open: exact ½/⅓ Split View not scripted, auto-selected detail stays pushed through compact, multiple windows, iPad menu-bar commands, FKA audit. **Pending operator call: separate iPad app vs one universal app** |
| 2026-10-02 | Orchestrator | Operator: **one universal iOS app** (merge FestivalTablet into the iPhone bundle, device family 1,2; iPhone portrait-only, iPad all orientations). Restarting the Claude app now for the Accessibility grant. **Next after restart:** (1) verify Device Hub poses work (Duo inner display), (2) universal-app merge lane, (3) Duo J1–J3 + live inner-portrait verification, (4) Mac/iPad performance pass (Songs idle CPU, scroll stalls, shared Shop pulse clock), (5) iPad leftovers (exact Split View, menu-bar commands, FKA) |
| 2026-10-02 | Orchestrator | After restart: Device Hub pose scripting still lacks Accessibility — the grant must be on the embedded Claude Code helper (`~/Library/Application Support/Claude/claude-code/<version>/<hash>/claude.app`), not Claude.app (operator action; path changes with Claude Code updates). Launched Lane UNI (merge FestivalTablet into universal FestivalMobile), Lane PERF (Mac/iPad CPU + scroll stalls, shared pulse clock, `tools/apple_perf.py`), Lane DUO2 (J1–J3 + rail a11y frames, then journey 3 Stages 1–3) |
| 2026-10-02 | Lane UNI | Universal iOS app landed (`9783fd0c`, `1f3c51f4`): FestivalMobile device family 1,2 (iPhone portrait-only; iPad all orientations, no full-screen requirement); FestivalTablet removed; iPad UI tests → `FestivalMobileIPadUITests` / `FestivalMobileIPad` scheme; `ios_sim.py --device ipad` runs the universal app and prints pass/skip/fail counts; `tools/tests/test_universal_app.py` guards the plist settings. iPad 9/9 + Home Screen name 1/1; iPhone 8 pass / 6 skip / 1 pre-existing fail. **For Copilot iPhone sessions:** `testFailureActionRemainsReachableAtLargestTypeAndLandscape` assumes iPhone landscape (needs skip/rewrite); App Store Connect needs iPad screenshots before the next review |
| 2026-10-02 | Lane DUO2 | Journey 2 built (`bd33566c` J3 split-column width class, `eff427fa` J1 separate titled rail items for instrument + Rank By incl. Band Rankings / J2 names win over songs column, `71ee260e` docs); 656 tests green. Operator: accept system-sized rail controls and full-width list row a11y frames as observed exceptions; journey 3 R1 (Find Rival `.high` on Rivals hub), R2 (Rank By in content, 44 pt), R3 (Statistics 2 columns inner portrait for now), R4 (inline Find Rival field) accepted. Lane continues: build journey 3, then Stages 1–3 for Item Shop, Suggestions, Compete, Settings, sheets |

| 2026-10-02 | Lane PERF | Mac/iPad performance landed (`5fd46f1b`, `3a2ee4c1`, `13e28a07`, `5a46ce6e`, `dcb27a8f`): carousel (macOS now too), Shop row/Song Detail pulses (one wall-clock `ShopPulseClock`) and marquee scrolling run on Core Animation; Mac covers pre-dimmed once (`DimmedArtwork`, AppKit composited the black layer ~2× brighter); marquees measure with a stateless `MarqueeFitLayout` (no per-row geometry/preference state), status chips are cached bitmaps, `SongChipRows` skips merged alignment guides, cached ISO-8601 formatters; still states draw in SwiftUI for `ImageRenderer`. Mac Songs idle 57.7% → 0.6% (Debug), 59.9% → 0.6% (Release probe); Leaderboards/Statistics/Shop 18–40% → 0.7%; scroll stress units ≥ 100 ms 62–68 → 13–29 (worst 631 → 293–436 ms). iPad idle 1–4% (already CA), stress unchanged count (~38), worst 714 → ~400 ms. `tools/apple_perf.py` (CPU, stress stalls, Mac xctrace; `--probe` = Release optimization + Debug hooks); numbers in `.agents/platforms/apple/architecture.md` § Performance. iPhone: 656 Swift tests green; Shop/Song Detail journeys show the same 7 failures on master and the lane (pre-existing: Text clipped audit, Settings scroll at largest text, Song Detail score-history asserts, Solo contrast). Open: stress far jumps still ≈ 250–450 ms (row creation inside animated `NSTableView`/`UICollectionView` scroll; real jumps are instant), first-run demo glow is a SwiftUI shadow (Release with the sheet 38.9% → 14.3%), xctrace cannot attach to simulator apps |
| 2026-10-02 | Orchestrator | Lane PERF landed (`5fd46f1b`…`dcb27a8f`): Mac idle CPU Songs 58–60% → 0.6% (endless SwiftUI animations moved to system animations; one shared Shop pulse clock; marquee single-pass layout; cached instrument icon images), first-run sheet 39% → 14%, Mac scroll-stress stalls 62–68 → 13–29 (worst 631 → ~400 ms); iPad unchanged ~38 stalls (Instruments can't attach to sim apps); `tools/apple_perf.py`. Duo journey 3 built (`ebfdc09c` R1/R2, `7475ef3a`); journey 4 decisions S1 (even Shop columns inner), G1 (Suggestions 2-column grid), M1 (What's New drops Dismiss bar only with the vertical bar) accepted → building |
| 2026-10-02 | Lane DUO2 | Journey 4 built (`c6e48bae`): S1 even Shop columns on the inner display (4×~200 pt landscape, 2 portrait), G1 Suggestions two top-aligned card columns at regular width (also wide iPad/Mac), M1 What's New single Close with the vertical bar. Duo all four journeys through `/duo` Stage 5. Remaining: real inner-display captures (Accessibility grant), Split View/PiP/keyboard overflow/Reduce Transparency/RTL/outer rotations, App Resizability check, device check → Lane DUO3 for what doesn't need poses |
| 2026-10-02 | Lane DUO3 | Duo Stage 5 checks without poses (folded, live; `~/FestivalShowcase/native-duo/checks/`): Reduce Transparency + Increase Contrast pass (new `ios_sim.py shot --a11y`); RTL fixed — reading-direction chevrons app-wide, flipped difficulty meter (`ff150d18`); AX5 fixed — rankings row overflowed its folded column under the rail, inline service status hyphenated (`d9758cbf`); software keyboard pass (Songs filter, Search, Find Rival); PiP N/A (own), Split View/inner/rotations pending (Accessibility grant still missing); App Resizability skill is Xcode-chat only, prerequisites pass. Pending decision O1 (Duo outer landscape) in `duo-notes.md` |
| 2026-10-02 | Lane DUO3 | Stage 5 checks without poses (`ff150d18` RTL chevrons/meter mirroring, `d9758cbf` AX5 rankings rows + notice hyphenation, `745c2a5d` `ios_sim.py shot --a11y`, `530ffee6` docs): Reduce Transparency/Increase Contrast pass, software keyboard pass, PiP N/A, App Resizability prerequisites pass (Xcode-chat only). Pending: hardware keyboard, Split View, inner display, rotations (poses). Operator O1: **outer-display landscape allowed on hinged devices only** (runtime mask; iPhone stays portrait) → building |
| 2026-10-03 | Lane DUO3 | O1 built (`db3816cb`): `OrientationPolicy` + app delegate `supportedInterfaceOrientationsFor` — hinged devices (hinge probe or vertical-bar fallback) get all orientations; others use the Info.plist value (iPhone portrait-only, iPad all); guard test `iPhoneDeclarationStaysPortraitOnly`. Verified iPhone stays 402×874 portrait, iPad rotates 1210×834; Duo outer landscape unverifiable without Device Hub rotate (pending Accessibility grant) |
| 2026-10-04 | Issue #92 (Apple) | iPhone/Duo/iPad chrome back to Apple defaults: removed the tab-bar accessory dock (#42/#84/#89) and header Search button; trailing top bar in two glass groups (Sort · Filter · Quick Links \| bell · avatar); global search is a trailing `Tab(role: .search)` (`RootTab`/`RootTabTransition`), compact phone tabs drop Statistics to fit it (drawer pushes it); iPad sidebar Search row; Songs "Filter Songs" pinned `navigationBarDrawer`; Sort+Filter fold < 390 pt / AX text. Folded Duo rail keeps bell + profile (Quick Links overflows). macOS unchanged. Record: [nav-accessories.md](.agents/design/apple/nav-accessories.md) |
| 2026-10-05 | Issue #92 follow-up (Apple, iPhone) | Owner: page tools belong in the tab-bar accessory, not the header. iPhone (iOS 26.1+) now puts the front page's tools then a divider, bell and avatar in the system `tabViewBottomAccessory` (`PageToolsAccessory.swift`: `PageToolsRegistry`, `.festivalPageTool`, `pageToolsScope()`); Songs reads Sort · Filter · Quick Links \| bell · avatar, header keeps drawer/Back/title. Inline/narrow/AX folds Sort+Filter (`PageToolsAccessoryFit`); accessory menus open as a compact sheet (`PageToolMenu`: iOS 26 never opens an inline accessory `Menu`, and expanded it answers only near its glyph); root presents bell/profile sheets (`openNotifications`). Search tab and "Filter Songs" unchanged; Duo/iPad/older iOS keep nav-bar items; macOS unchanged. Record: [nav-accessories.md](.agents/design/apple/nav-accessories.md) |

| 2026-10-03 | Lane IPAD2 | iPad leftovers landed (`171a4d93`, `94aa4aaf` range): **menu bar** `FestivalCommands` (Edit Search ⌘F; View Refresh ⌘R/Sort/Filter/Rank By/sidebar; Go Back ⌘[/⌘1…⌘9/Search ⌘K/Quick Links/⌥⌘↓↑; Song; Profile ⇧⌘P; Help; App Settings…), scene-safe `focusedSceneValue`, top-page-only publishing; iPhone unchanged. **Exact tiles** scripted (`tile:` Left/Right/Arrange thirds; landscape ½ 600 pt, ⅓ 396.5 pt, portrait ½ 412 pt, all compact). **Fixed** auto-selected detail reopening pushed in the compact tab shell when another section was in front (root pops automatic details). **Multiple windows**: decided yes (person-opened only): File › New Window + "Open in New Window" on Songs/ranking rows (`FestivalWindowRoute`), one shared `FestivalSession`. **First-run glow** on Core Animation (iPad sheet 2.6–4.1% → 0.0%). **Scroll stalls**: not iPad-specific: every stall is Songs rows being built (~12–14 ms main-thread CPU/row, same on iPhone sim); Liquid Glass row card ≈27%, invisible link ≈15% of a row; new `Stall.counts`/`cpuMarks`/`main_cpu_s`; counts 34–44 under host load 20–190 (no measurable change). **Keyboard**: shortcuts pass; Tab reaches only Filter Songs; FKA switch exists in sim Settings but did not toggle (no hardware keyboard). Open: row-card glass cost (design call), FKA/sidebar focus on hardware keyboard |
| 2026-10-03 | Lane IPAD2 | iPad leftovers landed (`171a4d93`…`c86221ee`): iPad menu bar (View/Go/Song/Profile/Help, App Settings…, Mac shortcuts, per-window), exact Split View tiling scripted (½ 600 pt / ⅓ 396.5 pt landscape → compact tabs) + compact-transition bug fixed, multiple windows (user-initiated; shared profile/session, per-window navigation), first-run glow → system animation (iPad sheet CPU → 0%); iPad journeys 14/14, Swift 675. Scroll stalls not iPad-specific (12–14 ms main-thread per Songs row build, same on iPhone); glass card ≈27% of row cost — cheaper card needs operator design sign-off. FKA needs a hardware keyboard check |

| 2026-10-03 | Lane CARD | Songs row card: per-row Liquid Glass → `festivalRowCard` (`ultraThinMaterial` + fitted tint + gradient rim as plain modifiers; HIG Materials: no Liquid Glass in the content layer). Tint/rim fitted per platform from same-backdrop A/B captures (Debug `FST_DEBUG_ROW_CARD_AB`); Reduce Transparency/in-app Increase Contrast pixel-identical; system Increase Contrast tint 88% on iOS. Main-thread ms per row: Mac probe 7.9 → 7.3 (stress stalls 19–29 → 11–14), iPad 11.6 → 9.9, iPhone 13.4 → 11.9; iOS stall counts unchanged (~25 rows per animated jump). iOS/iPadOS pairs within 1–3 levels; **Mac over bright covers reads up to ~15 levels darker/frostier than glass (operator eye)**. Evidence `~/FestivalShowcase/native-perf/card/`; numbers in architecture.md § Performance |
| 2026-10-03 | Lane CARD | Cheaper Songs row card landed (`69dd2cde`, `c3f6bb69`): `.ultraThinMaterial` + tint + 1 pt rim (`Design/RowCardSurface.swift`) instead of per-row Liquid Glass (HIG: no glass on content); per-row build −8% Mac / −15% iPad / −11% iPhone; Mac stalls 19–29 → 11–14; iPhone/iPad visually within 1–3 levels, Reduce Transparency pixel-identical. **Operator check pending:** Mac card reads darker/more frosted over bright covers (`mac-detail-zoom-bright.png`) |
| 2026-10-04 | Orchestrator | Operator: keep the new material row card as is on Mac (darker over bright covers accepted) |
| 2026-10-04 | Orchestrator | Operator granted Accessibility to the Claude Code helper; pose scripting now passes the permission check without a restart (needs Device Hub open). Launched Lane DUO4 (auto-open Device Hub in `ios_sim.py`; real inner-display, fold/unfold, O1 outer landscape, Split View, hardware-keyboard verification) alongside Lane A11Y |

| 2026-10-04 | Lane A11Y | iPad/Mac accessibility + far jumps landed (`10fc1c9e`…`a02c9019`): **far list jumps teleport** behind a short fade (`ListJump`; stress stalls iPad 33–37 → 8–9, iPhone 34–39 → 3–4, Mac 76–79 → 23–26, same-binary A/B via `FST_DEBUG_SONGS_SCROLL_STRESS=animated`); **iPad audit journeys** (`IPadAccessibilityAuditTests`: three columns, portrait regular, ⅓ compact, AX1/AX5, Bold Text / Increase Contrast / Reduce Transparency via new `ios_sim.py uitest --a11y`, JSON per run) + structural journey (sidebar → list → detail order, selected traits, headings); **Mac hosted accessibility trees** (`MacAccessibilityTreeTests`, toolbar via `sceneBridgingOptions`). Fixed: fade-ins un-hid decorative images app-wide (`accessibilityHidden(while:)`), selected iPad sidebar text 3.56:1, invisible pinned title in the tree, rivals red text 2.6–3.0:1, 18 pt See All rows, pager frame, marquees truncating at AX sizes (now wrap), AX5 footers/rank lines, Mac Deselect/profile/"Search" toolbar labels. Audit contrast verdicts on iPadOS 26.5 are mostly false (rendered 5–19.5:1) and landscape screenshots are rotated; open: FKA/VoiceOver (Mac needs Automation Mode), AX1 not run. Record: [accessibility.md](.agents/testing/apple/accessibility.md) |
| 2026-10-04 | Lane DUO4 | Real Duo poses verified (`cc17abcf`, `71f3ed33`, `9e5018e7`, `927c302c`): `tools/device_hub_ax.swift` + auto-open Device Hub; inner landscape (flat/book) pass; inner portrait fixed to two columns; fold-from-inner-portrait crash in `UITabBarController` fixed (deferred tab change); D6 scroll restore pass; O1 outer landscape observed both sides; R3 Statistics charts legible at 2 columns. Pending: Split View scripting, hardware keyboard, App Resizability (Xcode chat), device |
| 2026-10-04 | Orchestrator | Operator delegated Duo defaults: the orchestrator takes recommended options on Duo decisions (logged for later review). P1 keep 2 Statistics columns, P2 accept Shop cards scrolling under the fold in book pose, P3 inset Songs in outer landscape (compact height), P4 one-line truncated song-leaderboard rows in the narrow column → Lane DUO5 |
| 2026-10-04 | Lane A11Y | iPad/Mac accessibility pass (`10fc1c9e`…`a9794f0c`): real fixes — selected sidebar row contrast, rivals red text, AX5 truncations, fade-in exposing hidden decorative images (all platforms), unlabelled/duplicate Mac toolbar labels; far jumps: iPad stalls 33–37 → 8–9, iPhone 34–39 → 3–4, Mac 76–79 → 23–26. iPad audit journeys still fail mostly on auditor false positives over translucent surfaces + system controls → Lane A11Y2 (re-audit, scoped documented waivers, AX1/compact/player page) |
| 2026-10-04 | Orchestrator | **Operator split-view redesign:** current always-on splits rejected (not aligned to the Duo fold / screen midpoint; Songs must never split). New rules in `.agents/design/apple/split-view.md`: on-demand split (starts full width, selecting splits 50/50 at the exact midpoint or hinge, close returns full width) only in landscape/wide for Rivals, Leaderboards, Full/Band Rankings, Song Leaderboard, Settings; Songs and other pages never split (Songs two-column rows under headers in landscape); iPad/Duo navigation becomes an overlay flyout like iPhone. DUO5 stopped on split work; A11Y2 deferred layout re-audit. → Lane SPLIT |
| 2026-10-04 | Orchestrator | Operator refinements to the split redesign: Song Leaderboard → player is **direct push navigation** (no split); **Song Detail splits** to the full Song Leaderboard or score history; **Paths is always a modal** |
| 2026-10-04 | Lane DUO5 | Wrapped up (`bdf5d080`…`bf764805`, 692 tests): P3 Songs outer-landscape inset; Paths instrument name no longer breaks folded; iPhone bottom tool bar no longer shows on the open Duo in portrait (shell, flagged to SPLIT); Bands readable width open; What's New centred sheet open; first-run outer-landscape scroll. Delegated Duo defaults logged in `duo-notes.md` (P1, P2, P3, S6–S9). Still needs operator/device: App Resizability (Xcode chat), hardware keyboard, Licenses/Privacy sweep on inner display |

| 2026-10-05 | Lane SPLIT | On-demand split + overlay flyout (`f421705e`…): shared `OnDemandSplitPolicy`/`OnDemandSplitLayout` (50/50 at the content midpoint or Duo hinge, landscape regular only, panes ≥ 360 pt, spring/crossfade, 1 pt divider) used by iOS `OnDemandSplitStack` and Mac `MacListDetailStack`; split pages Rivals, Leaderboards, Full/Band Rankings, Song Detail (board, score history), Settings › Licenses; Songs never splits (2 cards/row landscape iPad/Duo); iPad has no persistent sidebar (flyout with Search row, edge swipe, ⌃⌘S, Escape via menu bar); removed ListDetail*, FestivalSidebar, MacColumnDivider. Measured: iPad hairline 605.0 pt of 1210, Mac 750 pt = sidebar 220 + 530 of 1060. Swift 738 pass. Open: Duo hinge capture and journeys pending simulator time (A11Y2 audits held the lock for hours) — see split-view.md |
| 2026-10-05 | Lane A11Y2 | iPad audits made honest (pre-redesign counts; `6cec85b4`…): **measured, per-issue waivers** (`IPadAuditWaivers`: rendered contrast per recognized word from a full-screen capture, rotated upright so three columns audit contrast in landscape; page-level evidence for the many issues iPadOS 26.5 reports without an element; AX5 comparison launches for Dynamic Type growth and read-back; scoped system entries for the search field, toolbar badge, keyboard candidates). Raw → open: Regular 62/104/228 → 0/0/2, Compact 52/82/94 → 1/1/1, AX1 27/29/71 → 0/0/1, AX5 20/28/36 → 0/0/0. Fixes: stat tiles and suggestion pills cut at AX5, accent-blue ratings/values 3.8–4.2:1 → `AccentText.blue`, Rank History bars ("0 to 1", paged-out bars over the sidebar, hidden axis titles), song title heading, iPad sidebar footer at AX5. Mac trees re-checked (chart and heading checks added). Operator VoiceOver script for iPad and Mac: [voiceover.md](.agents/testing/apple/voiceover.md). Open: Statistics unattributed "inaccessible text" (Swift Charts tick labels suspected), AX5 compact Song row mid-word breaks (shared iPhone row), FKA/VoiceOver (Mac needs Automation Mode); final re-audit on the Lane SPLIT shell (audit journeys that drive the old split/sidebar need updating) |
| 2026-10-05 | Lane A11Y2 | iPad audit pass landed (`6cec85b4`…`b05dc5d9`, pre-redesign counts): open issues down to 0–2 per mode (Statistics chart tick labels, 3 compact items, Rival Detail unreached); landscape contrast auditing fixed; 15 evidence-backed waivers tabled in `accessibility.md` (7 measured false positives, 7 system controls, 1 system alert); fixes: AX5 tiles/pills, accent-blue values ~7:1, Rank History labels/axes, song title heading, sidebar footer scrolls at AX5. Mac tree checks pass. **Operator VoiceOver walkthrough** (20 steps, iPad + Mac) in `.agents/testing/apple/voiceover.md`. Final re-audit after Lane SPLIT |

| 2026-10-05 | Lane SPLIT | Verified + fixes (`…` after `66c1a2db`): iPad flyout shell now the root `TabView` with its bar hidden (a plain view switch lost the first responder); Go › Quick Links ▸ submenu dropped (it froze the iPadOS menu bar on Leaderboards/Song Detail, live A/B); Escape via View › Close; one Open-in-New-Window menu per Songs grid row; flyout footer scrolls at AX sizes (A11Y2 rule). iPad journeys 11/11, iPad split structure audit pass, Swift tests pass. Duo inner landscape: hinge 455–495 pt, hairline 475.0–475.7 pt; inner portrait/folded push; Mac 750 pt = 220 + 530. Shots + `ALIGNMENT.md` in `~/FestivalShowcase/split-redesign/`. Open: Escape not deliverable from XCUITest; Duo coordinate gestures (edge swipe) unverifiable; iPhone SongsChrome reorder journey failed on a persisted descending sort (shared simulator state), SongsJourneyTests runner crashed (infra) |
| 2026-10-05 | Lane SPLIT | Split/flyout redesign landed (`87a9e4b7`…`d5ff2b11`): `OnDemandSplitPolicy`/`OnDemandSplitLayout`/`OnDemandSplitStack` (hinge or exact midpoint, landscape regular, ≥360 pt panes, spring / Reduce Motion crossfade); split pages Rivals, All Rivals, Leaderboards, Full/Band Rankings, Song Detail → board/history, Settings → Licenses; everything else full width (Songs two cards per row in landscape); iPad/Duo overlay flyout (root TabView, bar hidden); Mac fixed divider. Measured: iPad 605/1210 exact, Mac 750 = 220 + 1060/2 exact, Duo hairline 475.0–475.7 on hinge 455–495. 751 Swift tests, iPad 11/11. Deviations: iPad Go › Quick Links submenu removed (froze menu bar). Open: Escape and Duo edge swipe unverified by XCUITest; iPhone Songs reorder journey failed on a leftover saved sort. Next: final iPad a11y re-audit on the new shell |
| 2026-10-05 | Orchestrator | Operator: a split shares **one** background (static or animated per setting), owned by the parent (leading) page — no per-pane background/scrim; Rivals halves currently differ in darkness; Rivals trailing title inset wrong → Lane SPLIT2 (all split pages, iPad/Duo/Mac, luminance + inset measured) |
| 2026-10-05 | Lane SPLIT2 | Split shared background + insets (`7bdbc278`…): the split container draws **one** backdrop behind both panes and the hinge band (pages in a split draw none, clear navigation containers, iOS 18+; trailing pages never register, so the parent decides the art); trailing pane gets the top scrim at the leading page's height. Insets: trailing large title 0 → 20 pt (UIKit reports a zero minimum margin mid-window; bar margins raised to the window edge's), Duo leading content 100 → 16 pt from the hinge (vertical bar safe area ignored at the divider edge). Measured flat-backdrop luminance equal within 0.02 on iPad (5 split pages), Duo, Mac (`~/FestivalShowcase/split-redesign/bg-fix/`). New `FST_DEBUG_FLAT_BACKDROP=1`. Found: tapping a card in the 2-column Songs grid pushes both songs of the row (filed as a task) |
| 2026-10-05 | Lane SPLIT2 | Shared split background landed (`10da4804`, `73810689`, `9e8369df`): one backdrop behind both panes + hinge band, parent page owns the art, equal top darkening (iPad top strip 19.42/38.00 → 19.42/19.41; Duo hinge band black → matches; Mac 46.70/49.42 → 46.15/46.16); trailing title inset 0 → 20 pt; Duo hinge-side gap 100 → 16 pt; 761 tests. Found: Songs landscape grid tap opens both songs in a row. **Urgent:** issue #122 — our `RowCardSurfaceTests` fails on the GitHub macOS runner, blocking other PRs (#121, #128) → Lane FIX (CI fix + grid double-open) |

| 2026-10-05 | Orchestrator | Agentic-architecture audit (all 303 tracker issues) and fixes. Native: pattern registry (`.agents/patterns/`, `contracts/patterns.json`, 10 patterns), `tools/pattern_guard.py` in the `inventory` check, `.agents/skills/<name>/SKILL.md` skills (new fix-reported-issue, consistency-sweep, design-proposal, web-parity-check), `.github/instructions/*.instructions.md`, pattern-first AGENTS.md (#259). Release machine (festival-report-tracker `72eb280`, `5f184d3`): pattern-aware triage, **Needs Decision** with `/choose`, independent design-review gate before native merges (`review.model`), Apple validation lanes, `supersede`/`validation-prune`, fresh product clones. Follow-ups filed: #308 (scroll-edge consolidation), #309 (Android chrome decision; #187/#278 pruned) |
| 2026-10-05 | Lane FIX | #122 fixed and closed (`d20f6784`, `8d2b0e26`; apple-ci green on master run 37346556652): the GitHub macOS runner has Reduce Transparency on, so the card drew its opaque fallback; `RowCardSurfaceTests` now forces Reduce Transparency off for the material check and compares against its own layers and the opaque card. Songs landscape grid double-open fixed (`2b7f4c1f`): a List row fires every link in it, so each grid card is now its own button; iPad journey + Duo inner landscape verified |

| 2026-10-06 | Lane A11Y3 | Final a11y re-audit on the flyout/split shell (`36507e04`…, iPad + Duo + Mac). Raw → open per group (browse/rankings/profile/shell): iPad Landscape 41/54/102/217 → 0/0/0/2, Landscape AX5 shell 25 → 0, Regular 43/116/165/12 → 0, Compact ⅓ 47/86/168/16 → 0/0/1/0, AX1 7/10/48/0 → 0, AX5 4/5/31/0 → 0, Bold 15/44/68/1 → 0, IC 25/79/116/11 → 1/0/0/0, RT 16/44/73/12 → 0; Duo inner landscape 6/9/29/30 → 2/0/2/0 (+AX5 shell 4 → 0), inner portrait 1/17/30/0 → 1/1/3/0, folded 23/30/73/12 → 2/0/1/0. Fixes: VoiceOver focus into the split pane / flyout and back (Duo: back to the rail's More), drawer modal behind the phone drawer, Swift Charts tick labels as axis elements (A11Y2's Statistics item), Score History chart one element, selected-row fill behind text (rivals pills 4.0 → readable), white-label buttons and accent text links on readable fills, Reset red 4.33 → 5.4:1 under IC, Song Detail AX5 main-thread hang (lazy grid → eager rows), AX5 cuts (accuracy pill, Total Score, stat tiles one column + chevron padding). Waivers added: `system-bar-title-size`, `behind-modal-drawer`, `description-outside-tree`. `IPadShellAccessibilityTests` 5/5 iPad; Duo 4/5 split pages. Mac split tree + toolbar checks pass. Open: Song Detail unlabelled full-screen Image node, landscape Settings split 2 unattributed issues, Duo Rank History bar hit area, ⅓ Rival Detail last See All unmeasured, Duo unreachables (coordinate gestures). Record: [accessibility.md](.agents/testing/apple/accessibility.md#results-post-redesign-lane-a11y3-2026-10-05) |
| 2026-10-06 | Lane A11Y3 | Post-redesign a11y re-audit (`36507e04`…`3d5abbf0`; apple-ci green): iPad modes open 0–2 per cell (landscape shell 2, compact profile 1, Increase Contrast browse 1), iPad shell structure 5/5; Duo inner landscape/portrait/folded 1–3 open per cell, Duo split pages 4/5. Fixes: VoiceOver focus into/out of split pane and flyout, page behind drawer hidden, chart a11y elements, selected-row/button/Retry/Reset contrast, AX5 Song Detail scroll freeze + truncations. Waivers +3. Open: unlabelled full-screen image on Song Detail, 2 Settings-split element-detection items, Duo portrait Rank History bar tap target, unmeasured ⅓ See All, Duo items blocked by XCUITest taps not landing on the inner display. VoiceOver script updated |

| 2026-10-06 | Lane A11Y4 | A11Y3 tail closed (`6fa6f7d4`…; apple-ci green): **Song Detail's unlabelled full-screen Image** was the song cover (`scaledToFill`), in the tree despite every hiding modifier → cover drawn in a `Canvas`; pushed pages' refresh boundary no longer un-hides decoration (`.accessibilityHidden(while:)` + source guard test). **Landscape Settings split** issues: `.combine` around the Licenses list-detail link made a selected static text plus an exposed inner button → labelled link (selected button). **Duo Rank History hit area** → one adjustable chart element over the plot, value reads each visible snapshot. **⅓ Rival Detail last View All** reached and measured. **Duo reach**: gestures from the app window's coordinate (scrim tap, AX5 comparison scrolls), drags clear of the vertical bar, Search via `FST_DEBUG_TAB=search`, Statistics/Leaderboards by route, What's New proved by Close. Counts (raw → open): Duo inner landscape 6/9/32/33 (+AX5 4) → 0, inner portrait 0/16/34/0 → 0, folded 17/30/69/12 → 0, splits 5/5, flyout (Close + scrim) all poses; iPad affected pages Landscape 22/25/56/205 → 0 (AX5 shell 25 → 0), Regular, Compact (Statistics now by route), AX5, Increase Contrast → 0, shell structure 4/4. **iPad and Duo journeys green.** Tooling: `FST_AUDIT_PAGES`, driver `audit:<path>`, pane-top headers measured in place. Record: [accessibility.md](.agents/testing/apple/accessibility.md#results-lane-a11y4-2026-10-06) |
| 2026-10-06 | Lane A11Y4 | Accessibility tail closed (`6fa6f7d4`…`fb7c392c`; apple-ci green): background cover drawn in a Canvas (no AX element) + guard against un-hiding decorative content on pushed pages; Settings-split Licenses row reads as one selected button; Duo Rank History one adjustable element; ⅓ Rival Detail View All reachable; Duo taps/drags anchored to the app window so the inner display is testable. **iPad and Duo audit journeys green** (Duo inner landscape/portrait/folded → 0 open; Duo split 5/5; flyout all poses; iPad re-run pages → 0; shell 4/4). Remaining: three Leaderboards hosted tests time out under parallel load (pre-existing flake, blocks `lane_integrate --test`); operator VoiceOver walkthrough; Mac VoiceOver/FKA need Automation Mode |

| 2026-10-06 | Lane FLAKE | Leaderboards hosted flakes fixed. Under `swift test --parallel` the shared main actor runs ~99% busy, so the spotlight tests reached ready at 62–80 s, past their 60 s wall-clock bound. Readiness bounds now count the wait's own time, its sleeps plus its own work but not queueing delay (`NativeHostedPollBudget` in `nativeHostedSettle` and in the Mac-tree/reveal loops), so a starved run takes longer instead of failing. The overview is hosted in a `NavigationStack`: outside one, its disabled 50%-opacity rows cost 1.35 s per capture instead of 9 ms. Full parallel suite green 3/3 (851 tests). Settling rule: [hosted-snapshots](.agents/testing/apple/hosted-snapshots.md#settling-rule-parallel-runs) |
| 2026-10-07 | Lane FLAKE | Leaderboards hosted-test timeouts fixed (`7eb095a6`, `cb6ab02b`): readiness budgets count only a wait's own work/sleeps (not main-actor queueing under `--parallel`); Leaderboards hosted inside a `NavigationStack` (rows no longer disabled, 1.35 s → 9 ms per capture); rule in `hosted-snapshots.md`. `swift test --parallel` 3/3 locally, apple-ci green. Watch: one-off `selectedRowRevealFadesTheRowItReaches` (Song Band) failure on CI |

| 2026-10-07 | Lane SONGS-GRID | iPad/Duo landscape grid double push (left card tap showed the row's right song on top) re-verified fixed on master by `2b7f4c1f` (`SongGridCardLink`); backdrop matches the visible song. `testSongsGridCardOpensOnlyItsSong` now taps the leading and trailing card (fails without the fix: "Fixture Pulse" on top). |
| 2026-10-07 | Orchestrator (macOS) | Band board selected-row reveal that never landed under load fixed (apple-ci run 37565614724, `selectedRowRevealFadesTheRowItReaches(songBand, standard)`). Root cause in the product: the band board's reload gate sits inside its scroll view and grows the content over its 400 ms reveal; on a starved main actor that ran for seconds, and the reveal's `scrollTo` stopped at the half-grown end (y 286.5 of 2774) and never moved again. An animated `FestivalReloadGate` reveal now registers with the page's `FestivalFadeInScope` (`beginContentReveal`/`endContentReveal` via `withAnimation` completion) and `SelectedRowReveal` awaits `contentRevealed()` before scrolling. Reproduced 100% with six concurrent journeys inside the full parallel bundle (synthetic hogs never did); 0/6 → 6/6 after the fix. Docs: load-transition R5, hosted-snapshots pitfalls. |
| 2026-10-13 | Issue #632 (Apple, iPhone) | Tab-bar accessory replaced by floating glass page tools (fade-up with loaded content, no replay, hidden under sheets/Notifications, stay put on minimize); bell + Profile share one header pill; leading titles on roots and pushed pages (pinned song titles too). Pattern R28, ADR note, guards `apple-tab-accessory` (no allowed files) and `apple-title-display-mode` |
| 2026-10-25 | Orchestrator (iPad, Duo) | Three journeys that failed on stock and slim simulators were stale tests; the product behaves correctly. iPad `SongsChromeJourneyTests/testScrollAwaySectionBarAccessibility` read a `TabBar` the flyout shell hides (`SongsUITestSupport.tabBarTop(in:)`). iPad `FirstRunJourneyTests` song demos: the audit's 3 element-less "Potentially inaccessible text" issues are the Songs page behind the form sheet, now proved in the run (`assertUnnamedTextIsBehindSheet`, `RecognizedText.lines(in:)`). Folded Duo `DuoDrawerJourneyTests`: `fst.shell.drawer` spans the whole window, but the glass (x ≤ 330, y ≤ 670) stays clear of the bar; the test now measures the glass in pixels (`drawerGlassMaxX/MaxY`, shared with `DrawerMotionJourneyTests`). CI runs none of them on iPad; iOS 27 iPad not checked locally (no FST iOS 27 iPad) |
| 2026-10-25 | Orchestrator (tools) | Slim simulators: `tools/sim_slim.py` applies `tools/simslim/ui.json` after every `ios_sim.boot_exclusive` (inside the hold; idempotent, one `simslim verify` when already slim), `ios_sim.py slim --device <alias> [--measure]`, `apple_perf.py ipad` now takes the devcap hold through `sim_lock`. Unit tests `tools/tests/test_sim_slim.py`. |
