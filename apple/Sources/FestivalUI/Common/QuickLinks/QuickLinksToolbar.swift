import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Toolbar item

/// The page's "Quick Links" toolbar button: a native `Menu` listing the page's
/// sections with the active one checked. Hidden while fewer than two sections exist.
///
/// Add it to the page's own `.toolbar { … }` so it coexists with page actions and
/// `festivalRootChrome`; the system groups it into the trailing glass capsule on iOS 26.
public struct QuickLinksToolbarItem: ToolbarContent {
    private let controller: QuickLinksController
    private let placement: ToolbarItemPlacement
    /// Set where Quick Links sits in the iPhone tab-bar accessory instead (registered by
    /// the `.quickLinks` container, issue #92).
    @Environment(\.pageToolsRegistry) private var pageTools

    /// Create the toolbar item.
    ///
    /// - Parameters:
    ///   - controller: The page's controller, also passed to `.quickLinks(_:title:…)`.
    ///   - placement: Toolbar placement; defaults to the trailing edge.
    public init(_ controller: QuickLinksController, placement: ToolbarItemPlacement = QuickLinksToolbarItem.defaultPlacement) {
        self.controller = controller
        self.placement = placement
    }

    /// Trailing navigation bar on iOS, primary action elsewhere (`.festivalPageAction`).
    public static var defaultPlacement: ToolbarItemPlacement { .festivalPageAction }

    public var body: some ToolbarContent {
        if pageTools == nil {
            item
        }
    }

    @ToolbarContentBuilder private var item: some ToolbarContent {
        // Default priority in the iPhone Duo vertical bar: the bell and profile stay
        // visible first (issue #92, ``RootChromeRailItem``).
        #if os(iOS)
        if #available(iOS 27.0, *) {
            ToolbarItem(placement: placement) {
                QuickLinksMenu(controller: controller)
            }
            .railVisibilityPriority(.quickLinks)
        } else {
            ToolbarItem(placement: placement) {
                QuickLinksMenu(controller: controller)
            }
        }
        #else
        ToolbarItem(placement: placement) {
            QuickLinksMenu(controller: controller)
        }
        #endif
    }
}

// MARK: - Menu

/// "Quick Links" menu button; usable outside a toolbar (e.g. an iPad inspector header).
public struct QuickLinksMenu: View {
    let controller: QuickLinksController

    /// Create the menu.
    ///
    /// - Parameter controller: The page's quick-links controller.
    public init(controller: QuickLinksController) {
        self.controller = controller
    }

