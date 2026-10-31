#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Flow maths

/// Row wrapping for the Songs row's pills and chips: the arithmetic of ``SongMetadataFlow``
/// and ``SongChipRows`` over measured sizes, so a row can lay itself out by hand.
enum UKSongFlow {
    /// Wraps source-order sizes greedily, then balances the rows when more than one is needed.
    ///
    /// - Parameters:
    ///   - sizes: Each item's size.
    ///   - width: The available width.
    ///   - spacing: Gap between items on a line.
    /// - Returns: Contiguous index ranges, one per line.
    static func pillRows(_ sizes: [CGSize], width: CGFloat, spacing: CGFloat) -> [Range<Int>] {
        guard !sizes.isEmpty else { return [] }
        var groups: [Range<Int>] = []
        var start = 0
        var used: CGFloat = 0
        for index in sizes.indices {
            let required = sizes[index].width + (index == start ? 0 : spacing)
            if index > start && used + required > width {
                groups.append(start..<index)
                start = index
                used = sizes[index].width
            } else {
                used += required
            }
        }
        groups.append(start..<sizes.count)
        guard groups.count > 1 else { return groups }
        let base = sizes.count / groups.count
        let extra = sizes.count % groups.count
        var first = 0
        let balanced = (0..<groups.count).map { row -> Range<Int> in
            let end = first + base + (row < extra ? 1 : 0)
            defer { first = end }
            return first..<end
        }
        return balanced.allSatisfy { rowWidth($0, sizes: sizes, spacing: spacing) <= width } ? balanced : groups
    }

    /// Splits chips evenly across the fewest-wide rows that fit.
    ///
    /// - Parameters:
    ///   - sizes: Each chip's size.
    ///   - width: The available width.
    ///   - spacing: Gap between chips.
    /// - Returns: Contiguous index ranges, one per line.
    static func chipRows(_ sizes: [CGSize], width: CGFloat, spacing: CGFloat) -> [Range<Int>] {
        guard !sizes.isEmpty else { return [] }
        let widest = sizes.map(\.width).max() ?? 0
        let ideal = rowWidth(sizes.indices, sizes: sizes, spacing: spacing)
        let measured = min(max(0, width), ideal)
        let fit = max(1, Int((measured + spacing) / (widest + spacing)))
        let rowCount = (sizes.count + fit - 1) / fit
        let base = sizes.count / rowCount
        let extra = sizes.count % rowCount
        var start = 0
        return (0..<rowCount).map { row in
            let end = start + base + (row < extra ? 1 : 0)
            defer { start = end }
            return start..<end
        }
    }

    /// Sums one line's widths and gaps.
    static func rowWidth<C: Collection>(_ indices: C, sizes: [CGSize], spacing: CGFloat) -> CGFloat where C.Element == Int {
        indices.reduce(CGFloat.zero) { $0 + sizes[$1].width } + CGFloat(max(0, indices.count - 1)) * spacing
    }

    /// Positions items on lines.
    ///
    /// - Parameters:
    ///   - rows: Line ranges.
    ///   - sizes: Item sizes.
    ///   - width: Container width.
    ///   - spacing: Gap between items and between lines.
    ///   - alignment: Where each line starts: leading, trailing or centred.
    /// - Returns: Frames in source order and the total height.
    static func place(
        rows: [Range<Int>], sizes: [CGSize], width: CGFloat, spacing: CGFloat, alignment: Alignment
    ) -> (frames: [CGRect], height: CGFloat) {
        var frames = [CGRect](repeating: .zero, count: sizes.count)
        var y: CGFloat = 0
        for row in rows {
            let lineWidth = rowWidth(row, sizes: sizes, spacing: spacing)
            var x: CGFloat
            switch alignment {
            case .leading: x = 0
            case .trailing: x = width - lineWidth
            case .center: x = max(0, (width - lineWidth) / 2)
            }
            let height = row.reduce(CGFloat.zero) { max($0, sizes[$1].height) }
            for index in row {
                frames[index] = CGRect(origin: CGPoint(x: x, y: y), size: sizes[index])
                x += sizes[index].width + spacing
            }
            y += height + spacing
        }
        return (frames, max(0, y - spacing))
    }

    /// Horizontal anchoring of a line.
    enum Alignment { case leading, trailing, center }
}

// MARK: - Pill

