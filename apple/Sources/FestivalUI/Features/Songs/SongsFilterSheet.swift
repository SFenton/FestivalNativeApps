import FestivalCore
import FestivalDesign
import SwiftUI

#if os(iOS)
  import UIKit
#endif

/// The web FilterModal: a General section (Year, Duration, Item Shop, Double Bass) that
/// works without a selected player, then selected-player score/FC, instrument and
/// per-instrument bucket filters. Changes apply as they are made (operator, 2026-09-28:
/// no Cancel/Apply); the shared ``FestivalModal``'s system Close dismisses it.
struct SongsFilterSheet: View {
  @State private var draftGeneral: SongGeneralFilter
  @State private var draftPlayerFilter: SongPlayerScoreFilter
  @State private var draftInstrument: Instrument?
  @State private var scoreSectionsExpanded: Bool
  @State private var scoreSectionsAccordion: FestivalAccordionState<Bool>
  @State private var bucketAccordion: FestivalAccordionState<Instrument>
  @State private var yearAccordion: FestivalAccordionState<Bool>
  @State private var durationAccordion: FestivalAccordionState<Bool>
  @State private var shopAccordion: FestivalAccordionState<Bool>
  @State private var doubleBassAccordion: FestivalAccordionState<Bool>
  @State private var seasonAccordion: FestivalAccordionState<Bool>
  @State private var percentileAccordion: FestivalAccordionState<Bool>
  @State private var starsAccordion: FestivalAccordionState<Bool>
  @State private var intensityAccordion: FestivalAccordionState<Bool>
  @State private var applyError: String?
  let appliedGeneral: SongGeneralFilter
  let appliedPlayerFilter: SongPlayerScoreFilter
  let appliedInstrument: Instrument?
  let visibleInstruments: Set<Instrument>
  let showShop: Bool
  let shopAvailable: Bool
  let selectedPlayer: Bool
  let scoreAvailable: Bool
  let invalidScoreFilteringEnabled: Bool
  /// Release decades in the catalogue (``SongGeneralFilter/decades(in:)``).
  let availableDecades: [Int]
  /// Duration buckets to offer (``SongGeneralFilter/durationBuckets(in:)``).
  let availableDurations: [Int]
  /// Season keys to offer (seasons in the player's scores, then 0 for No Score).
  let availableSeasons: [Int]
  let onApply: (SongGeneralFilter, SongPlayerScoreFilter, Instrument?) throws -> Void

