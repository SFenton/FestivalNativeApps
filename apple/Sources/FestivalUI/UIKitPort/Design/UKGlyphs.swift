#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Instrument icon

/// A bundled instrument icon (``InstrumentIcon``): the artwork in a fixed square, high
/// interpolation, spoken as the instrument's label unless ``hidesFromAccessibility``.
final class UKInstrumentIconView: UIImageView {
    /// The instrument drawn.
    private(set) var instrument: Instrument
    private let side: CGFloat

    /// Creates an icon.
    ///
    /// - Parameters:
    ///   - instrument: The instrument.
    ///   - keyboard: Draw the keys variant of Lead and Pro Lead.
    ///   - size: Edge length in points.
    ///   - hidesFromAccessibility: Decorative use beside a text label.
    init(_ instrument: Instrument, keyboard: Bool = false, size: CGFloat = 20, hidesFromAccessibility: Bool = false) {
        self.instrument = instrument
        self.side = size
        super.init(frame: .zero)
        contentMode = .scaleAspectFit
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        image = Self.image(for: instrument, keyboard: keyboard)
        isAccessibilityElement = !hidesFromAccessibility
        accessibilityLabel = instrument.label
        accessibilityTraits = .image
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The bundled artwork.
    ///
    /// - Parameters:
    ///   - instrument: The instrument.
    ///   - keyboard: The keys variant of Lead and Pro Lead.
    /// - Returns: The image, or nil when the asset is missing.
    static func image(for instrument: Instrument, keyboard: Bool = false) -> UIImage? {
        UIImage(named: InstrumentIcon.assetName(for: instrument, keyboard: keyboard), in: .module, compatibleWith: nil)
    }
}

/// A row of non-spoken icons (``InstrumentIconRow``).
final class UKInstrumentIconRow: UIStackView {
    /// Creates a row.
    ///
    /// - Parameters:
    ///   - instruments: The instruments in order.
    ///   - side: Icon edge length.
    ///   - spacing: Gap between icons.
    init(instruments: [Instrument], side: CGFloat, spacing: CGFloat = 4) {
        super.init(frame: .zero)
        axis = .horizontal
        self.spacing = spacing
        alignment = .center
        for instrument in instruments {
            addArrangedSubview(UKInstrumentIconView(instrument, size: side, hidesFromAccessibility: true))
        }
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Star rating

/// A star rating (``StarRating``): one to five white stars, or five gold for a gold-star
/// result; the `mini` style draws each star in a circle with a gold ring. Sizes scale
/// with Dynamic Type relative to `.caption`, and the row is one element
/// ("3 stars", "5 gold stars").
final class UKStarRatingView: UIView {
    /// Spacing and size variant (``StarRating/Style``).
    typealias Style = StarRating.Style

    private let stack = UIStackView()
    private let count: Int
    private let isGold: Bool
    private let style: Style
    private let baseSize: CGFloat?
    private var starViews: [UIView] = []

    /// Creates the rating.
    ///
    /// - Parameters:
    ///   - stars: Earned stars; 6 or more, or `gold`, shows five gold stars.
    ///   - gold: Whether the result is a gold-star one.
    ///   - style: Inline or mini.
    ///   - size: Star edge length at the default type size.
    init(stars: Int, gold: Bool = false, style: Style = .inline, size: CGFloat? = nil) {
        let display = StarRating.display(stars: stars, gold: gold)
        count = display.count
        isGold = display.gold
        self.style = style
        baseSize = size
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isAccessibilityElement = true
        accessibilityLabel = StarRating.accessibilityLabel(count: count, gold: isGold)
        accessibilityTraits = .image
        rebuild()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKStarRatingView, _) in self.rebuild() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func rebuild() {
        starViews.forEach { $0.removeFromSuperview() }
        let scale = UKFont.scaled(1, relativeTo: .caption1, traits: traitCollection)
        let defaultSize: CGFloat = style == .inline ? 14 : 20
        let edge = (baseSize ?? defaultSize) * scale
        stack.spacing = (style == .inline ? 2 : 3) * scale
        starViews = (0..<count).map { _ in star(edge: edge) }
        starViews.forEach(stack.addArrangedSubview)
    }

    private func star(edge: CGFloat) -> UIView {
        let image = UIImageView(image: UIImage(named: StarRating.assetName(gold: isGold), in: .module, compatibleWith: nil))
        image.contentMode = .scaleAspectFit
        image.translatesAutoresizingMaskIntoConstraints = false
        switch style {
        case .inline:
            NSLayoutConstraint.activate([image.widthAnchor.constraint(equalToConstant: edge), image.heightAnchor.constraint(equalToConstant: edge)])
            return image
        case .mini:
            let circle = edge * 1.2
            let holder = UIView()
            holder.translatesAutoresizingMaskIntoConstraints = false
            holder.clipsToBounds = true
            holder.layer.cornerRadius = circle / 2
            holder.layer.borderWidth = isGold ? 1.5 : 0
            holder.layer.borderColor = BrandUIColors.gold.cgColor
            holder.addSubview(image)
            NSLayoutConstraint.activate([
                holder.widthAnchor.constraint(equalToConstant: circle), holder.heightAnchor.constraint(equalToConstant: circle),
                image.centerXAnchor.constraint(equalTo: holder.centerXAnchor), image.centerYAnchor.constraint(equalTo: holder.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: edge), image.heightAnchor.constraint(equalToConstant: edge),
            ])
            return holder
        }
    }
}

// MARK: - Difficulty meter

/// The website's seven 8 x 20 parallelograms with one-point spacing (``DifficultyMeter``),
/// drawn in Core Graphics; white for filled bars, grey after; mirrored in right-to-left
/// layouts. Spoken as "Difficulty 4 of 7"; a non-finite level shows "Difficulty
/// unavailable" text.
final class UKDifficultyMeterView: UIView {
    private let level: Double
    private let raw: Bool
    private let filled: Int
    private var unavailable: UILabel?

    /// Creates the meter.
    ///
    /// - Parameters:
    ///   - level: Numeric difficulty from the song model.
    ///   - raw: Whether the level is on the 0-6 raw scale.
    init(level: Double, raw: Bool = false) {
        self.level = level
        self.raw = raw
        filled = DifficultyMeter.filledBars(level: level, raw: raw)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        accessibilityIdentifier = "fst.songs.difficulty-meter"
        if level.isFinite {
            isAccessibilityElement = true
            accessibilityLabel = DifficultyMeter.accessibilityLabel(level: level, raw: raw)
            NSLayoutConstraint.activate([widthAnchor.constraint(equalToConstant: 62), heightAnchor.constraint(equalToConstant: 20)])
        } else {
            let label = UKLabel("Difficulty unavailable")
            label.accessibilityIdentifier = "fst.songs.difficulty-unavailable"
            addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: leadingAnchor), label.trailingAnchor.constraint(equalTo: trailingAnchor),
                label.topAnchor.constraint(equalTo: topAnchor), label.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            unavailable = label
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard level.isFinite, let context = UIGraphicsGetCurrentContext() else { return }
        if effectiveUserInterfaceLayoutDirection == .rightToLeft {
            context.translateBy(x: bounds.width, y: 0)
            context.scaleBy(x: -1, y: 1)
        }
        for index in 0..<7 {
            let x = CGFloat(index * 9)
            let bar = UIBezierPath()
            bar.move(to: CGPoint(x: x + 2, y: 0))
            bar.addLine(to: CGPoint(x: x + 8, y: 0))
            bar.addLine(to: CGPoint(x: x + 6, y: 20))
            bar.addLine(to: CGPoint(x: x, y: 20))
            bar.close()
            (index < filled ? UIColor.white : UIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1)).setFill()
            bar.fill()
        }
    }
}
#endif