/// One compact score field with its explicit look (``SongMetadataFieldView``): drawn by hand
/// from a label and layer properties so a row holds few views.
final class UKSongMetadataFieldView: UIView {
    let field: SongMetadataField
    private let label = UILabel()
    private var stars: UKStarRatingView?
    private var meter: UKDifficultyMeterView?
    private var icon: UIImageView?
    private var outline: CAShapeLayer?
    private let isAX: Bool
    private let inset: CGFloat
    private let badgeHeight: CGFloat
    private let percentWidth: CGFloat

    /// Creates the pill.
    ///
    /// - Parameters:
    ///   - field: The validated field.
    ///   - traits: The row's trait collection (Dynamic Type).
    init(field: SongMetadataField, traits: UITraitCollection) {
        self.field = field
        isAX = traits.preferredContentSizeCategory.isAccessibilityCategory
        inset = UKFont.scaled(4, relativeTo: .body, traits: traits)
        badgeHeight = max(UKFont.scaled(28, relativeTo: .body, traits: traits), isAX ? 44 : 28)
        percentWidth = UKFont.scaled(66, relativeTo: .callout, traits: traits)
        super.init(frame: .zero)
        isAccessibilityElement = false
        label.numberOfLines = 0
        label.textColor = BrandUIColors.textPrimary
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Build

    private func build() {
        switch field {
        case let .score(value):
            style(label, .title3, bold: true, mono: true)
            label.text = value.formatted()
            addSubview(label)
        case let .accuracy(value, combo, percentageVisible, tint):
            style(label, .callout, bold: true, italic: combo)
            label.textAlignment = .center
            label.numberOfLines = 1
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.8
            label.text = Self.accuracyLabel(value: value, fullCombo: combo, percentageVisible: percentageVisible, tint: tint)
            label.textColor = combo ? BrandUIColors.gold : BrandUIColors.textPrimary
            addSubview(label)
            if combo {
                let shape = CAShapeLayer()
                shape.fillColor = nil
                shape.strokeColor = BrandUIColors.gold.cgColor
                shape.lineWidth = 2
                layer.addSublayer(shape)
                outline = shape
            } else {
                layer.cornerRadius = 6
                layer.cornerCurve = .continuous
                if let tint {
                    backgroundColor = UIColor(
                        red: CGFloat(tint.red) / 255, green: CGFloat(tint.green) / 255, blue: CGFloat(tint.blue) / 255, alpha: 0.25
                    )
                } else {
                    backgroundColor = BrandUIColors.statusRed
                }
            }
        case let .percentile(text, tier):
            let highlighted = tier != .ordinary
            style(label, .callout, bold: true, italic: tier == .topOne)
            label.text = text
            label.textAlignment = .center
            label.numberOfLines = isAX ? 2 : 1
            label.textColor = highlighted ? BrandUIColors.gold : BrandUIColors.textPrimary
            backgroundColor = highlighted ? BrandUIColors.cardBackground : BrandUIColors.surfaceMuted
            layer.cornerRadius = 6
            layer.cornerCurve = .continuous
            layer.borderWidth = highlighted ? 2 : 0
            layer.borderColor = BrandUIColors.goldStroke.cgColor
            addSubview(label)
        case let .stars(count, gold):
            if isAX {
                let image = UIImageView(image: UIImage(named: StarRating.assetName(gold: gold), in: .module, compatibleWith: nil))
                image.contentMode = .scaleAspectFit
                icon = image
                addSubview(image)
                style(label, .callout, bold: true)
                label.text = gold ? "\(count) gold stars" : "\(count) stars"
                label.textColor = gold ? BrandUIColors.gold : BrandUIColors.textPrimary
                addSubview(label)
            } else {
                let rating = UKStarRatingView(stars: count, gold: gold, style: .mini, size: badgeHeight / 1.2)
                rating.translatesAutoresizingMaskIntoConstraints = true
                rating.isAccessibilityElement = false
                stars = rating
                addSubview(rating)
            }
        case let .season(number, current):
            style(label, .callout, bold: true)
            label.text = "S\(number)"
            label.textAlignment = .center
            label.numberOfLines = 1
            label.textColor = current ? BrandUIColors.surfaceSubtle : BrandUIColors.textPrimary
            backgroundColor = current ? BrandUIColors.textSecondary : BrandUIColors.surfaceSubtle
            layer.cornerRadius = 6
            layer.cornerCurve = .continuous
            addSubview(label)
        case let .intensity(raw):
            let view = UKDifficultyMeterView(level: raw, raw: true)
            view.translatesAutoresizingMaskIntoConstraints = true
            view.isAccessibilityElement = false
            meter = view
            addSubview(view)
        case let .difficulty(number):
            style(label, .callout, bold: true)
            label.text = Self.difficultyInitial(number)
            label.textAlignment = .center
            label.numberOfLines = 1
            label.textColor = Self.difficultyForeground(number)
            backgroundColor = Self.difficultyBackground(number)
            layer.cornerRadius = 6
            layer.cornerCurve = .continuous
            layer.borderWidth = 1
            layer.borderColor = BrandUIColors.borderSubtle.cgColor
            addSubview(label)
        case let .lastPlayed(value):
            style(label, .footnote)
            label.text = value
            label.textAlignment = .center
            backgroundColor = BrandUIColors.surfaceSubtle
            layer.cornerRadius = 6
            layer.cornerCurve = .continuous
            addSubview(label)
        }
    }

    private func style(_ label: UILabel, _ style: UIFont.TextStyle, bold: Bool = false, mono: Bool = false, italic: Bool = false) {
        label.font = UKFont.font(style, weight: bold ? .bold : nil, monospacedDigit: mono, italic: italic)
        label.adjustsFontForContentSizeCategory = true
    }

    // MARK: Measure

    /// The pill's size within `maxWidth`.
    ///
    /// - Parameter maxWidth: The widest the pill may be.
    /// - Returns: Its size.
    func fittedSize(maxWidth: CGFloat) -> CGSize {
        switch field {
        case .score:
            return label.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
        case .accuracy:
            return CGSize(width: min(percentWidth, maxWidth), height: badgeHeight)
        case .percentile:
            let text = label.sizeThatFits(CGSize(width: maxWidth - 2 * inset, height: .greatestFiniteMagnitude))
            return CGSize(width: min(maxWidth, max(80, text.width + 2 * inset)), height: max(badgeHeight, text.height))
        case .stars:
            if isAX {
                let text = label.sizeThatFits(CGSize(width: maxWidth - 18 - 4 - 2 * inset, height: .greatestFiniteMagnitude))
                return CGSize(width: min(maxWidth, 18 + 4 + text.width + 2 * inset), height: max(badgeHeight, text.height))
            }
            let natural = stars?.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize) ?? .zero
            return CGSize(width: natural.width, height: badgeHeight)
        case .season:
            let text = label.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
            return CGSize(width: min(maxWidth, max(42, text.width + 2 * inset)), height: badgeHeight)
        case .intensity:
            let scale = badgeHeight / 20
            return CGSize(width: 62 * scale, height: badgeHeight)
        case .difficulty:
            let text = label.sizeThatFits(CGSize(width: maxWidth, height: .greatestFiniteMagnitude))
            return CGSize(width: min(maxWidth, max(32, text.width + 2 * inset)), height: badgeHeight)
        case .lastPlayed:
            let text = label.sizeThatFits(CGSize(width: maxWidth - 2 * inset, height: .greatestFiniteMagnitude))
            return CGSize(width: min(maxWidth, max(108, text.width + 2 * inset)), height: max(badgeHeight, text.height))
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = self.bounds
        switch field {
        case .score:
            label.frame = bounds
        case .accuracy, .season, .difficulty:
            label.frame = bounds.insetBy(dx: inset, dy: 0)
            if let outline { layoutOutline(outline) }
        case .percentile, .lastPlayed:
            label.frame = bounds.insetBy(dx: inset, dy: 0)
        case .stars:
            if isAX {
                icon?.frame = CGRect(x: inset, y: (bounds.height - 18) / 2, width: 18, height: 18)
                label.frame = CGRect(x: inset + 22, y: 0, width: max(0, bounds.width - inset - 22 - inset), height: bounds.height)
            } else {
                stars?.frame = bounds
            }
        case .intensity:
            let scale = badgeHeight / 20
            meter?.bounds = CGRect(x: 0, y: 0, width: 62, height: 20)
            meter?.center = CGPoint(x: bounds.midX, y: bounds.midY)
            meter?.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }

    /// The web's `GOLD_SKEW`: a rounded outline sheared -8° about its middle.
    private func layoutOutline(_ shape: CAShapeLayer) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        guard box.width > 0, box.height > 0 else { shape.path = nil; return }
        let shear = tan(8 * CGFloat.pi / 180)
        let shift = shear * box.height / 2
        let local = CGRect(x: shift, y: 0, width: max(0, box.width - 2 * shift), height: box.height)
        let transform = CGAffineTransform(a: 1, b: 0, c: -shear, d: 1, tx: shear * box.height / 2, ty: 0)
            .concatenating(CGAffineTransform(translationX: box.minX, y: box.minY))
        let path = UIBezierPath(roundedRect: local, cornerRadius: 7)
        path.apply(transform)
        shape.path = path.cgPath
    }

    // MARK: Copy

    /// Do not make an invalid non-FC tint look like a correctly graded score.
    static func accuracyLabel(value: Double?, fullCombo: Bool, percentageVisible: Bool, tint: ScoreAccuracyTint?) -> String {
        if !fullCombo && value != nil && tint == nil { return "Accuracy display unavailable" }
        if percentageVisible, let value { return "\(ScoreFormatting.accuracy(value))%" }
        return fullCombo ? "FC" : "Accuracy unavailable"
    }

    static func difficultyInitial(_ number: Int) -> String {
        switch number {
        case 0: "E"
        case 1: "M"
        case 2: "H"
        case 3: "X"
        default: "?"
        }
    }

    static func difficultyForeground(_ number: Int) -> UIColor {
        switch number {
        case 0, 2: BrandUIColors.cardBackground
        case 1, 3: BrandUIColors.textPrimary
        default: BrandUIColors.gold
        }
    }

    static func difficultyBackground(_ number: Int) -> UIColor {
        switch number {
        case 0: BrandUIColors.diffPillEasy
        case 1: BrandUIColors.diffPillMedium
        case 2: BrandUIColors.diffPillHard
        case 3: BrandUIColors.diffPillExpert
        default: BrandUIColors.statusRed
        }
    }
}

// MARK: - Pill flow

/// Ordered pills that wrap and align to the trailing (or leading) edge
/// (``SongProfileMetadataPills``), laid out by hand.
final class UKSongMetadataFlowView: UIView {
    private(set) var pills: [UKSongMetadataFieldView] = []
    private let leading: Bool
    private let spacing: CGFloat = 10
    private var plan: (width: CGFloat, frames: [CGRect], height: CGFloat)?

