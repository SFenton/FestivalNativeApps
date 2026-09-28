# Songs section index — Android notes

> **What:** the Android right-edge section index. **Read when:** changing `SectionIndexScrubber` or `SongSectionIndex`. Behavior: [spec.md](spec.md).

- Shown for Title/Artist/Year with ≥2 sections; `AnimatedVisibility` fades/slides it in and out as the sort or results change.
- Tap or drag jumps (`scrollToItem`, no network); labels are sampled when they don't fit, positions still reach every section; a frosted pill shows while pressed.
- Accessibility: one node (`fst.songs.section-index`), description "Section index", state = the section at the top of the list, custom actions **Next section** / **Previous section**.
- Missing or zero year is its own "—" section.
