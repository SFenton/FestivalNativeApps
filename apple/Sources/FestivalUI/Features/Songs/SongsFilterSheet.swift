import FestivalCore
import FestivalDesign
import SwiftUI

#if os(iOS)
  import UIKit
#endif

/// Selected-player score/FC, instrument and public Item Shop filters. Changes apply as
/// they are made (operator, 2026-09-28: no Cancel/Apply); Done closes the standard
/// `festivalSheet` modal.
struct SongsFilterSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var draftInShop: Bool
  @State private var draftLeavingTomorrow: Bool
  @State private var draftPlayerFilter: SongPlayerScoreFilter
  @State private var draftInstrument: Instrument?
  @State private var scoreSectionsExpanded: Bool
  @State private var applyError: String?
  let applied: SongShopFilter
  let appliedPlayerFilter: SongPlayerScoreFilter
  let appliedInstrument: Instrument?
  let visibleInstruments: Set<Instrument>
  let showShop: Bool
  let shopAvailable: Bool
  let profileAvailable: Bool
  let selectedPlayer: Bool
  let scoreAvailable: Bool
  let invalidScoreFilteringEnabled: Bool
  let onApply: (SongShopFilter, SongPlayerScoreFilter, Instrument?) throws -> Void

  /// Start from the applied filters; every change is committed immediately.
  ///
  /// - Parameters:
  ///   - applied: Saved native public Shop filters.
  ///   - appliedPlayerFilter: Saved typed selected-player chart predicates.
  ///   - appliedInstrument: Currently applied single-chart Songs filter, like web's
  ///     `instrumentFilter` field folded into the same Filter draft.
  ///   - visibleInstruments: Settings-enabled solo charts in source order.
  ///   - showShop: Whether Settings exposes the Shop feature.
  ///   - shopAvailable: Whether a validated Shop feed is retained.
  ///   - profileAvailable: Whether a selected player's scores are available.
  ///   - selectedPlayer: Whether a player identity can show score sections.
  ///   - scoreAvailable: Whether validated scores match the current Songs catalogue.
  ///   - invalidScoreFilteringEnabled: Whether unsupported score substitution blocks raw filters.
  ///   - onApply: Commit all current choices together; called on every change and may
  ///     throw (shown in the sheet).
  init(
    applied: SongShopFilter, showShop: Bool, shopAvailable: Bool,
    profileAvailable: Bool,
    appliedPlayerFilter: SongPlayerScoreFilter = SongPlayerScoreFilter(),
    appliedInstrument: Instrument? = nil,
    visibleInstruments: Set<Instrument> = Set(Instrument.allCases),
    selectedPlayer: Bool = false, scoreAvailable: Bool = false,
    invalidScoreFilteringEnabled: Bool = false,
    onApply: @escaping (SongShopFilter, SongPlayerScoreFilter, Instrument?) throws -> Void
  ) {
    self.applied = applied
    self.appliedPlayerFilter = appliedPlayerFilter.scoped(to: visibleInstruments)
    self.appliedInstrument = appliedInstrument
    self.visibleInstruments = visibleInstruments
    self.showShop = showShop
    self.shopAvailable = shopAvailable
    self.profileAvailable = profileAvailable
    self.selectedPlayer = selectedPlayer
    self.scoreAvailable = scoreAvailable
    self.invalidScoreFilteringEnabled = invalidScoreFilteringEnabled
    self.onApply = onApply
    _draftInShop = State(initialValue: applied.inShop)
    _draftLeavingTomorrow = State(initialValue: applied.leavingTomorrow)
    _draftPlayerFilter = State(initialValue: appliedPlayerFilter.scoped(to: visibleInstruments))
    _draftInstrument = State(initialValue: appliedInstrument)
    _scoreSectionsExpanded = State(
      initialValue: appliedPlayerFilter.scoped(to: visibleInstruments).isActive
    )
  }

  private var draft: SongShopFilter {
    SongShopFilter(inShop: draftInShop, leavingTomorrow: draftLeavingTomorrow)
  }

  /// Identity of the current choices, to commit on any change.
  private struct ChoiceKey: Equatable {
    let shop: SongShopFilter
    let player: SongPlayerScoreFilter
    let instrument: Instrument?
  }

  private var choiceKey: ChoiceKey {
    ChoiceKey(shop: draft, player: draftPlayerFilter, instrument: draftInstrument)
  }

  private var canEnableShop: Bool {
    showShop && shopAvailable && profileAvailable
  }

  private var canEnableScores: Bool {
    selectedPlayer && scoreAvailable && !invalidScoreFilteringEnabled
  }

  /// Choices the list can use right now (paused sources stay as saved, not applied).
  private var isApplicable: Bool {
    (!draft.isActive || canEnableShop)
      && (!draftPlayerFilter.isActive || canEnableScores)
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        Form {
          if selectedPlayer {
            Section("Instrument") {
              Picker("Instrument", selection: $draftInstrument) {
                Text("All instruments").tag(Instrument?.none)
                ForEach(Instrument.allCases.filter(visibleInstruments.contains)) { choice in
                  Text(choice.label).tag(Instrument?.some(choice))
                }
              }
              .pickerStyle(.inline)
              .accessibilityIdentifier("fst.songs.filter.instrument")
            }
          }
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
          if selectedPlayer && scoreSectionsExpanded {
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
                DisclosureGroup {
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
          Section("Item Shop") {
            Toggle("In Shop", isOn: $draftInShop)
              .disabled(!canEnableShop)
              .accessibilityHint("Show songs in the validated public Item Shop")
              .accessibilityIdentifier("fst.songs.filter.in-shop")
            Toggle("Leaving Tomorrow", isOn: $draftLeavingTomorrow)
              .disabled(!canEnableShop)
              .accessibilityHint("Show validated offers leaving tomorrow")
              .accessibilityIdentifier("fst.songs.filter.leaving")
            if !showShop {
              Text("Item Shop is hidden in Settings. Saved filters can be reset.")
                .foregroundStyle(FestivalText.primary)
            } else if !profileAvailable {
              Text("Select a player with available scores to edit song filters.")
                .foregroundStyle(FestivalText.primary)
            } else if !shopAvailable {
              Text("Item Shop filters need matching public Songs and Shop data.")
                .foregroundStyle(FestivalText.primary)
            }
          }
          Section {
            Button(selectedPlayer ? "Reset filters" : "Reset Shop filters") {
              draftInShop = false
              draftLeavingTomorrow = false
              draftPlayerFilter = SongPlayerScoreFilter()
              draftInstrument = nil
            }
            .tint(FestivalText.primary)
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
      }
      .navigationTitle("Filter Songs")
      #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
      #endif
      .toolbar {
        // Dismiss-only modal: trailing Done (modal standard, operator 2026-09-28).
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
            .accessibilityIdentifier("fst.songs.filter.done")
        }
      }
      .onChange(of: choiceKey) { _, _ in commit() }
    }
    // Many collapsible sections (instrument, score/FC, Shop): fixed large detent
    // rather than a partial height that would clip mid-section.
    .festivalSheet(.large)
  }

  /// Apply the current choices immediately when the list can use them.
  private func commit() {
    guard isApplicable else { return }
    do {
      try onApply(draft, draftPlayerFilter, draftInstrument)
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