  /// Start from the applied filters; every change is committed immediately.
  ///
  /// - Parameters:
  ///   - appliedGeneral: Saved General filters (Year, Duration, Item Shop, Double Bass).
  ///   - showShop: Whether Settings exposes the Shop feature (shows the Item Shop group).
  ///   - shopAvailable: Whether a validated Shop feed matches the current Songs.
  ///   - availableDecades: Year options from the catalogue.
  ///   - availableDurations: Duration options from the catalogue.
  ///   - appliedPlayerFilter: Saved typed selected-player chart predicates.
  ///   - appliedInstrument: Currently applied single-chart Songs filter, like web's
  ///     `instrumentFilter` field folded into the same Filter draft.
  ///   - visibleInstruments: Settings-enabled solo charts in source order.
  ///   - selectedPlayer: Whether a player identity is selected; without one only the
  ///     General section is shown (web `hasSelectedProfile`).
  ///   - scoreAvailable: Whether validated scores match the current Songs catalogue.
  ///   - invalidScoreFilteringEnabled: Whether unsupported score substitution blocks raw filters.
  ///   - availableSeasons: Season filter keys (``SongSeasonBucket/keys(in:)``).
  ///   - onApply: Commit all current choices together; called on every change and may
  ///     throw (shown in the sheet).
  init(
    appliedGeneral: SongGeneralFilter = SongGeneralFilter(),
    showShop: Bool, shopAvailable: Bool,
    availableDecades: [Int] = [], availableDurations: [Int] = Array(0..<10),
    appliedPlayerFilter: SongPlayerScoreFilter = SongPlayerScoreFilter(),
    appliedInstrument: Instrument? = nil,
    visibleInstruments: Set<Instrument> = Set(Instrument.allCases),
    selectedPlayer: Bool = false, scoreAvailable: Bool = false,
    invalidScoreFilteringEnabled: Bool = false,
    availableSeasons: [Int] = [0],
    onApply: @escaping (SongGeneralFilter, SongPlayerScoreFilter, Instrument?) throws -> Void
  ) {
    self.appliedGeneral = appliedGeneral
    self.appliedPlayerFilter = appliedPlayerFilter.scoped(to: visibleInstruments)
    self.appliedInstrument = appliedInstrument
    self.visibleInstruments = visibleInstruments
    self.showShop = showShop
    self.shopAvailable = shopAvailable
    self.selectedPlayer = selectedPlayer
    self.scoreAvailable = scoreAvailable
    self.invalidScoreFilteringEnabled = invalidScoreFilteringEnabled
    // A saved restriction on a bucket no longer in the catalogue stays toggleable.
    self.availableDecades = Array(Set(availableDecades).union(appliedGeneral.excludedDecades)).sorted()
    self.availableDurations = Array(Set(availableDurations).union(appliedGeneral.excludedDurations)).sorted()
    self.availableSeasons = availableSeasons
    self.onApply = onApply
    _draftGeneral = State(initialValue: appliedGeneral)
    _draftPlayerFilter = State(initialValue: appliedPlayerFilter.scoped(to: visibleInstruments))
    _draftInstrument = State(initialValue: appliedInstrument)
    let scoreSectionsOpen = appliedPlayerFilter.scoped(to: visibleInstruments).isActive
    _scoreSectionsExpanded = State(initialValue: scoreSectionsOpen)
    _scoreSectionsAccordion = State(
      initialValue: FestivalAccordionState(expanded: selectedPlayer && scoreSectionsOpen)
    )
    _bucketAccordion = State(initialValue: FestivalAccordionState(selectedPlayer ? appliedInstrument : nil))
    _yearAccordion = State(initialValue: FestivalAccordionState(expanded: appliedGeneral.restrictsYear))
    _durationAccordion = State(initialValue: FestivalAccordionState(expanded: appliedGeneral.restrictsDuration))
    _shopAccordion = State(initialValue: FestivalAccordionState(expanded: appliedGeneral.shop.isActive))
    _doubleBassAccordion = State(initialValue: FestivalAccordionState(expanded: appliedGeneral.restrictsDoubleBass))
    _seasonAccordion = State(initialValue: FestivalAccordionState(expanded: !appliedPlayerFilter.excluded(.season).isEmpty))
    _percentileAccordion = State(initialValue: FestivalAccordionState(expanded: !appliedPlayerFilter.excluded(.percentile).isEmpty))
    _starsAccordion = State(initialValue: FestivalAccordionState(expanded: !appliedPlayerFilter.excluded(.stars).isEmpty))
    _intensityAccordion = State(initialValue: FestivalAccordionState(expanded: !appliedPlayerFilter.excluded(.intensity).isEmpty))
  }

  /// Identity of the current choices, to commit on any change.
  private struct ChoiceKey: Equatable {
    let general: SongGeneralFilter
    let player: SongPlayerScoreFilter
    let instrument: Instrument?
  }

  private var choiceKey: ChoiceKey {
    ChoiceKey(general: draftGeneral, player: draftPlayerFilter, instrument: draftInstrument)
  }

  private var canEnableScores: Bool {
    selectedPlayer && scoreAvailable && !invalidScoreFilteringEnabled
  }

