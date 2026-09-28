#if os(macOS)
import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - SuggestionsFilterSheet

/// A standalone `Form`-based sheet (like Songs' Sort/Filter sheets): render its
/// content bare, without a window, per `hosted-snapshots.md`'s pitfall that
/// attaching a window makes native pickers look inactive — and, as this app's
/// other bare-hosted Form sheets already do (`SongsSortSheetRenderTests.swift`),
/// prove branch coverage through distinct pixel captures rather than per-row
/// Form/List accessibility identifiers, which don't reliably surface through
/// `nativeHostedAccessibility`'s walk for `ForEach`-generated rows even with a
/// window attached.
///
/// Previously untested (`SuggestionsFilterSheet.swift` measured 0% coverage,
/// per `.agents/testing/apple/coverage.md`'s Lane U2 table). Its Cancel/Apply
/// actions moved from a custom `safeAreaInset` footer to semantic
/// `.cancellationAction`/`.confirmationAction` toolbar placements; per
/// `hosted-snapshots.md`'s newly-documented pitfall, a hosted window never gets
/// an `NSToolbar`, so those two buttons cannot be asserted here — only the Form
/// content and the draft state they gate. The actual Cancel/Apply/Reset
/// interactions are covered on-device by `SuggestionsJourneyTests.swift`
/// (`fst.suggestions.filter.cancel`/`.apply`/`.reset`), whose accessibility
/// identifiers this sheet keeps unchanged.
@MainActor
@Test func suggestionsFilterSheetPaintsVisibleInstrumentAndOverrideSections() throws {
    var bassOff = SuggestionFilterSettings.defaults()
    bassOff.setInstrumentEnabled(.bass, enabled: false)
    let cases: [(name: String, applied: SuggestionFilterSettings, visible: [Instrument])] = [
        ("defaults-two-instruments", .defaults(), [.lead, .bass]),
        ("bass-disabled", bassOff, [.lead, .bass]),
        ("no-visible-instruments", .defaults(), []),
    ]
    var images: [String: Data] = [:]
    for scenario in cases {
        let size = CGSize(width: 390, height: 700)
        let host = nativeHostedView(
            SuggestionsFilterSheet(
                applied: scenario.applied, visibleInstruments: scenario.visible,
                onApply: { _ in }
            )
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue)
            .background(BrandTokens.appBackground),
            size: size
        )
        let image = try nativeHostedImage(host)
        let pixels = nativeHostedControlPixels(image)
        #expect(pixels.bright > 20)
        #expect(pixels.placeholder == 0)
        images[scenario.name] = try nativeHostedPNG(
            image, filename: "suggestions-filter-\(scenario.name).png",
            environment: "FST_SUGGESTIONS_RENDER_OUT"
        )
    }
    // An empty `visibleInstruments` hides both the Instruments and
    // Instrument-Specific sections entirely (fewer, shorter rows), so it must
    // paint differently from either two-instrument scenario.
    #expect(images["defaults-two-instruments"] != images["no-visible-instruments"])
    #expect(images["bass-disabled"] != images["no-visible-instruments"])
    let ax = nativeHostedAccessibility(
        nativeHostedView(
            SuggestionsFilterSheet(applied: .defaults(), visibleInstruments: [.lead], onApply: { _ in })
                .preferredColorScheme(.dark)
                .background(BrandTokens.appBackground),
            size: CGSize(width: 390, height: 700)
        )
    )
    #expect(ax.texts.contains("Filter Suggestions"))
    #expect(ax.identifiers.contains("fst.suggestions.filter.form"))
}
#endif
