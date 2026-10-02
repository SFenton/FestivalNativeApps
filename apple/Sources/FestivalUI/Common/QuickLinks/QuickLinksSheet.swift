import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Accessory button

/// The "Quick Links" control in the iOS 26.1+ tab-bar accessory: a plain button that opens
/// ``QuickLinksSheet`` from the page, because a `Menu` inside the accessory highlights
/// but never opens (measured on iOS 26.5, issue #42). It announces the active section
/// like ``QuickLinksMenu``.
struct QuickLinksSheetButton: View {
    let controller: QuickLinksController

    var body: some View {
        if controller.isAvailable {
            Button {
                controller.presentSheet()
            } label: {
                Label("Quick Links", systemImage: "list.bullet.indent")
            }
            .tint(BrandTokens.textPrimary)
            .accessibilityLabel("Quick Links")
            .accessibilityValue(controller.activeSection?.title ?? "")
            .accessibilityHint("Jumps to a section of this page")
            .accessibilityIdentifier("fst.quick-links.open")
        }
    }
}

// MARK: - Sheet

/// The page's sections as a compact sheet (HIG: a medium-detent sheet keeps the page's
/// context visible), in page order with a checkmark on the active one. Choosing a row
/// closes the sheet and jumps; the same rows and identifiers as ``QuickLinksMenu``.
struct QuickLinksSheet: View {
    let controller: QuickLinksController

    var body: some View {
        NavigationStack {
            List {
                ForEach(controller.sections) { section in
                    Button {
                        controller.choose(section.id)
                    } label: {
                        HStack {
                            QuickLinkSheetRowLabel(section: section)
                            Spacer(minLength: 8)
                            if section.id == controller.activeID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(BrandTokens.accentBlue)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(
                        section.id == controller.activeID ? .isSelected : []
                    )
                    .accessibilityIdentifier("fst.quick-links.item.\(section.id)")
                }
            }
            .navigationTitle(controller.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                FestivalSheetCloseItem(identifier: "fst.quick-links.close") {
                    controller.sheetPresented = false
                }
            }
        }
        .festivalSheet(.compact)
    }
}

/// A sheet row's icon and title. Unlike a `Menu`, a `List` row does not size image
/// assets to the text, so instrument art is fitted to an icon box that scales with
/// Dynamic Type, and nested sections indent by level.
private struct QuickLinkSheetRowLabel: View {
    let section: QuickLinkSection
    @ScaledMetric(relativeTo: .body) private var iconSide: CGFloat = 24
    @ScaledMetric(relativeTo: .body) private var indentStep: CGFloat = 20

    var body: some View {
        Label {
            Text(section.title)
                .foregroundStyle(FestivalText.primary)
        } icon: {
            icon
                .frame(width: iconSide, height: iconSide)
        }
        .padding(.leading, CGFloat(section.depth) * indentStep)
        .accessibilityLabel(section.accessibilityTitle)
    }

    @ViewBuilder private var icon: some View {
        switch section.icon {
        case let .system(name):
            Image(systemName: name)
                .foregroundStyle(FestivalText.primary)
        case let .instrument(instrument):
            Image(InstrumentIcon.assetName(for: instrument, keyboard: false), bundle: .module)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
        case nil:
            Color.clear
        }
    }
}
