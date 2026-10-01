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
    /// Where the iPhone bottom dock exists the menu lives there instead.
    @Environment(\.isTabAccessoryAvailable) private var inDock

    /// Create the toolbar item.
    ///
    /// - Parameters:
    ///   - controller: The page's controller, also passed to `.quickLinks(_:title:…)`.
    ///   - placement: Toolbar placement; defaults to the trailing edge.
    public init(_ controller: QuickLinksController, placement: ToolbarItemPlacement = QuickLinksToolbarItem.defaultPlacement) {
        self.controller = controller
        self.placement = placement
    }

    /// Trailing navigation bar on iOS, primary action elsewhere.
    public static var defaultPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }

    public var body: some ToolbarContent {
        if !inDock || controller.prefersToolbar {
            ToolbarItem(placement: placement) {
                QuickLinksMenu(controller: controller)
            }
        }
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
            Menu {
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
            // iOS flips `.automatic` menus that open upward (the iPhone bottom dock),
            // listing sections bottom-to-top; keep page order wherever it opens.
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
    private var selection: Binding<String?> {
        Binding(
            get: { controller.activeID },
            set: { id in if let id { controller.jump(to: id) } }
        )
    }
}

// MARK: - Row label

/// One quick link's icon and title, indented by depth.
struct QuickLinkLabel: View {
    let section: QuickLinkSection

    var body: some View {
        Label {
            Text(indent + section.title)
        } icon: {
            switch section.icon {
            case let .system(name):
                Image(systemName: name)
            case let .instrument(instrument):
                Image(InstrumentIcon.assetName(for: instrument, keyboard: false), bundle: .module)
                    .renderingMode(.original)
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