    /// Creates the flow.
    ///
    /// - Parameters:
    ///   - fields: Ordered fields.
    ///   - traits: The row's trait collection.
    ///   - leading: Lines start at the leading edge (a wide row's instrument cards).
    init(fields: [SongMetadataField], traits: UITraitCollection, leading: Bool) {
        self.leading = leading
        super.init(frame: .zero)
        pills = fields.map { UKSongMetadataFieldView(field: $0, traits: traits) }
        pills.forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func layout(width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        if let plan, plan.width == width { return (plan.frames, plan.height) }
        let ideal = pills.map { $0.fittedSize(maxWidth: .greatestFiniteMagnitude) }
        let intrinsic = UKSongFlow.rowWidth(ideal.indices, sizes: ideal, spacing: spacing)
        let available = max(1, min(width, max(1, intrinsic)))
        let sizes = pills.enumerated().map { index, pill in
            ideal[index].width > available ? pill.fittedSize(maxWidth: available) : ideal[index]
        }
        let rows = UKSongFlow.pillRows(sizes, width: available, spacing: spacing)
        let placed = UKSongFlow.place(
            rows: rows, sizes: sizes, width: width, spacing: spacing, alignment: leading ? .leading : .trailing
        )
        plan = (width, placed.frames, placed.height)
        return placed
    }

    /// The height needed at `width`.
    func height(forWidth width: CGFloat) -> CGFloat { layout(width: width).height }

    override func layoutSubviews() {
        super.layoutSubviews()
        let frames = layout(width: bounds.width).frames
        for (pill, frame) in zip(pills, frames) { pill.frame = frame }
    }
}

// MARK: - Instrument status chips

/// A song's per-chart status circles (``SongInstrumentStatusChips``), pre-drawn once per
/// instrument, status and size and laid out in balanced centred rows.
final class UKSongStatusChipsView: UIView {
    private var images: [UIImageView] = []
    private let side: CGFloat
    private let spacing: CGFloat = 4
    private var plan: (width: CGFloat, frames: [CGRect], height: CGFloat)?
    /// The spoken statuses, joined with "; ".
    let announcement: String

