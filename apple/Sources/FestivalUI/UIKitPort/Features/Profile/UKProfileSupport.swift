#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Width-dependent views

/// A view whose content depends on the width it is given (column counts, chart paging,
/// stacked-or-side-by-side rows). The parent tells it the width before Auto Layout sizes it,
/// so the first frame already has its final shape (the SwiftUI custom `Layout`s read the
/// proposed width in the same pass; UIKit has no equivalent, so the width is passed down).
@MainActor
protocol UKWidthDependent: AnyObject {
    /// The width the view will be laid out at.
    ///
    /// - Parameter width: The view's width in points.
    func prepare(width: CGFloat)
}

// MARK: - View helpers

extension UIView {
    /// Adds `child` and pins it to this view's edges.
    ///
    /// - Parameters:
    ///   - child: The view to add.
    ///   - insets: Distance from each edge.
    func ukPin(_ child: UIView, insets: UIEdgeInsets = .zero) {
        child.translatesAutoresizingMaskIntoConstraints = false
        addSubview(child)
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            child.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
            child.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            child.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
        ])
    }

    /// Makes the view a labelled container XCUITest and VoiceOver can find while its children
    /// stay separate elements (`.accessibilityElement(children: .contain)` plus an identifier).
    ///
    /// - Parameters:
    ///   - identifier: Accessibility identifier.
    ///   - label: Optional spoken name.
    func ukContain(identifier: String, label: String? = nil) {
        isAccessibilityElement = false
        accessibilityContainerType = .semanticGroup
        accessibilityIdentifier = identifier
        accessibilityLabel = label
    }

    /// Forwards a width to this view and every descendant that depends on it, top down.
    ///
    /// - Parameter width: The width this view is laid out at.
    func ukPrepare(width: CGFloat) {
        (self as? UKWidthDependent)?.prepare(width: width)
    }
}

// MARK: - Settings

/// Boolean settings read the way `@AppStorage` does: `UserDefaults.bool(forKey:)` once a value
/// exists, so a launch argument (`-key YES`, stored as a string) counts, with the registered
/// default otherwise (``UKSettings/bool(_:default:)`` only accepts a stored `Bool`).
@MainActor
enum UKProfileSettings {
    /// A Boolean setting.
    ///
    /// - Parameters:
    ///   - key: The `fst.*` key.
    ///   - fallback: The value when nothing is stored.
    /// - Returns: The stored or default value.
    static func bool(_ key: String, default fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) == nil ? fallback : UserDefaults.standard.bool(forKey: key)
    }
}

// MARK: - Metrics

/// Page metrics shared by the lane's screens.
enum UKProfileMetrics {
    /// Padding around the page content (`.padding(16)`).
    static let pagePadding: CGFloat = 16
    /// Space between the page's sections (`VStack(spacing: 20)`).
    static let sectionSpacing: CGFloat = 20
    /// The text inset of a section header inside the page column (`.padding(.horizontal, 4)`).
    static let headerInset: CGFloat = 4
    /// Band row card corner radius.
    static let rowCornerRadius: CGFloat = 12
}

// MARK: - Inset wrapper

/// Wraps a view with horizontal padding (`.padding(.horizontal, n)`), forwarding widths.
final class UKProfileInset: UIView, UKWidthDependent {
    private let child: UIView
    private let horizontal: CGFloat

