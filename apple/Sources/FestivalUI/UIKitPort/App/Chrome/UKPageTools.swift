#if os(iOS)
import UIKit

// MARK: - Page tools

/// One of a page's tools (Sort, Filter, Find Rival, Quick Links …).
///
/// Pages vend their tools; the shell places them: in the navigation bar before the account
/// group, or (iPhone tab bar) as floating glass buttons above the tab bar
/// (`festivalFloatingPageTools`, issue #632).
struct UKPageTool {
    /// Position in the row (``PageToolOrder``); equal orders keep array order.
    var order: Int
    /// The bar button (an action or a menu), already carrying its identifier and labels.
    var item: UIBarButtonItem
    /// A compact choice sheet the iPhone floating tool opens instead of the item's menu
    /// (``PageToolMenu``); bar placements keep the menu.
    var sheet: UKPageToolSheet?
    /// Creates a tool.
    ///
    /// - Parameters:
    ///   - order: Position (``PageToolOrder``).
    ///   - item: The bar button.
    ///   - sheet: The floating tool's choice sheet, if it has one.
    init(
        order: Int, item: UIBarButtonItem, sheet: UKPageToolSheet? = nil
    ) {
        self.order = order
        self.item = item
        self.sheet = sheet
    }
}

/// One native command in the fixed iPadOS page-tool menu family.
///
/// The command carries the page's existing action closure. `UKMenuBar` projects this
/// value into `UICommand` instances, while the debug mirror projects those same
/// instances into UIKit controls; neither surface owns page behavior.
@MainActor
struct UKPageMenuCommand {
    let identifier: String
    let title: String
    var isEnabled: Bool = true
    var state: UICommand.State = .off
    var children: [UKPageMenuCommand] = []
    let perform: (() -> Void)?

    init(
        identifier: String, title: String, isEnabled: Bool = true,
        state: UICommand.State = .off, children: [UKPageMenuCommand] = [],
        perform: (() -> Void)? = nil
    ) {
        self.identifier = identifier
        self.title = title
        self.isEnabled = isEnabled
        self.state = state
        self.children = children
        self.perform = perform
    }

    var isSubmenu: Bool { !children.isEmpty || perform == nil }
}

/// A page that offers tools. Implement it on a section root or a pushed page; call
/// ``UIKit/UIViewController/ukPageToolsDidChange()`` when ``ukPageTools`` changes.
@MainActor
protocol UKPageToolsProviding: UIViewController {
    /// The page's tools, any order.
    var ukPageTools: [UKPageTool] { get }
    /// Whether the page shows the notifications bell (some pages hide it).
    var ukShowsNotifications: Bool { get }
    /// Whether the page's tools stay in the navigation bar even where tools float above the
    /// tab bar (Suggestions' Filter: its SwiftUI page keeps it in the bar row).
    var ukToolsStayInBar: Bool { get }

    /// Fixed page-command families for the iPadOS menu bar.
    var ukPageMenuCommands: [UKPageMenuCommand] { get }
    /// DEBUG-only render evidence for the menu mirror; never a command state source.
    var ukDebugMenuTrace: String? { get }
}

extension UKPageToolsProviding {
    var ukShowsNotifications: Bool { true }
    var ukToolsStayInBar: Bool { false }
    var ukPageMenuCommands: [UKPageMenuCommand] { [] }
    var ukDebugMenuTrace: String? { nil }
}

extension UIViewController {
    /// The shell that owns this page, found through the controller hierarchy.
    var ukShell: UKRootViewController? {
        var current: UIViewController? = self
        while let controller = current {
            if let root = controller as? UKRootViewController { return root }
            current = controller.parent ?? controller.presentingViewController
        }
        return nil
    }

    /// Tells the shell the page's tools changed.
    func ukPageToolsDidChange() { ukShell?.refreshChrome() }

    /// Puts the notifications bell and the profile button on this (pushed) page's
    /// navigation bar, before the page's own tools: the UIKit `pageTrailingItems()`.
    func ukInstallAccountItems() { ukShell?.installAccountChrome(on: self) }
}
#endif
