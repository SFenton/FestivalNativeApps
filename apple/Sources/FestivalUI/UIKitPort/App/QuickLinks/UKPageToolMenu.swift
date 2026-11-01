#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Choices

/// One choice of a page tool's compact sheet: the UIKit ``PageToolMenuChoice``.
struct UKPageToolChoice {
    /// Accessibility identifier of the row (`fst.quick-links.item.<id>`).
    let identifier: String
    /// Visible title, indented by depth with figure spaces.
    let title: String
    /// What VoiceOver reads (no indent).
    let spokenTitle: String
    /// The leading glyph, or nil for none.
    let icon: QuickLinkIcon?
    /// Whether the row is the current choice.
    let isSelected: Bool
    /// What picking it does; runs once the sheet has closed.
    let action: () -> Void
}

/// A page tool that opens a compact choice sheet from the iPhone floating tool instead of a
/// menu (the approved Quick Links variant, `quick-links` R5, issues #92, #632).
struct UKPageToolSheet {
    /// The sheet's inline title.
    let title: String
    /// The choices in page order, read when the sheet opens.
    let choices: () -> [UKPageToolChoice]
}

// MARK: - Metrics

/// Sizes of the sheet's row artwork, following the SwiftUI `QuickLinkLabel` list curve.
enum UKPageToolMenuMetrics {
    /// Instrument icon side at the default size (``InstrumentIcon/menuIconSide``).
    static let instrumentSide: CGFloat = 24
    /// Point size of the row symbols at the default size (20 pt tall ink in SwiftUI list rows).
    static let symbolPointSize: CGFloat = 17
    /// Minimum row height (HIG Accessibility: 44 x 44 pt).
    static let minimumRowHeight: CGFloat = 44

    /// Scales a point value like the SwiftUI list row's symbols: with body text up to
    /// xxxLarge, held across xxxLarge...AX3, then with body text again (measured on iOS 26
    /// `List` rows; `QuickLinkLabel.symbolPlateau`).
    ///
    /// - Parameters:
    ///   - value: The size at the default text size.
    ///   - traits: The trait collection supplying the text size.
    /// - Returns: The scaled size in points.
    static func scaled(_ value: CGFloat, traits: UITraitCollection) -> CGFloat {
        let metrics = UIFontMetrics(forTextStyle: .body)
        func at(_ category: UIContentSizeCategory, _ v: CGFloat) -> CGFloat {
            metrics.scaledValue(for: v, compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
        }
        let category = traits.preferredContentSizeCategory
        let lower = UIContentSizeCategory.extraExtraExtraLarge
        let upper = UIContentSizeCategory.accessibilityLarge
        if category <= lower { return at(category, value) }
        let plateau = at(lower, value)
        if category <= upper { return plateau }
        return plateau * at(category, 17) / at(upper, 17)
    }
}

// MARK: - Sheet

/// The compact sheet a floating page tool opens: a list of choices, the current one selected;
/// picking one closes the sheet and then runs it. The UIKit counterpart of
/// ``PageToolInlineMenuSheet``; Quick Links is its first user.
///
/// HIG route (`hig_route.py`: sheet, list, accessibility): sheets (a medium detent with a
/// grabber that expands to large), lists and tables (44 pt rows) and accessibility
/// (selected state, larger text).
@MainActor
final class UKPageToolMenuViewController: UIViewController, UICollectionViewDelegate, UKModalScrollProviding {
    /// Identifier of the sheet's Close button.
    static let closeIdentifier = "fst.page-tools.menu.close"

    private let choices: [UKPageToolChoice]
    private var collection: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Int, Int>!
    private var picked = false

    var ukModalScrollView: UIScrollView? { collection }

