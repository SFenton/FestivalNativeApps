# Songs section index — Android notes

> **What:** the Android right-edge section index. **Read when:** changing `SectionIndexScrubber` or `SongSectionIndex`. Behavior: [spec.md](spec.md).

- Shown for Title/Artist/Year with ≥2 sections; `AnimatedVisibility` fades/slides it in and out as the sort or results change.
- Tap or drag jumps (`scrollToItem`, no network); a frosted pill shows while pressed.
- When the labels don't fit (large text, landscape), every `SongSectionIndex.stride()`-th label is drawn in an equal slot. A touch on a drawn label opens that label's section, and the gaps between labels reach the skipped sections (`SongSectionIndex.sectionAt`). Before #48 the touch was mapped evenly over all sections, so at font scale 2 # opened A and B opened C. `SongsSectionIndexUiTest` covers a far jump and the reported section.
- Accessibility: one node (`fst.songs.section-index`), description "Section index", state = the section at the top of the list, custom actions **Next section** / **Previous section**.
- Missing or zero year is its own "—" section.
