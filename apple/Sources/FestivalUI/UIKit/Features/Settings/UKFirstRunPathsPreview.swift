#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

/// The Song Info Paths lesson reuses the viewer's selector row without actions or a load task.
final class UKFirstRunPathsPreview: UIView {
    let path = UIView()
    let selectors = UIView()
    private let layout: () -> DeviceLayout
    private var lastLayout: DeviceLayout?
    private var selectorRow: UIView?

    /// - Parameter layout: The window layout provider, including Duo poses.
    init(layout: @escaping () -> DeviceLayout) {
        self.layout = layout
        super.init(frame: .zero)
        clipsToBounds = true
        let card = UKCardView(cornerRadius: 16)
        path.backgroundColor = BrandUIColors.surfaceMuted
        path.layer.cornerRadius = 12
        path.layer.cornerCurve = .continuous
        let icon = UIImageView(image: UIImage(systemName: "point.topleft.down.curvedto.point.bottomright.up"))
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.title2))
        icon.tintColor = BrandUIColors.textPrimary
        icon.contentMode = .scaleAspectFit
        let caption = UKLabel("Path Preview", style: .caption1, lines: 1)
        let placeholder = UIStackView(arrangedSubviews: [icon, caption])
        placeholder.axis = .vertical
        placeholder.alignment = .center
        placeholder.spacing = 6
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        path.addSubview(placeholder)
        let stack = UIStackView(arrangedSubviews: [path, selectors])
        stack.axis = .vertical
        stack.spacing = 10
        card.contentView.ukPin(stack, insets: UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14))
        addSubview(card)
        let fill = card.heightAnchor.constraint(equalTo: heightAnchor)
        fill.priority = .defaultHigh
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor), card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor), fill,
            path.heightAnchor.constraint(greaterThanOrEqualToConstant: 90),
            placeholder.centerXAnchor.constraint(equalTo: path.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: path.centerYAnchor),
        ])
        refreshSelector()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKFirstRunPathsPreview, _) in
            self.refreshSelector()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if lastLayout != layout() { refreshSelector() }
    }

    private func refreshSelector() {
        let current = layout()
        lastLayout = current
        selectorRow?.removeFromSuperview()
        let row = UKSongPathsSelectorRow.make(
            instrument: .lead, difficulty: .expert,
            mode: SongPathsPolicy.resolve(.image, layout: current, fallback: .image),
            instruments: FirstRunSongInfoPathsDemo.instruments,
            songUsesKeyboardIcon: false, traits: traitCollection, layout: layout
        )
        selectors.ukPin(row)
        selectorRow = row
    }
}
#endif