    public var body: some View {
        if controller.isAvailable {
            PageToolMenu(controller.title, choices: choices) {
                Section(controller.title) {
                    Picker(controller.title, selection: selection) {
                        ForEach(controller.sections) { section in
                            QuickLinkLabel(section: section, presentation: .menu)
                                .tag(Optional(section.id))
                                .accessibilityIdentifier("fst.quick-links.item.\(section.id)")
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            } label: {
                Label("Quick Links", systemImage: "list.bullet.indent")
            }
            // iOS flips `.automatic` menus that open upward, listing sections
            // bottom-to-top; keep page order wherever it opens.
            .menuOrder(.fixed)
            .tint(BrandTokens.textPrimary)
            .festivalBarItemAccessibility(
                label: "Quick Links", value: controller.activeSection?.title ?? ""
            )
            .accessibilityHint("Jumps to a section of this page")
            .accessibilityIdentifier("fst.quick-links.open")
        }
    }

    /// The sections for the inline-accessory sheet (``PageToolMenu``), in page order with
    /// the active one selected.
    ///
    /// - Returns: One choice per section; picking one jumps to it.
    func choices() -> [PageToolMenuChoice] {
        let controller = controller
        return controller.sections.map { section in
            PageToolMenuChoice(
                id: "fst.quick-links.item.\(section.id)", label: AnyView(QuickLinkLabel(section: section, presentation: .list)),
                isSelected: section.id == controller.activeID, action: { controller.jump(to: section.id) }
            )
        }
    }

    /// Reading returns the active section; writing requests a jump (re-selecting the
    /// active section jumps back to its start).
    private var selection: Binding<String?> {
        Binding(
            get: { controller.activeID },
            set: { id in if let id { controller.jump(to: id) } }
        )
    }
}

// MARK: - Row label

/// One quick link's icon and title, indented by depth.
///
/// Instrument artwork is pre-sized to the visual weight of the adjacent SF Symbols
/// (issues #303, #313): menus and the iPhone accessory sheet draw a plain image at its
/// 144 pt intrinsic size.
struct QuickLinkLabel: View {
    let section: QuickLinkSection
    /// Where the row is shown; menus draw smaller symbols than list rows.
    let presentation: Presentation

    /// The chooser that shows the row.
    enum Presentation {
        /// The iPhone tab-bar accessory sheet's `List` (``PageToolMenu``).
        case list
        /// The native `Menu` (iPad, iPhone Duo, Mac).
        case menu
    }

    /// Instrument icon side at the default text size, sized for visual weight (#313).
    ///
    /// The artwork is a full-bleed disc whose black outer ring disappears on the dark
    /// sheet and menus, so only 81–86 % of the side reads: the visible disc, not the
    /// frame, matches ``adjacentSymbolSide(_:)`` (HIG Icons: "Adjust dimensions for
    /// visual weight so they look consistent, rather than forcing equal geometry").
    /// iOS list rows use 24 pt (``InstrumentIcon/menuIconSide``) beside 20 pt-tall symbols
    /// and iOS menus 17 pt beside 13.5 pt symbols. macOS menus keep 16 pt (#303).
    ///
    /// - Parameter presentation: The chooser showing the row.
    /// - Returns: The side in points at the default text size.
    static func instrumentIconBaseSide(_ presentation: Presentation) -> CGFloat {
        #if os(macOS)
        return 16
        #else
        switch presentation {
        case .list: return InstrumentIcon.menuIconSide
        case .menu: return 17
        }
        #endif
    }

    /// Height of the SF Symbols in neighbouring rows at the default text size, measured
    /// on iOS 26: 20 pt in list rows beside 17 pt body text, 13.5 pt in menus beside
    /// 15 pt menu text. macOS menus aren't measured (no GUI automation).
    ///
    /// - Parameter presentation: The chooser showing the row.
    /// - Returns: The symbol height in points.
    static func adjacentSymbolSide(_ presentation: Presentation) -> CGFloat {
        switch presentation {
        case .list: 20
        case .menu: 13.5
        }
    }

    /// Text sizes over which list-row SF Symbols hold their xxxLarge size while body text
    /// keeps growing (measured on iOS 26 List rows: 20 pt tall at Large, 27 at xxxLarge,
    /// 25.5 at AX1, 28 at AX3, then 38 at AX5, growing with body text again).
    static let symbolPlateau = DynamicTypeSize.xxxLarge...DynamicTypeSize.accessibility3

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The instrument icon side for a text size, following the row symbols' curve so the
    /// visible disc keeps matching them (HIG Typography: "Increase the size of meaningful
    /// interface icons as font size increases").
    ///
    /// Scales like body text up to xxxLarge, holds across ``symbolPlateau``, then scales
    /// with body text from there. macOS menus don't scale.
    ///
    /// - Parameters:
    ///   - size: The environment's Dynamic Type size.
    ///   - presentation: The chooser showing the row.
    /// - Returns: The side in points before ``InstrumentIcon/menuSide(_:)`` snapping.
    static func instrumentIconSide(for size: DynamicTypeSize, in presentation: Presentation) -> CGFloat {
        let base = instrumentIconBaseSide(presentation)
        #if canImport(UIKit)
        let metrics = UIFontMetrics(forTextStyle: .body)
        func scaled(_ value: CGFloat, at size: DynamicTypeSize) -> CGFloat {
            metrics.scaledValue(
                for: value, compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
            )
        }
        if size <= symbolPlateau.lowerBound { return scaled(base, at: size) }
        let plateau = scaled(base, at: symbolPlateau.lowerBound)
        if size <= symbolPlateau.upperBound { return plateau }
        return plateau * scaled(17, at: size) / scaled(17, at: symbolPlateau.upperBound)
        #else
        return base
        #endif
    }

    var body: some View {
        Label {
            Text(indent + section.title)
        } icon: {
            switch section.icon {
            case let .system(name):
                Image(systemName: name)
            case let .instrument(instrument):
                InstrumentIcon.menuImage(
                    for: instrument, keyboard: false, side: Self.instrumentIconSide(for: dynamicTypeSize, in: presentation)
                )
            case nil:
                EmptyView()
            }
        }
        .accessibilityLabel(section.accessibilityTitle)
    }

    /// Menus cannot indent rows, so nested sections get a leading figure space per level.
    private var indent: String {
        String(repeating: "\u{2007}\u{2007}", count: section.depth)
    }
}
