import FestivalCore
import FestivalDesign
import SwiftUI

/// The Item Shop's New / Available / Leaving Tomorrow filter (issues #19, #376), built from the
/// Songs filter sheet's pieces: the shared ``FestivalModal`` with the system Close, a
/// grouped `Form` of switch rows and the red Reset action. Changes apply as they are
/// made, like ``SongsFilterSheet`` (operator, 2026-09-28: no Cancel/Apply). The switches
/// start on and turning one off hides its group (issue #376), like the Songs Item Shop
/// switches.
///
/// HIG Toggles (iOS, iPadOS): "Use the switch style only in a list row"; HIG Sheets
/// (iOS, iPadOS): "Support swiping vertically to dismiss".
struct ShopFilterSheet: View {
  @State private var draft: ShopOfferFilter
  let onApply: (ShopOfferFilter) -> Void

  /// Start from the applied filter; every change is committed immediately.
  ///
  /// - Parameters:
  ///   - applied: The saved Shop filter.
  ///   - onApply: Saves the current choices; called on every change.
  init(applied: ShopOfferFilter, onApply: @escaping (ShopOfferFilter) -> Void) {
    _draft = State(initialValue: applied)
    self.onApply = onApply
  }

  var body: some View {
    FestivalModal("Filter Shop", closeIdentifier: "fst.shop.filter.done") {
      Form {
        Section {
          ForEach(ShopAvailability.allCases) { group in
            Toggle(group.label, isOn: binding(group))
              .accessibilityHint(Self.hint(group))
              .accessibilityIdentifier("fst.shop.filter.\(group.rawValue)")
          }
        } header: {
          Text("Availability")
        } footer: {
          Text(
            "Turn a switch off to hide those offers. With every switch on, every offer shows."
          )
          .foregroundStyle(FestivalText.primary)
        }
        Section {
          Button("Reset Filters", role: .destructive) {
            draft = ShopOfferFilter()
          }
          .foregroundStyle(FestivalSheetActionColor.destructive)
          .accessibilityIdentifier("fst.shop.filter.reset")
        }
      }
      .festivalFormIdentifier("fst.shop.filter.form")
      .onChange(of: draft) { _, updated in onApply(updated) }
    }
    .festivalSheet(.compact)
  }

  /// Bind one group's switch to the draft.
  ///
  /// - Parameter group: One availability group.
  /// - Returns: Two-way switch binding (committed through `onChange`).
  private func binding(_ group: ShopAvailability) -> Binding<Bool> {
    Binding(
      get: { draft.includes(group) },
      set: { draft = draft.setting(group, included: $0) }
    )
  }

  /// What a group's switch shows, for VoiceOver.
  ///
  /// - Parameter group: One availability group.
  /// - Returns: A short hint.
  static func hint(_ group: ShopAvailability) -> String {
    switch group {
    case .new: "Show offers new to the Item Shop"
    case .available: "Show offers that are neither new nor leaving tomorrow"
    case .leavingTomorrow: "Show offers leaving the Item Shop tomorrow"
    }
  }
}
