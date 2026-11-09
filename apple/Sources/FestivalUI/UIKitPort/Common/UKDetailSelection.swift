#if os(iOS)
import FestivalCore
import UIKit

nonisolated(unsafe) private var detailSelectionKey: UInt8 = 0

extension UIView {
    /// Keeps native row/control selection aligned with the current split detail route.
    ///
    /// - Parameters:
    ///   - route: The detail destination this row opens.
    ///   - context: The owning page/window context.
    @MainActor
    func ukBindDetailSelection(_ route: AppRoute, context: UKContext) {
        let binding = UKDetailSelectionBinding(view: self, route: route, context: context)
        objc_setAssociatedObject(self, &detailSelectionKey, binding, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Removes a reused view's previous split-detail owner.
    @MainActor
    func ukClearDetailSelection() {
        guard objc_getAssociatedObject(self, &detailSelectionKey) != nil else { return }
        objc_setAssociatedObject(self, &detailSelectionKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        (self as? UIControl)?.isSelected = false
        accessibilityTraits.remove(.selected)
    }

    /// Restores selection after a row reapplies its other accessibility traits.
    @MainActor
    func ukRefreshDetailSelection() {
        (objc_getAssociatedObject(self, &detailSelectionKey) as? UKDetailSelectionBinding)?.refresh()
    }
}

@MainActor
private final class UKDetailSelectionBinding {
    private weak var view: UIView?
    private weak var shell: UKShellState?
    private let route: AppRoute
    private let section: FestivalSection?
    private let isPage: Bool
    private var observation: UKObservation?

    init(view: UIView, route: AppRoute, context: UKContext) {
        self.view = view
        shell = context.shell
        self.route = route
        section = context.section
        isPage = context.surface == .page
        observation = UKObservation { [weak self] in self?.refresh() }
    }

    func refresh() {
        guard let view else { return }
        let selected = isPage && section != nil && shell?.selectedSection == section
            && shell?.splitOpen == true && shell?.detailSelection == route
        if let control = view as? UIControl, control.isSelected != selected { control.isSelected = selected }
        if selected { view.accessibilityTraits.insert(.selected) }
        else { view.accessibilityTraits.remove(.selected) }
    }
}
#endif
