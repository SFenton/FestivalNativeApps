#if os(iOS)
import FestivalDesign
import UIKit

// MARK: - Rim

/// A card's 1 pt rim: a (possibly solid) top-to-bottom gradient cut to the card's border
/// by a bordered mask layer, so the gradient is drawn by the render server (the
/// ``CardRim`` rule, issue #553). It takes no touches and is hidden from accessibility.
final class UKRimView: UIView {
    private let gradient = CAGradientLayer()
    private let ring = CALayer()
    /// Corner radius; ignored while ``isCapsule``.
    var cornerRadius: CGFloat = 16 { didSet { setNeedsLayout() } }
    /// Whether the radius is half the height.
    var isCapsule = false { didSet { setNeedsLayout() } }
    /// How far the border extends past the top and bottom edges, so a group card's inner
    /// edges draw no line (`FestivalSegmentRim`).
    var overhang: (top: CGFloat, bottom: CGFloat) = (0, 0) { didSet { setNeedsLayout() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        clipsToBounds = true
        ring.borderWidth = 1
        ring.borderColor = UIColor.black.cgColor
        ring.cornerCurve = .continuous
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        gradient.mask = ring
        layer.addSublayer(gradient)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Sets the rim's colours, top to bottom (equal colours draw a solid rim).
    func setColors(top: UIColor, bottom: UIColor) {
        gradient.colors = [top.cgColor, bottom.cgColor]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        ring.frame = CGRect(
            x: 0, y: -overhang.top, width: bounds.width, height: bounds.height + overhang.top + overhang.bottom
        )
        ring.cornerRadius = isCapsule ? ring.bounds.height / 2 : cornerRadius
        CATransaction.commit()
    }
}

// MARK: - Material card

/// The shared material card (``View/festivalCard(cornerRadius:)``): an ultra-thin dark
/// material under a flat tint and a 1 pt rim, the opaque `cardBackground` + `borderSubtle`
/// card under Reduce Transparency or the in-app toggles, and the pre-26 frosted card
/// before iOS 26 (`FestivalCardModifier`). Put content in ``contentView``.
///
/// Group cards draw one row per card with a ``FestivalGroupSegment``: the fill takes the
/// segment's corners and the rim only its share (issue #543).
final class UKCardView: UIView {
    /// Where the card's content goes; sits above the fill and under the rim.
    let contentView = UIView()
    private let backdrop = UIView()
    private let blur = UIVisualEffectView(effect: nil)
    private let tint = UIView()
    private let rim = UKRimView()
    private var observer: UKAccessibilityObserver?

    /// Corner radius (the whole card's, for a segment).
    var cornerRadius: CGFloat { didSet { applyShape() } }
    /// The row's segment of a group card, or nil for a whole card.
    var segment: FestivalGroupSegment? { didSet { applyShape() } }
    /// A capsule card (floating controls and pills, ``View/festivalCardCapsule()``).
    var isCapsule: Bool { didSet { applyShape() } }
    /// Clips ``contentView`` to the card's corners (flush rows in a group card).
    var clipsContent = false { didSet { contentView.clipsToBounds = clipsContent; applyShape() } }

    /// Creates a card.
    ///
    /// - Parameters:
    ///   - cornerRadius: Continuous corner radius.
    ///   - segment: The row's segment of a group card, or nil.
    ///   - capsule: Draw a capsule instead of a rounded rectangle.
    init(cornerRadius: CGFloat = 16, segment: FestivalGroupSegment? = nil, capsule: Bool = false) {
        self.cornerRadius = cornerRadius
        self.segment = segment
        self.isCapsule = capsule
        super.init(frame: .zero)
        backdrop.isUserInteractionEnabled = false
        backdrop.clipsToBounds = true
        backdrop.layer.cornerCurve = .continuous
        backdrop.addSubview(blur)
        backdrop.addSubview(tint)
        for view in [backdrop, contentView, rim] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        contentView.layer.cornerCurve = .continuous
        NSLayoutConstraint.activate(
            [backdrop, contentView, rim].flatMap { view in
                [view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
                 view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor)]
            }
        )
        observer = UKAccessibilityObserver { [weak self] in self?.applySurface() }
        registerForTraitChanges([UITraitAccessibilityContrast.self]) { (self: UKCardView, _) in self.applySurface() }
        translatesAutoresizingMaskIntoConstraints = false
        applyShape()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = backdrop.bounds
        tint.frame = backdrop.bounds
        if isCapsule {
            let radius = bounds.height / 2
            backdrop.layer.cornerRadius = radius
            contentView.layer.cornerRadius = radius
        }
    }

    // MARK: Look

    private func applyShape() {
        let corners: CACornerMask
        let first = segment?.isFirst ?? true
        let last = segment?.isLast ?? true
        var mask: CACornerMask = []
        if first { mask.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if last { mask.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        corners = mask
        backdrop.layer.maskedCorners = corners
        contentView.layer.maskedCorners = corners
        if !isCapsule {
            backdrop.layer.cornerRadius = cornerRadius
            contentView.layer.cornerRadius = clipsContent ? cornerRadius : 0
        }
        rim.isCapsule = isCapsule
        rim.cornerRadius = cornerRadius
        if segment != nil {
            let overhang = cornerRadius + 2
            rim.overhang = (first ? 0 : overhang, last ? 0 : overhang)
        } else {
            rim.overhang = (0, 0)
        }
        applySurface()
        setNeedsLayout()
    }

    private func applySurface() {
        let increasedContrast = UKAccessibility.systemIncreasedContrast(traitCollection)
        if UKAccessibility.cardIsOpaque {
            blur.effect = nil
            tint.backgroundColor = BrandUIColors.cardBackground
            rim.setColors(top: BrandUIColors.borderSubtle, bottom: BrandUIColors.borderSubtle)
        } else if FestivalGlassSurface.glassAvailable {
            blur.effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            tint.backgroundColor = UKCardView.tint(increasedContrast: increasedContrast)
            if segment == nil || segment?.isFirst == true {
                rim.setColors(
                    top: UIColor.white.withAlphaComponent(RowCardStyle.rimTopOpacity),
                    bottom: UIColor.white.withAlphaComponent(RowCardStyle.rimBottomOpacity)
                )
            } else {
                let end = UIColor.white.withAlphaComponent(RowCardStyle.rimBottomOpacity)
                rim.setColors(top: end, bottom: end)
            }
        } else {
            blur.effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            tint.backgroundColor = BrandUIColors.surfaceFrosted
            rim.setColors(top: BrandUIColors.glassBorder, bottom: BrandUIColors.glassBorder)
        }
    }

    /// The iOS tint over the material (``RowCardStyle/tint(increasedContrast:)``).
    ///
    /// - Parameter increasedContrast: System Increase Contrast is on.
    static func tint(increasedContrast: Bool) -> UIColor {
        let rgb = RowCardStyle.tintRGB
        return UIColor(
            red: rgb.red, green: rgb.green, blue: rgb.blue,
            alpha: increasedContrast ? RowCardStyle.contrastTintOpacity : RowCardStyle.baseTintOpacity
        )
    }

    // MARK: Convenience

    /// Pins `view` inside ``contentView`` with insets.
    ///
    /// - Parameters:
    ///   - view: The content.
    ///   - insets: Padding on each side.
    func embed(_ view: UIView, insets: UIEdgeInsets = .zero) {
        view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: insets.left),
            view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -insets.right),
            view.topAnchor.constraint(equalTo: contentView.topAnchor, constant: insets.top),
            view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -insets.bottom),
        ])
    }
}