    /// Creates the sheet's content.
    ///
    /// - Parameter choices: The choices in order.
    init(choices: [UKPageToolChoice]) {
        self.choices = choices
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Presents the sheet from `presenter`.
    ///
    /// - Parameters:
    ///   - sheet: The tool's sheet description.
    ///   - presenter: The controller to present from.
    static func present(_ sheet: UKPageToolSheet, from presenter: UIViewController) {
        guard presenter.presentedViewController == nil else { return }
        let content = UKPageToolMenuViewController(choices: sheet.choices())
        let sheet = UKSheet.make(content, title: sheet.title, closeIdentifier: closeIdentifier, size: .compact)
        // Like every SwiftUI Festival sheet (`FestivalSheetModifier`) it opens at the large detent,
        // where the glass is opaque and the title keeps its contrast; the medium detent stays as
        // the step down.
        sheet.sheetPresentationController?.selectedDetentIdentifier = .large
        presenter.present(sheet, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        var configuration = UICollectionLayoutListConfiguration(appearance: .insetGrouped)
        configuration.backgroundColor = .clear
        configuration.showsSeparators = true
        let layout = UICollectionViewCompositionalLayout.list(using: configuration)
        collection = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collection.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        collection.backgroundColor = .clear
        collection.delegate = self
        view.addSubview(collection)
        let choices = choices
        let registration = UICollectionView.CellRegistration<UKPageToolMenuCell, Int> { cell, _, index in
            cell.configure(choices[index])
            var background = UIBackgroundConfiguration.listGroupedCell()
            background.backgroundColor = BrandUIColors.cardBackground
            cell.backgroundConfiguration = background
        }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collection) { collection, path, index in
            collection.dequeueConfiguredReusableCell(using: registration, for: path, item: index)
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems(Array(choices.indices))
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        pick(indexPath.item)
    }

    /// Closes the sheet, then runs the choice so a sheet it presents never collides with this one.
    private func pick(_ index: Int) {
        guard !picked, choices.indices.contains(index) else { return }
        picked = true
        let action = choices[index].action
        (navigationController ?? self).dismiss(animated: true) { action() }
    }
}

// MARK: - Cell

/// One row: glyph, title, checkmark. The row's accessibility stop is a proxy view so it reads
/// as a button (a list cell reads as `Cell`).
@MainActor
private final class UKPageToolMenuCell: UICollectionViewListCell {
    private let icon = UIImageView()
    private let iconColumn = UIView()
    private let title = UILabel()
    private let check = UIImageView(image: UIImage(systemName: "checkmark"))
    private let proxy = UKRowAccessibilityView()
    private var current: UKPageToolChoice?
    private var iconWidth: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = false
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconColumn.addSubview(icon)
        title.font = UIFont.preferredFont(forTextStyle: .body)
        title.adjustsFontForContentSizeCategory = true
        title.numberOfLines = 0
        title.textColor = BrandUIColors.textPrimary
        check.tintColor = BrandUIColors.accentBlue
        check.setContentHuggingPriority(.required, for: .horizontal)
        check.setContentCompressionResistancePriority(.required, for: .horizontal)
        check.isAccessibilityElement = false
        let row = UIStackView(arrangedSubviews: [iconColumn, title, check])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)
        iconWidth = iconColumn.widthAnchor.constraint(equalToConstant: 28)
        let minimum = row.heightAnchor.constraint(greaterThanOrEqualToConstant: UKPageToolMenuMetrics.minimumRowHeight)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            row.leadingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.layoutMarginsGuide.trailingAnchor),
            minimum, iconWidth,
            icon.centerXAnchor.constraint(equalTo: iconColumn.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconColumn.centerYAnchor),
            iconColumn.heightAnchor.constraint(equalTo: icon.heightAnchor),
        ])
        contentView.addSubview(proxy)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows a choice.
    func configure(_ choice: UKPageToolChoice) {
        current = choice
        title.text = choice.title
        check.isHidden = !choice.isSelected
        var traits: UIAccessibilityTraits = [.button]
        if choice.isSelected { traits.insert(.selected) }
        proxy.set(identifier: choice.identifier, label: choice.spokenTitle, traits: traits, frame: bounds)
        applyIcon()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        proxy.frame = bounds
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        applyIcon()
    }

    private func applyIcon() {
        guard let choice = current else { return }
        let traits = traitCollection
        switch choice.icon {
        case let .system(name)?:
            let side = UKPageToolMenuMetrics.scaled(UKPageToolMenuMetrics.symbolPointSize, traits: traits)
            icon.image = UIImage(
                systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: side, weight: .regular, scale: .large)
            )
            icon.tintColor = BrandUIColors.textPrimary
        case let .instrument(instrument)?:
            let side = UKPageToolMenuMetrics.scaled(UKPageToolMenuMetrics.instrumentSide, traits: traits)
            icon.image = InstrumentIcon.menuPlatformImage(for: instrument, keyboard: false, side: side)
        case nil:
            icon.image = nil
        }
        iconColumn.isHidden = choice.icon == nil
        iconWidth.constant = UKPageToolMenuMetrics.scaled(UKPageToolMenuMetrics.instrumentSide + 4, traits: traits).rounded()
    }
}
#endif