  var body: some View {
    FestivalModal("Filter Songs", closeIdentifier: "fst.songs.filter.done") {
      VStack(spacing: 0) {
        Form {
          generalSections
          if selectedPlayer {
            Section {
              Button {
                scoreSectionsExpanded.toggle()
              } label: {
                HStack {
                  Text("Player Score and FC Filters")
                  Spacer()
                  Image(
                    systemName: scoreSectionsExpanded
                      ? "chevron.up" : "chevron.down"
                  )
                  .accessibilityHidden(true)
                }
                .foregroundStyle(FestivalText.primary)
              }
              .accessibilityValue(
                scoreSectionsExpanded ? "Expanded" : "Collapsed"
              )
              .accessibilityIdentifier("fst.songs.filter.score-sections")
            }
          }
          FestivalAccordionContent(scoreSectionsAccordion) {
            Section("Player Scores") {
              Text(
                "Score and full combo checks match any enabled chart; "
                  + "selected checks on one chart apply together."
              )
              .font(.footnote)
              .foregroundStyle(FestivalText.primary)
              if invalidScoreFilteringEnabled {
                Text(
                  "Score filters are paused while Filter Invalid Scores "
                    + "is enabled in Settings."
                )
                .foregroundStyle(FestivalText.primary)
              } else if !scoreAvailable {
                Text(
                  "Score filters need published player scores from "
                    + "the current Songs catalogue."
                )
                .foregroundStyle(FestivalText.primary)
              }
            }
            Section("All enabled charts") {
              ForEach(SongScoreFilterKind.allCases) { kind in
                Toggle(kind.label, isOn: scoreBinding(kind))
                  .disabled(!canEnableScores)
                  .accessibilityIdentifier(
                    "fst.songs.filter.score.global.\(kind.rawValue)"
                  )
              }
            }
            Section("Individual charts") {
              ForEach(Instrument.allCases.filter(visibleInstruments.contains)) {
                chart in
                FestivalDisclosureGroup {
                  ForEach(SongScoreFilterKind.allCases) { kind in
                    Toggle(
                      kind.label(for: chart),
                      isOn: scoreBinding(kind, chart: chart)
                    )
                    .disabled(!canEnableScores)
                    .accessibilityIdentifier(
                      "fst.songs.filter.score.chart.\(chart.rawValue).\(kind.rawValue)"
                    )
                  }
                } label: {
                  Text(chart.label)
                    .accessibilityIdentifier(
                      "fst.songs.filter.score.instrument.\(chart.rawValue)"
                    )
                }
              }
            }
          }
          // Web order: General, score checks, then the Instrument selector with its
          // one-chart Season / Percentile / Stars / Intensity filters.
          if selectedPlayer {
            Section {
              Picker("Instrument", selection: $draftInstrument) {
                Text("All Instruments").tag(Instrument?.none)
                ForEach(Instrument.allCases.filter(visibleInstruments.contains)) { choice in
                  Text(choice.label).tag(Instrument?.some(choice))
                }
              }
              .pickerStyle(.inline)
              .labelsHidden()
              .accessibilityIdentifier("fst.songs.filter.instrument")
            } header: {
              Text("Instrument")
            } footer: {
              Text("Filtering to a single instrument enables more filters.")
                .foregroundStyle(FestivalText.primary)
            }
          }
          FestivalAccordionContent(bucketAccordion) { _ in
            bucketSections
          }
          Section {
            // Also clears paused player choices hidden while no player is selected.
            Button("Reset Filters", role: .destructive) {
              draftGeneral = SongGeneralFilter()
              draftPlayerFilter = SongPlayerScoreFilter()
              draftInstrument = nil
            }
            .foregroundStyle(FestivalSheetActionColor.destructive)
            .accessibilityIdentifier("fst.songs.filter.reset")
          }
          if let applyError {
            Section {
              Text("Could not save filters: \(applyError)")
                .foregroundStyle(BrandTokens.gold)
                .accessibilityIdentifier("fst.songs.filter.save-error")
            }
          }
        }
        .accessibilityIdentifier("fst.songs.filter.form")
        // Shared accordion motion (pattern `accordion`, #561) for the sections the score
        // button and the instrument choice reveal; driven from the always-present Form.
        .festivalAccordion(
          $scoreSectionsAccordion, follows: selectedPlayer && scoreSectionsExpanded ? true : nil
        )
        .festivalAccordion($bucketAccordion, follows: selectedPlayer ? draftInstrument : nil)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .onChange(of: choiceKey) { _, _ in commit() }
    }
    // Many collapsible sections (General, score/FC, instrument): fixed large detent
    // rather than a partial height that would clip mid-section.
    .festivalSheet(.large)
  }

  // MARK: - General (any profile state)

  /// The web's General section: Year, Duration, Item Shop (while the Shop is shown)
  /// and Double Bass accordions. These read only public catalogue/Shop metadata, so
  /// they are editable with or without a selected player.
  @ViewBuilder private var generalSections: some View {
    Section {
      Text("General filters that apply to all songs.")
        .font(.footnote)
        .foregroundStyle(FestivalText.primary)
    } header: {
      Text("General")
        .accessibilityIdentifier("fst.songs.filter.general")
    }
    generalBucketSection(
      id: "year", title: "Year", hint: "Filter songs by their release decade.",
      keys: availableDecades, expanded: $yearAccordion,
      label: SongGeneralFilter.decadeLabel, excluded: \.excludedDecades
    )
    generalBucketSection(
      id: "duration", title: "Duration", hint: "Filter songs by their duration.",
      keys: availableDurations, expanded: $durationAccordion,
      label: SongGeneralFilter.durationLabel, excluded: \.excludedDurations
    )
    if showShop {
      Section {
        FestivalDisclosureGroup(state: $shopAccordion) {
          Toggle("Available in Item Shop", isOn: shopBinding(available: true))
            .accessibilityIdentifier("fst.songs.filter.shop-available")
          Toggle("Not Available in Item Shop", isOn: shopBinding(available: false))
            .accessibilityIdentifier("fst.songs.filter.shop-unavailable")
          if !shopAvailable && draftGeneral.shop.needsShopFeed {
            Text("Item Shop filters need matching public Songs and Shop data.")
              .font(.footnote)
              .foregroundStyle(FestivalText.primary)
          }
        } label: {
          bucketLabel(
            "Item Shop",
            hint: "Filter songs by whether they are available in the Item Shop."
          )
          .accessibilityIdentifier("fst.songs.filter.shop")
        }
      }
    }
    Section {
      FestivalDisclosureGroup(state: $doubleBassAccordion) {
        Toggle("Double Bass Support", isOn: $draftGeneral.doubleBassSupported)
          .accessibilityIdentifier("fst.songs.filter.double-bass.supported")
        Toggle("No Double Bass Support", isOn: $draftGeneral.doubleBassUnsupported)
          .accessibilityIdentifier("fst.songs.filter.double-bass.unsupported")
      } label: {
        bucketLabel(
          "Double Bass",
          hint: "Filter songs that have or don't have double bass charts for Pro Drums."
        )
        .accessibilityIdentifier("fst.songs.filter.double-bass")
      }
    }
  }

  /// One General bucket accordion (Year or Duration) with Select All / Clear All in
  /// the header, like the per-instrument bucket accordions.
  ///
  /// - Parameters:
  ///   - id: Accessibility identifier suffix.
  ///   - title: Accordion title.
  ///   - hint: The web's hint line.
  ///   - keys: Bucket keys in display order.
  ///   - expanded: Disclosure state.
  ///   - label: Visible and spoken label for a key.
  ///   - excluded: The draft's excluded-key set for this accordion.
  /// - Returns: A Form section.
  private func generalBucketSection(
    id: String, title: String, hint: String, keys: [Int], expanded: Binding<FestivalAccordionState<Bool>>,
    label: @escaping (Int) -> String,
    excluded: WritableKeyPath<SongGeneralFilter, Set<Int>>
  ) -> some View {
    Section {
      FestivalDisclosureGroup(state: expanded) {
        ForEach(keys, id: \.self) { key in
          Toggle(label(key), isOn: Binding(
            get: { !draftGeneral[keyPath: excluded].contains(key) },
            set: { included in
              if included {
                draftGeneral[keyPath: excluded].remove(key)
              } else {
                draftGeneral[keyPath: excluded].insert(key)
              }
            }
          ))
          .accessibilityIdentifier("fst.songs.filter.\(id).\(key)")
        }
      } label: {
        bucketLabel(title, hint: hint)
          .accessibilityIdentifier("fst.songs.filter.\(id)")
      }
    } header: {
      // Header actions are part of the accordion's content: they fade in after it opens
      // and out before it closes.
      FestivalAccordionContent(expanded.wrappedValue) {
        bulkActions(
          id: id, enabled: true,
          all: { draftGeneral[keyPath: excluded] = [] },
          none: { draftGeneral[keyPath: excluded] = Set(keys) }
        )
      }
    }
  }

  private func shopBinding(available: Bool) -> Binding<Bool> {
    Binding(
      get: { available ? draftGeneral.shop.available : draftGeneral.shop.unavailable },
      set: { value in
        draftGeneral.shop = available
          ? SongShopFilter(available: value, unavailable: draftGeneral.shop.unavailable)
          : SongShopFilter(available: draftGeneral.shop.available, unavailable: value)
      }
    )
  }

  // MARK: - Percentile and stars (one instrument)

  /// The web's Season, Percentile, Stars and Intensity accordions, shown once Songs
  /// shows one instrument (they read that chart). Each has Select All / Clear All.
  @ViewBuilder private var bucketSections: some View {
    bucketSection(
      .season, title: "Season",
      hint: "Filter songs by the season your high score was achieved.",
      keys: availableSeasons, expanded: $seasonAccordion
    ) { Text(SongSeasonBucket.label($0)) }
    bucketSection(
      .percentile, title: "Percentile",
      hint: "Show or hide songs based on their leaderboard ranking bracket.",
      keys: SongPercentileBucket.keys, expanded: $percentileAccordion
    ) { Text(SongPercentileBucket.label($0)) }
    bucketSection(
      .stars, title: "Stars",
      hint: "Filter songs by the number of stars on your high score.",
      keys: SongStarsBucket.keys, expanded: $starsAccordion
    ) { key in
      if key == 0 {
        Text(SongStarsBucket.label(key))
      } else {
        StarRating(stars: key).accessibilityHidden(true)
      }
    }
    bucketSection(
      .intensity, title: "Intensity",
      hint: "Filter songs by the chart's intensity.",
      keys: SongIntensityBucket.keys, expanded: $intensityAccordion
    ) { key in
      if key == 0 {
        Text(SongIntensityBucket.label(key))
      } else {
        DifficultyMeter(level: Double(key)).accessibilityHidden(true)
      }
    }
  }

  /// One bucket accordion: title and hint, Select All / Clear All, one toggle per key.
  ///
  /// - Parameters:
  ///   - kind: Bucket filter.
  ///   - title: Accordion title.
  ///   - hint: The web's hint line.
  ///   - keys: Keys in display order.
  ///   - expanded: Disclosure state.
  ///   - label: Visible label for a key (spoken label comes from the kind).
  /// - Returns: A Form section.
  private func bucketSection<Label: View>(
    _ kind: SongBucketKind, title: String, hint: String, keys: [Int],
    expanded: Binding<FestivalAccordionState<Bool>>, @ViewBuilder label: @escaping (Int) -> Label
  ) -> some View {
    Section {
      FestivalDisclosureGroup(state: expanded) {
        ForEach(keys, id: \.self) { key in
          Toggle(isOn: bucketBinding(kind, key)) { label(key) }
            .accessibilityLabel(Self.spokenLabel(kind, key))
            .disabled(!canEnableScores)
            .accessibilityIdentifier("fst.songs.filter.\(kind.rawValue).\(key)")
        }
      } label: {
        // ID on the label, not the group: on iOS 26 a DisclosureGroup identifier
        // replaces every nested toggle's own.
        bucketLabel(title, hint: hint)
          .accessibilityIdentifier("fst.songs.filter.\(kind.rawValue)")
      }
    } header: {
      // Platform pattern: trailing text actions in the section header, Clear in red
      // (operator batch 7), shown while the accordion is open and faded with its content.
      FestivalAccordionContent(expanded.wrappedValue) {
        bulkActions(
          id: kind.rawValue, enabled: canEnableScores,
          all: { draftPlayerFilter = draftPlayerFilter.settingExcluded(kind, []) },
          none: { draftPlayerFilter = draftPlayerFilter.settingExcluded(kind, Set(keys)) }
        )
      }
    }
  }

  /// VoiceOver label for a bucket toggle.
  private static func spokenLabel(_ kind: SongBucketKind, _ key: Int) -> String {
    switch kind {
    case .season: SongSeasonBucket.label(key)
    case .percentile: SongPercentileBucket.label(key)
    case .stars: SongStarsBucket.label(key)
    case .intensity: SongIntensityBucket.label(key)
    }
  }

  private func bucketBinding(_ kind: SongBucketKind, _ key: Int) -> Binding<Bool> {
    Binding(
      get: { draftPlayerFilter.includes(kind, key) },
      set: { draftPlayerFilter = draftPlayerFilter.setting(kind, key, included: $0) }
    )
  }

  /// An accordion title with the web's hint line beneath.
  private func bucketLabel(_ title: String, hint: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .foregroundStyle(FestivalText.primary)
      Text(hint)
        .font(.footnote)
        .foregroundStyle(FestivalText.primary)
    }
    .accessibilityElement(children: .combine)
  }

