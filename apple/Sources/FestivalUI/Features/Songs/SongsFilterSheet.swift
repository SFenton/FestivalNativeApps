import FestivalCore
import FestivalDesign
import SwiftUI

#if os(iOS)
  import UIKit
#endif

/// Native draft for selected-player score/FC and public Item Shop conditions.
struct SongsFilterSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @State private var draftInShop: Bool
  @State private var draftLeavingTomorrow: Bool
  @State private var draftPlayerFilter: SongPlayerScoreFilter
  @State private var draftInstrument: Instrument?
  @State private var scoreSectionsExpanded: Bool
  @State private var discardPending = false
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

  /// Stage all backed toggles without changing Songs until Apply.
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
  ///   - onApply: Atomically commit all draft choices or throw without dismissing.
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

  private var hasChanges: Bool {
    draft != applied || draftPlayerFilter != appliedPlayerFilter
      || draftInstrument != appliedInstrument
  }

  private var canEnableShop: Bool {
    showShop && shopAvailable && profileAvailable
  }

  private var canEnableScores: Bool {
    selectedPlayer && scoreAvailable && !invalidScoreFilteringEnabled
  }

  private var canApply: Bool {
    hasChanges && (!draft.isActive || canEnableShop)
      && (!draftPlayerFilter.isActive || canEnableScores)
  }

  private var actionLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: 12))
      : AnyLayout(HStackLayout(spacing: 12))
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        #if os(iOS)
          Text("Filter Songs")
            .font(.title2.bold())
            .foregroundStyle(BrandTokens.textPrimary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 8)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("fst.songs.filter.title")
        #endif
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
                .foregroundStyle(BrandTokens.textPrimary)
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
              .foregroundStyle(BrandTokens.textSecondary)
              if invalidScoreFilteringEnabled {
                Text(
                  "Score filters are paused while Filter Invalid Scores "
                    + "is enabled in Settings."
                )
                .foregroundStyle(BrandTokens.textSecondary)
              } else if !scoreAvailable {
                Text(
                  "Score filters need published player scores from "
                    + "the current Songs catalogue."
                )
                .foregroundStyle(BrandTokens.textSecondary)
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
                .foregroundStyle(BrandTokens.textSecondary)
            } else if !profileAvailable {
              Text("Select a player with available scores to edit song filters.")
                .foregroundStyle(BrandTokens.textSecondary)
            } else if !shopAvailable {
              Text("Item Shop filters need matching public Songs and Shop data.")
                .foregroundStyle(BrandTokens.textSecondary)
            }
          }
          Section {
            Button(selectedPlayer ? "Reset filters" : "Reset Shop filters") {
              draftInShop = false
              draftLeavingTomorrow = false
              draftPlayerFilter = SongPlayerScoreFilter()
              draftInstrument = nil
            }
            .tint(BrandTokens.textPrimary)
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
      #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
      #else
        .navigationTitle("Filter Songs")
      #endif
      .safeAreaInset(edge: .bottom, spacing: 0) {
        actionLayout {
          Button {
            if hasChanges { discardPending = true } else { dismiss() }
          } label: {
            Text("Cancel")
              .font(.body)
              .foregroundStyle(BrandTokens.textPrimary)
              .frame(maxWidth: .infinity, minHeight: 44)
              .background(
                BrandTokens.cardBackground,
                in: RoundedRectangle(cornerRadius: 10)
              )
          }
          .buttonStyle(HighContrastPagerStyle())
          .accessibilityIdentifier("fst.songs.filter.cancel")
          Button {
            do {
              try onApply(draft, draftPlayerFilter, draftInstrument)
              dismiss()
            } catch {
              applyError = error.localizedDescription
            }
          } label: {
            Text("Apply")
              .font(.body.bold())
              .foregroundStyle(
                canApply
                  ? BrandTokens.textPrimary : BrandTokens.textSecondary
              )
              .frame(maxWidth: .infinity, minHeight: 44)
              .background(
                BrandTokens.cardBackground,
                in: RoundedRectangle(cornerRadius: 10)
              )
          }
          .buttonStyle(HighContrastPagerStyle())
          .disabled(!canApply)
          .accessibilityIdentifier("fst.songs.filter.apply")
        }
        .padding(12)
        .background(BrandTokens.cardBackground)
      }
    }
    // Many collapsible sections (instrument, score/FC, Shop): fixed large detent
    // rather than a partial height that would clip mid-section.
    .festivalSheet(.large)
    .alert("Discard filter changes?", isPresented: $discardPending) {
      Button("Continue Editing", role: .cancel) {}
      Button("Discard Changes", role: .destructive) { dismiss() }
    } message: {
      Text("The song list will keep its current filters.")
    }
    .interactiveDismissDisabled()
  }

  /// Bind a global or per-chart condition to the staged, typed filter value.
  ///
  /// - Parameters:
  ///   - kind: One of four independent source score and FC checks.
  ///   - chart: Optional individual chart; nil updates all visible charts.
  /// - Returns: Native two-way toggle binding without changing applied rows.
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
