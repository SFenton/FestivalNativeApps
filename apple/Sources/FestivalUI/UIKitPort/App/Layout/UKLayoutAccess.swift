#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Layout for pages

extension UIViewController {
    /// The window layout the shell last published (pose, hinge, section chrome, cutout-safe
    /// insets), or ``DeviceLayout/standardPhone`` outside a shell (a test host).
    var ukWindowLayout: DeviceLayout { ukShell?.layout ?? .standardPhone }

    /// The section stack this page sits in, if any.
    var ukSectionStack: UKSectionStack? {
        var current: UIViewController? = self
        while let controller = current {
            if let stack = controller as? UKSectionStack { return stack }
            current = controller.parent
        }
        return nil
    }

    /// Which half of an on-demand split this page is in; nil in one full-width stack.
    var ukSplitPane: SplitPaneRole? {
        guard let stack = ukSectionStack, stack.geometry != nil else { return nil }
        var current: UIViewController? = self
        while let controller = current {
            if controller === stack.trailing { return .trailing }
            if controller === stack.leading { return .leading }
            current = controller.parent
        }
        return nil
    }

    /// The layout this page should adapt to: the window layout, re-classified by the pane's
    /// own width while it sits in one half of an on-demand split (`SplitPaneContext`), so a
    /// ~400 pt pane never picks two card columns from the window's regular size class.
    var ukLayout: DeviceLayout {
        let layout = ukWindowLayout
        guard ukSplitPane != nil, let navigation = navigationController, navigation.view.bounds.width > 0 else {
            return layout
        }
        return layout.column(width: navigation.view.bounds.width)
    }

    /// The list page's detail route currently open in the trailing pane, for row highlights.
    var ukOpenDetail: AppRoute? {
        guard let stack = ukSectionStack, stack.isDetailOpen else { return nil }
        return OnDemandSplitPolicy.cut(section: stack.section, path: stack.path)?.selection
    }
}

// MARK: - Hinge columns

/// Hinge-aware two-column placement for pages (the UIKit counterpart of ``HingeRow`` /
/// ``HingeGrid``): the pure ``HingeColumns`` maths over a UIKit view's frame.
@MainActor
enum UKHinge {
    /// The band a vertical fold makes across a view, in the view's own coordinates.
    ///
    /// - Parameters:
    ///   - view: The container.
    ///   - layout: The window layout.
    ///   - gutter: Smallest gap between columns.
    ///   - minimumSide: Narrowest column either side of the fold.
    /// - Returns: The leading width, fold clearance and trailing width, or nil when no vertical
    ///   fold crosses the view (flat, folded, or too narrow): lay out without a fold.
    static func band(in view: UIView, layout: DeviceLayout, gutter: CGFloat, minimumSide: CGFloat = HingeColumns.minimumSide) -> HingeBand? {
        guard let fold = layout.splitHinge, view.window != nil else { return nil }
        let frame = view.convert(view.bounds, to: nil)
        return HingeColumns.band(span: HorizontalSpan(frame), fold: fold, gutter: gutter, minimumSide: minimumSide)
    }
}

/// Two columns that meet at a book-pose fold, or split evenly otherwise: the container the
/// feature lanes place paired cards and list/detail halves in.
@MainActor
final class UKHingeColumnsView: UIView {
    /// The leading half.
    let leadingContent = UIView()
    /// The trailing half.
    let trailingContent = UIView()
    /// Spacing between the columns when no fold divides them.
    var spacing: CGFloat = 12 { didSet { setNeedsLayout() } }
    /// The window layout provider.
    var layoutProvider: () -> DeviceLayout = { .standardPhone } { didSet { setNeedsLayout() } }

    /// Creates the container.
    init() {
        super.init(frame: .zero)
        addSubview(leadingContent)
        addSubview(trailingContent)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let rtl = effectiveUserInterfaceLayoutDirection == .rightToLeft
        let leadingWidth: CGFloat
        let gap: CGFloat
        if let band = UKHinge.band(in: self, layout: layoutProvider(), gutter: spacing) {
            leadingWidth = band.leadingWidth
            gap = band.gap
        } else {
            gap = spacing
            leadingWidth = (width - gap) / 2
        }
        let trailingWidth = max(0, width - leadingWidth - gap)
        let first = CGRect(x: rtl ? width - leadingWidth : 0, y: 0, width: leadingWidth, height: bounds.height)
        let second = CGRect(x: rtl ? 0 : leadingWidth + gap, y: 0, width: trailingWidth, height: bounds.height)
        leadingContent.frame = first
        trailingContent.frame = second
    }
}
#endif