// MARK: - Glass

/// A Festival glass surface (``View/festivalGlass(_:cornerRadius:interactive:)``): system
/// Liquid Glass on iOS 26, the frosted material before it, and the opaque card under
/// Reduce Transparency or increased contrast, system or in-app (surface-materials R4).
/// Put content in ``contentView``.
final class UKGlassView: UIView {
    /// Where the surface's content goes.
    let contentView = UIView()
    private let effectView = UIVisualEffectView(effect: nil)
    private var observer: UKAccessibilityObserver?

    /// The surface role (tint and fallback opacity).
    var role: FestivalGlassRole { didSet { applySurface() } }
    /// Corner radius; ignored while ``isCapsule``.
    var cornerRadius: CGFloat { didSet { applyShape() } }
    /// A capsule surface (``View/festivalGlassCapsule(_:interactive:)``).
    var isCapsule: Bool { didSet { applyShape() } }
    /// Whether iOS 26 glass responds to touches.
    var isInteractive: Bool { didSet { applySurface() } }

    /// Creates a glass surface.
    ///
    /// - Parameters:
    ///   - role: Semantic role.
    ///   - cornerRadius: Continuous corner radius.
    ///   - capsule: Draw a capsule.
    ///   - interactive: Whether iOS 26 glass responds to touches.
    init(_ role: FestivalGlassRole = .card, cornerRadius: CGFloat = 16, capsule: Bool = false, interactive: Bool = false) {
        self.role = role
        self.cornerRadius = cornerRadius
        self.isCapsule = capsule
        self.isInteractive = interactive
        super.init(frame: .zero)
        effectView.isUserInteractionEnabled = true
        effectView.layer.cornerCurve = .continuous
        effectView.clipsToBounds = true
        effectView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effectView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentView)
        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: leadingAnchor), effectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            effectView.topAnchor.constraint(equalTo: topAnchor), effectView.bottomAnchor.constraint(equalTo: bottomAnchor),
            contentView.leadingAnchor.constraint(equalTo: leadingAnchor), contentView.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentView.topAnchor.constraint(equalTo: topAnchor), contentView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        observer = UKAccessibilityObserver { [weak self] in self?.applySurface() }
        registerForTraitChanges([UITraitAccessibilityContrast.self]) { (self: UKGlassView, _) in self.applySurface() }
        translatesAutoresizingMaskIntoConstraints = false
        applyShape()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        if isCapsule { effectView.layer.cornerRadius = bounds.height / 2 }
    }

    private func applyShape() {
        if !isCapsule { effectView.layer.cornerRadius = cornerRadius }
        applySurface()
        setNeedsLayout()
    }

    private func applySurface() {
        effectView.layer.borderWidth = 0
        effectView.backgroundColor = nil
        effectView.contentView.backgroundColor = nil
        switch UKAccessibility.glassSurface(traitCollection) {
        case .opaque:
            effectView.effect = nil
            effectView.backgroundColor = BrandUIColors.cardBackground
            effectView.layer.borderColor = BrandUIColors.borderSubtle.cgColor
            effectView.layer.borderWidth = 1
        case .glass:
            if #available(iOS 26.0, *) {
                let glass = UIGlassEffect(style: .regular)
                glass.isInteractive = isInteractive
                if let opacity = role.glassTintOpacity {
                    glass.tintColor = BrandUIColors.cardBackground.withAlphaComponent(opacity)
                }
                effectView.effect = glass
                effectView.cornerConfiguration = isCapsule
                    ? .capsule() : .uniformCorners(radius: .fixed(Double(cornerRadius)))
            }
        case .frosted:
            effectView.effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            let tint = role.frostedTint
            let base = tint.usesCardBackground ? BrandUIColors.cardBackground : BrandUIColors.surfaceFrosted
            // The tint sits over the material (`.background(tint).background(material)`).
            effectView.contentView.backgroundColor = base.withAlphaComponent(base.ukAlpha * tint.opacity)
            effectView.layer.borderColor = BrandUIColors.glassBorder.cgColor
            effectView.layer.borderWidth = 1
        }
    }
}

/// Groups adjacent glass surfaces so iOS 26 blends and morphs them
/// (``FestivalGlassGroup``); a plain container before iOS 26.
final class UKGlassGroupView: UIView {
    /// Where the glass-decorated children go.
    let contentView = UIView()

    /// Creates a group.
    ///
    /// - Parameter spacing: Distance at which neighbouring glass shapes start to merge.
    init(spacing: CGFloat? = nil) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let host: UIView
        if #available(iOS 26.0, *) {
            let container = UIGlassContainerEffect()
            if let spacing { container.spacing = spacing }
            let view = UIVisualEffectView(effect: container)
            host = view
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
                view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            view.contentView.addSubview(contentView)
        } else {
            host = self
            addSubview(contentView)
        }
        _ = host
        contentView.translatesAutoresizingMaskIntoConstraints = false
        guard let parent = contentView.superview else { return }
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: parent.leadingAnchor), contentView.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: parent.topAnchor), contentView.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

extension UIColor {
    /// The colour's alpha component.
    var ukAlpha: CGFloat {
        var alpha: CGFloat = 1
        getRed(nil, green: nil, blue: nil, alpha: &alpha)
        return alpha
    }
}
#endif