    /// Creates the chips.
    ///
    /// - Parameters:
    ///   - badges: Source-ordered statuses.
    ///   - keyboard: This song's Lead/Pro Lead use the keys icon.
    ///   - traits: The row's trait collection.
    init(badges: [SongInstrumentBadge], keyboard: Bool, traits: UITraitCollection) {
        let scaled = UKFont.scaled(34, relativeTo: .body, traits: traits)
        side = min(max(scaled, traits.preferredContentSizeCategory.isAccessibilityCategory ? 48 : 34), 64)
        announcement = badges.map(\.announcement).joined(separator: "; ")
        super.init(frame: .zero)
        isAccessibilityElement = false
        let scale = traits.displayScale > 0 ? traits.displayScale : 3
        for badge in badges {
            let usesKeys = keyboard && (badge.instrument == .lead || badge.instrument == .proLead)
            let view = UIImageView(image: Self.image(instrument: badge.instrument, keyboard: usesKeys, status: badge.status, side: side, scale: scale))
            view.isAccessibilityElement = false
            images.append(view)
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func layout(width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        if let plan, plan.width == width { return (plan.frames, plan.height) }
        let sizes = [CGSize](repeating: CGSize(width: side, height: side), count: images.count)
        let rows = UKSongFlow.chipRows(sizes, width: width, spacing: spacing)
        let placed = UKSongFlow.place(rows: rows, sizes: sizes, width: width, spacing: spacing, alignment: .center)
        plan = (width, placed.frames, placed.height)
        return placed
    }

    /// The height needed at `width`.
    func height(forWidth width: CGFloat) -> CGFloat { layout(width: width).height }

    override func layoutSubviews() {
        super.layoutSubviews()
        let frames = layout(width: bounds.width).frames
        for (view, frame) in zip(images, frames) {
            // The bitmap carries the stroke's 1 pt overhang on every side.
            view.frame = frame.insetBy(dx: -Self.overhang, dy: -Self.overhang)
        }
    }

    // MARK: Bitmaps

    private struct Key: Hashable {
        let instrument: Instrument
        let keyboard: Bool
        let status: SongInstrumentStatus
        let side: CGFloat
        let scale: CGFloat
    }

    nonisolated(unsafe) private static var cache: [Key: UIImage] = [:]
    /// Stroke overhang outside the chip frame on each side.
    static let overhang: CGFloat = 1

    /// The chip bitmap, drawn on first use.
    static func image(instrument: Instrument, keyboard: Bool, status: SongInstrumentStatus, side: CGFloat, scale: CGFloat) -> UIImage {
        let key = Key(instrument: instrument, keyboard: keyboard, status: status, side: side, scale: scale)
        if let cached = cache[key] { return cached }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        let canvas = CGSize(width: side + 2 * overhang, height: side + 2 * overhang)
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            let circle = CGRect(x: overhang, y: overhang, width: side, height: side)
            fillColor(status).setFill()
            UIBezierPath(ovalIn: circle).fill()
            if let icon = UKInstrumentIconView.image(for: instrument, keyboard: keyboard) {
                let edge = side * 0.7
                let rect = CGRect(x: circle.midX - edge / 2, y: circle.midY - edge / 2, width: edge, height: edge)
                icon.draw(in: rect)
            }
            let ring = UIBezierPath(ovalIn: circle)
            ring.lineWidth = 2
            strokeColor(status).setStroke()
            ring.stroke()
        }
        cache[key] = image
        return image
    }

    static func fillColor(_ status: SongInstrumentStatus) -> UIColor {
        switch status {
        case .fullCombo: BrandUIColors.gold
        case .scored: BrandUIColors.statusGreen
        case .noScore: BrandUIColors.statusRed
        case .inconsistentFullCombo: BrandUIColors.statusAmber
        case .unavailable: BrandUIColors.surfaceMuted
        }
    }

    static func strokeColor(_ status: SongInstrumentStatus) -> UIColor {
        switch status {
        case .fullCombo: BrandUIColors.goldStroke
        case .scored: BrandUIColors.statusGreenStroke
        case .noScore: BrandUIColors.statusRedStroke
        case .inconsistentFullCombo: BrandUIColors.statusAmberStroke
        case .unavailable: BrandUIColors.textDisabled
        }
    }
}
#endif