  /// The web's `BulkActions` row (Select All / Clear All).
  private func bulkActions(
    id: String, enabled: Bool, all: @escaping () -> Void, none: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 16) {
      Spacer()
      Button("Select All", action: all)
        .foregroundStyle(FestivalText.primary)
        .accessibilityIdentifier("fst.songs.filter.\(id).select-all")
      Button("Clear All", action: none)
        .foregroundStyle(FestivalSheetActionColor.destructive)
        .accessibilityIdentifier("fst.songs.filter.\(id).clear-all")
    }
    .font(.subheadline.weight(.semibold))
    .textCase(nil)
    .buttonStyle(.borderless)
    .disabled(!enabled)
  }

  /// Apply the current choices immediately. Choices the list cannot use yet (a Shop
  /// feed or player scores still loading) are saved and paused by Songs, not dropped.
  private func commit() {
    do {
      try onApply(draftGeneral, draftPlayerFilter, draftInstrument)
      applyError = nil
    } catch {
      applyError = error.localizedDescription
    }
  }

  /// Bind a global or per-chart condition to the staged, typed filter value.
  ///
  /// - Parameters:
  ///   - kind: One of four independent source score and FC checks.
  ///   - chart: Optional individual chart; nil updates all visible charts.
  /// - Returns: Native two-way toggle binding (committed through `commit()`).
  private func scoreBinding(
    _ kind: SongScoreFilterKind, chart: Instrument? = nil
  ) -> Binding<Bool> {
    Binding(
      get: {
        if let chart { return draftPlayerFilter.contains(kind, for: chart) }
        return draftPlayerFilter.allVisible(
          kind, visibleInstruments: visibleInstruments
        )
      },
      set: { enabled in
        if let chart {
          draftPlayerFilter = draftPlayerFilter.setting(
            kind, for: chart, enabled: enabled
          )
        } else {
          draftPlayerFilter = draftPlayerFilter.settingAll(
            kind, visibleInstruments: visibleInstruments, enabled: enabled
          )
        }
      }
    )
  }
}

extension SongScoreFilterKind {
  fileprivate var label: String {
    switch self {
    case .missingScores: "Missing Scores"
    case .hasScores: "Has Scores"
    case .missingFCs: "Missing FCs"
    case .hasFCs: "Has FCs"
    }
  }

  /// Speak the same chart-specific score/FC predicate as the source Filter.
  ///
  /// - Parameter chart: Visible solo instrument represented by the native toggle.
  /// - Returns: A concise, unique action label with its chart name.
  fileprivate func label(for chart: Instrument) -> String {
    switch self {
    case .missingScores: "Missing \(chart.label) Scores"
    case .hasScores: "Has \(chart.label) Scores"
    case .missingFCs: "Missing \(chart.label) FCs"
    case .hasFCs: "Has \(chart.label) FCs"
    }
  }
}