    /// Creates the wrapper.
    ///
    /// - Parameters:
    ///   - child: The wrapped view.
    ///   - horizontal: Padding on both sides.
    ///   - bottom: Extra space below the child.
    init(_ child: UIView, horizontal: CGFloat, bottom: CGFloat = 0) {
        self.child = child
        self.horizontal = horizontal
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        ukPin(child, insets: UIEdgeInsets(top: 0, left: horizontal, bottom: bottom, right: horizontal))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func prepare(width: CGFloat) { child.ukPrepare(width: max(0, width - 2 * horizontal)) }
}

// MARK: - Vertical section

/// A vertical stack that forwards its width to its arranged subviews: a page section.
final class UKProfileSection: UIStackView, UKWidthDependent {
    /// Creates a section.
    ///
    /// - Parameters:
    ///   - views: The arranged subviews, top to bottom.
    ///   - spacing: Space between them.
    init(_ views: [UIView], spacing: CGFloat) {
        super.init(frame: .zero)
        axis = .vertical
        alignment = .fill
        self.spacing = spacing
        translatesAutoresizingMaskIntoConstraints = false
        views.forEach(addArrangedSubview)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func prepare(width: CGFloat) { arrangedSubviews.forEach { $0.ukPrepare(width: width) } }
}

// MARK: - Notice row

/// One gold footnote row of the notices card: the row is the accessibility element (its frame
/// is the card row, the text column sits inside the 16 x 6 pt padding), spoken as its text.
final class UKProfileNoticeRow: UIView {
    /// Creates the row.
    ///
    /// - Parameters:
    ///   - text: The message.
    ///   - identifier: Accessibility identifier.
    init(text: String, identifier: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let label = UKLabel(text, style: .footnote, color: BrandUIColors.gold)
        // Break lines like `NSString.boundingRect` / SwiftUI `Text`, not with the UILabel default strategy.
        label.lineBreakStrategy = []
        ukPin(label, insets: UIEdgeInsets(top: 6, left: 16, bottom: 6, right: 16))
        heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        isAccessibilityElement = true
        accessibilityLabel = text
        accessibilityTraits = .staticText
        accessibilityIdentifier = identifier
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Width host

/// A container that remembers the width it was prepared at and forwards it to its content:
/// a section whose content is swapped as reads settle (a card that shows a spinner, a chart
/// or an error).
final class UKProfileHost: UIView, UKWidthDependent {
    /// The width the host was last prepared at.
    private(set) var width: CGFloat = 0

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func prepare(width: CGFloat) {
        self.width = width
        subviews.forEach { $0.ukPrepare(width: width) }
    }
}

// MARK: - Column grid

/// Equal-height-or-natural-height rows of cells in side-by-side columns, with the centre
/// gutter on an iPhone Duo fold while it is in book pose (``HingeGrid`` / ``HingeEagerGrid``
/// and the stat-tile grid's custom layout in one view).
///
/// The column count comes from the width the parent passes to ``prepare(width:)``; cells are
/// pinned to constant column widths, so nested self-sizing views measure exactly.
final class UKProfileColumnGrid: UIView, UKWidthDependent {
    /// How the column count is chosen.
    enum Columns: Equatable {
        /// A fixed count, split evenly (two flexible columns).
        case fixed(Int)
        /// The stat-tile grid's adaptive rule (``StatGridColumns``).
        case stat(minimumTile: Double, minimumColumns: Int)
        /// As many columns of at least this width as fit.
        case adaptive(minimum: CGFloat)
    }

    private struct Plan: Equatable {
        var offsets: [CGFloat]
        var widths: [CGFloat]
    }

    /// Column rule; changing it re-plans at the current width.
    var columns: Columns { didSet { if columns != oldValue { replan(force: true) } } }
    /// The window layout provider (for the Duo fold).
    var layoutProvider: () -> DeviceLayout = { .standardPhone }
    private let spacing: CGFloat
    private let rowSpacing: CGFloat
    private let stretches: Bool
    private let rows = UIStackView()
    private var cells: [UIView] = []
    private var plan: Plan?
    private var width: CGFloat = 0
    private var active: [NSLayoutConstraint] = []

    /// Creates a grid.
    ///
    /// - Parameters:
    ///   - columns: The column rule.
    ///   - spacing: Gap between columns (and the narrowest clearance over a fold).
    ///   - rowSpacing: Gap between rows; defaults to `spacing`.
    ///   - stretchesCells: Whether every cell fills its row's height (tiles) or keeps its own.
    init(columns: Columns, spacing: CGFloat, rowSpacing: CGFloat? = nil, stretchesCells: Bool = false) {
        self.columns = columns
        self.spacing = spacing
        self.rowSpacing = rowSpacing ?? spacing
        self.stretches = stretchesCells
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        rows.axis = .vertical
        rows.spacing = self.rowSpacing
        ukPin(rows)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Replaces the cells.
    ///
    /// - Parameter newCells: The views, in reading order.
    func setCells(_ newCells: [UIView]) {
        cells = newCells
        replan(force: true)
    }

    func prepare(width: CGFloat) {
        self.width = width
        replan(force: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A fold only shows once the grid has a frame in the window.
        if bounds.width > 0, abs(bounds.width - width) < 1 { replan(force: false) }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { replan(force: false) }
    }

    private func hingeBand(minimumSide: CGFloat) -> HingeBand? {
        guard bounds.width > 0, abs(bounds.width - width) < 1 else { return nil }
        guard let band = UKHinge.band(in: self, layout: layoutProvider(), gutter: spacing, minimumSide: minimumSide) else { return nil }
        return abs(band.width - width) < 1 ? band : nil
    }

    private func makePlan(width: CGFloat) -> Plan {
        guard width > 0 else { return Plan(offsets: [0], widths: [0]) }
        let count: Int
        let band: HingeBand?
        let perSide: HingeColumns.PerSide
        switch columns {
        case let .fixed(fixed):
            count = max(1, fixed)
            band = count >= 2 ? hingeBand(minimumSide: HingeColumns.minimumSide) : nil
            perSide = .columns(max(1, count / 2))
        case let .stat(minimumTile, minimumColumns):
            count = StatGridColumns.count(
                forWidth: Double(width), minimumTileWidth: minimumTile, spacing: Double(spacing), minimumColumns: minimumColumns
            )
            band = hingeBand(minimumSide: max(CGFloat(minimumTile), HingeColumns.minimumSide))
            perSide = .fit(minimum: CGFloat(minimumTile))
        case let .adaptive(minimum):
            count = HingeColumns.fitCount(width: width, minimum: minimum, spacing: spacing)
            band = count >= 2 ? hingeBand(minimumSide: HingeColumns.minimumSide) : nil
            perSide = .fit(minimum: minimum)
        }
        if let band {
            let spec = HingeColumns.spec(band: band, spacing: spacing, perSide: perSide)
            return Plan(offsets: spec.offsets, widths: spec.widths)
        }
        let each = max(0, (width - spacing * CGFloat(count - 1)) / CGFloat(count))
        return Plan(offsets: (0..<count).map { CGFloat($0) * (each + spacing) }, widths: Array(repeating: each, count: count))
    }

    private func replan(force: Bool) {
        let next = makePlan(width: width)
        guard force || next != plan else { return }
        plan = next
        rebuild(next)
    }

    private func rebuild(_ plan: Plan) {
        NSLayoutConstraint.deactivate(active)
        active.removeAll()
        for row in rows.arrangedSubviews {
            rows.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        let count = max(1, plan.widths.count)
        for start in stride(from: 0, to: cells.count, by: count) {
            let row = UIView()
            row.translatesAutoresizingMaskIntoConstraints = false
            for (offset, cell) in cells[start ..< min(start + count, cells.count)].enumerated() {
                cell.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(cell)
                active += [
                    cell.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: plan.offsets[offset]),
                    cell.widthAnchor.constraint(equalToConstant: plan.widths[offset]),
                    cell.topAnchor.constraint(equalTo: row.topAnchor),
                    stretches
                        ? cell.bottomAnchor.constraint(equalTo: row.bottomAnchor)
                        : cell.bottomAnchor.constraint(lessThanOrEqualTo: row.bottomAnchor),
                ]
                cell.ukPrepare(width: plan.widths[offset])
            }
            rows.addArrangedSubview(row)
        }
        NSLayoutConstraint.activate(active)
    }
}

// MARK: - Purple action

/// The purple "View All ..." button that ends a card of preview rows (``PurpleActionLink``
/// inside a ``FestivalGlassSection``): a flat accent-purple fill, white semibold text, 44 pt
/// minimum, 12 pt corners, spoken as its title and the card it opens.
final class UKProfilePurpleActionButton: UIControl {
    private let label: UKLabel
    /// Called when tapped.
    var onTap: (() -> Void)?

    /// Creates the button.
    ///
    /// - Parameters:
    ///   - title: Visible Title Case label.
    ///   - identifier: Accessibility identifier.
    ///   - card: The card it opens, spoken after the title.
    init(title: String, identifier: String, card: String?) {
        label = UKLabel(title, style: .body, weight: .semibold, lines: 0, alignment: .center)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = BrandUIColors.accentPurple
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        label.isUserInteractionEnabled = false
        ukPin(label, insets: UIEdgeInsets(top: 2, left: 12, bottom: 2, right: 12))
        heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = PurpleActionName.spoken(title, card: card)
        accessibilityIdentifier = identifier
        addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet { label.alpha = isHighlighted ? 0.6 : 1 }
    }
}

// MARK: - Chevron row

/// A label-and-chevron navigation row (a `NavigationLink` over `HStack(Text, Spacer, Image)`):
/// one button element, the chevron decorative.
final class UKProfileChevronRow: UIControl {
    private let label: UKLabel
    private let chevron = UIImageView(image: UIImage(systemName: "chevron.forward"))
    /// Called when tapped.
    var onTap: (() -> Void)?

    /// Creates the row.
    ///
    /// - Parameters:
    ///   - title: Row text.
    ///   - identifier: Accessibility identifier.
    init(title: String, identifier: String) {
        label = UKLabel(title, style: .body)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        label.isUserInteractionEnabled = false
        chevron.tintColor = BrandUIColors.textMuted
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.footnote, weight: .semibold))
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)
        chevron.isUserInteractionEnabled = false
        chevron.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        addSubview(chevron)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            chevron.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 8),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
        accessibilityIdentifier = identifier
        addAction(UIAction { [weak self] _ in self?.onTap?() }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }
}

// MARK: - Retry button

/// The caption-sized Retry control beside an inline failure line.
final class UKProfileRetryButton: UIButton {
    /// Creates the button.
    ///
    /// - Parameter onTap: Retry action.
    init(onTap: @escaping () -> Void) {
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Retry"
        configuration.baseForegroundColor = UKAccentText.blue
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { container in
            var container = container
            container.font = UKFont.font(.caption1, weight: .semibold)
            return container
        }
        self.configuration = configuration
        heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        translatesAutoresizingMaskIntoConstraints = false
        addAction(UIAction { _ in onTap() }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
