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
                            QuickLinkLabel(section: section)
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
            .accessibilityLabel("Quick Links")
            .accessibilityValue(controller.activeSection?.title ?? "")
            .accessibilityHint("Jumps to a section of this page")
            .accessibilityIdentifier("fst.quick-links.open")
        }
    }

    /// Reading returns the active section; writing requests a jump (re-selecting the
    /// active section jumps back to its start).
    /// The sections for the inline-accessory sheet (``PageToolMenu``).
    private func choices() -> [PageToolMenuChoice] {
        let controller = controller
        return controller.sections.map { section in
            PageToolMenuChoice(
                id: "fst.quick-links.item.\(section.id)", label: AnyView(QuickLinkLabel(section: section)),
                isSelected: section.id == controller.activeID, action: { controller.jump(to: section.id) }
            )
        }
    }

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

    /// Instrument icon side at the default text size, sized for visual weight (#313).
    ///
    /// The artwork is a full-bleed disc whose black outer ring disappears on the dark
    /// sheet and menus, so only 81–86 % of the side reads. 24 pt
    /// (``InstrumentIcon/menuIconSide``) shows a 19–21 pt disc beside the 20 pt-tall SF
    /// Symbols at 17 pt body text on iOS/iPadOS; 19 pt shows 15–16 pt beside macOS's
    /// 16 pt menu symbols (HIG Icons: "Adjust dimensions for visual weight so they look
    /// consistent, rather than forcing equal geometry").
    #if os(macOS)
    static let instrumentIconBaseSide: CGFloat = 19
    #else
    static let instrumentIconBaseSide: CGFloat = InstrumentIcon.menuIconSide
    #endif

    /// Height of the SF Symbols in neighbouring rows at the default text size: 20 pt
    /// beside 17 pt body text, 16 pt in macOS menus. The visible instrument disc matches it.
    #if os(macOS)
    static let adjacentSymbolSide: CGFloat = 16
    #else
    static let adjacentSymbolSide: CGFloat = 20
    #endif

    /// The text size the adjacent row symbols stop growing at: in the accessibility sizes
    /// list-row SF Symbols stay at their xxxLarge size (20 pt → 28 pt tall measured at
    /// Accessibility XL) while body text keeps growing.
    static let symbolScaleLimit = DynamicTypeSize.xxxLarge

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The instrument icon side for a text size: scaled like body text (HIG Typography:
    /// "Increase the size of meaningful interface icons as font size increases") up to
    /// ``symbolScaleLimit``, so it keeps matching the symbols. macOS menus don't scale.
    ///
    /// - Parameter size: The environment's Dynamic Type size.
    /// - Returns: The side in points before ``InstrumentIcon/menuSide(_:)`` snapping.
    static func instrumentIconSide(for size: DynamicTypeSize) -> CGFloat {
        #if canImport(UIKit)
        let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(min(size, symbolScaleLimit)))
        return UIFontMetrics(forTextStyle: .body).scaledValue(for: instrumentIconBaseSide, compatibleWith: traits)
        #else
        return instrumentIconBaseSide
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
                    for: instrument, keyboard: false, side: Self.instrumentIconSide(for: dynamicTypeSize)
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
