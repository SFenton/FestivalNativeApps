#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Pulse border

/// The Item Shop pulse on a row's border (``ShopRowPulseBorder``): a 2 pt border whose
/// opacity follows the shared 2 s clock, played by the render server; still under Reduce
/// Motion, an inactive scene or the UI-test still override.
final class UKRowPulseBorderView: UIView {
    private let border = CALayer()
    private var tone: ShopStatusTone?
    private var radius: CGFloat = 12

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        border.cornerCurve = .continuous
        border.borderWidth = 2
        layer.addSublayer(border)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Sets the tone.
    func configure(tone: ShopStatusTone, cornerRadius: CGFloat) {
        guard tone != self.tone || cornerRadius != radius else { return }
        self.tone = tone
        radius = cornerRadius
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        border.borderColor = Self.color(tone).cgColor
        CATransaction.commit()
        setNeedsLayout()
        replan()
    }

    /// The pulse's border colour for a tone.
    static func color(_ tone: ShopStatusTone) -> UIColor {
        switch tone {
        case .inShop: BrandUIColors.diffPillEasy
        case .new: BrandUIColors.gold
        case .leaving: UIColor(red: 239 / 255, green: 68 / 255, blue: 68 / 255, alpha: 1)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        border.frame = bounds.insetBy(dx: -1, dy: -1)
        border.cornerRadius = radius + 1
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        replan()
    }

    private func replan() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        border.removeAnimation(forKey: "pulse")
        let running = window != nil && !UKAccessibility.reduceMotion && !DebugAnimationOverride.stillBackground
            && window?.windowScene?.activationState == .foregroundActive
        guard tone != nil, running else {
            border.opacity = Float(ShopRowPulseBorder.peak)
            CATransaction.commit()
            return
        }
        let values = ShopPulseClock.keyframes(period: ShopRowPulseBorder.period) { ShopRowPulseBorder.opacity(at: $0, animating: true) }
        border.opacity = Float(values[0])
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = values.map { NSNumber(value: $0) }
        animation.calculationMode = .discrete
        animation.duration = ShopRowPulseBorder.period
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.beginTime = CACurrentMediaTime() - ShopPulseClock.elapsed(period: ShopRowPulseBorder.period, at: Date())
        let fps = ShopPulseClock.framesPerSecond
        animation.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: fps, preferred: fps)
        border.add(animation, forKey: "pulse")
        CATransaction.commit()
    }
}

// MARK: - Accessibility element

/// The row's one accessibility element: a button over the card that opens the song.
final class UKSongRowElement: UIAccessibilityElement {
    var onActivate: (() -> Void)?

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return onActivate != nil
    }
}

/// A stop over part of a row (a field, the chips, an invalid-score button).
final class UKSongRowStop: UIAccessibilityElement {
    var onActivate: (() -> Void)?
    var frameInCell: CGRect = .zero

    override var accessibilityFrame: CGRect {
        get {
            guard let cell = accessibilityContainer as? UIView else { return super.accessibilityFrame }
            return cell.convert(frameInCell, to: nil)
        }
        set { super.accessibilityFrame = newValue }
    }

    override func accessibilityActivate() -> Bool {
        onActivate?()
        return onActivate != nil
    }
}

// MARK: - Cell

/// One Songs row (or Item Shop row): the shared material card with ``UKSongRowView`` in it.
final class UKSongRowCell: UICollectionViewCell {
    static let reuseIdentifier = "UKSongRowCell"

    let card = UKCardView(cornerRadius: 12)
    let row = UKSongRowView()
    private let pulse = UKRowPulseBorderView()
    private let contrastRim = UIView()
    private var songId = ""
    private var rowElement: UKSongRowElement?
    private var stops: [UKSongRowStop] = []
    /// The row's accessibility stops, vended through the container protocol below.
    private var exposedElements: [Any] = []
    nonisolated(unsafe) private var voiceOver: NSObjectProtocol?
    /// Opens the song (tap, VoiceOver activate).
    var onOpen: (() -> Void)?
    /// Shows the invalid-score explanation for the warning.
    var onInvalidScore: ((InvalidScoreWarning) -> Void)?

    /// Item Shop list rows: the official bag action over the row's bag slot, or (at accessibility
    /// sizes) a full-width link under the card.
    struct ShopLink {
        var label: String
        var identifier: String
        var action: () -> Void
        /// Under the card instead of over the bag slot.
        var below: Bool
    }

    var shopLink: ShopLink? { didSet { configureShopLink() } }
    /// Overrides the row element's identifier (`fst.shop.song.<id>` for a navigable Shop row).
    var rowIdentifierOverride: String?
    /// Whether the row opens something (a Shop offer without a catalogue match does not).
    var rowOpens = true
    private let bagButton = UIButton(type: .system)
    private let linkButton = UIButton(type: .system)
    private static let linkHeight: CGFloat = 44
    private static let linkGap: CGFloat = 4

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        card.translatesAutoresizingMaskIntoConstraints = true
        contentView.addSubview(card)
        card.contentView.addSubview(row)
        contrastRim.layer.cornerRadius = 12
        contrastRim.layer.cornerCurve = .continuous
        contrastRim.layer.borderWidth = 2
        contrastRim.layer.borderColor = BrandUIColors.textPrimary.cgColor
        contrastRim.isUserInteractionEnabled = false
        contrastRim.isHidden = true
        pulse.isHidden = true
        card.addSubview(contrastRim)
        card.addSubview(pulse)
        for button in [bagButton, linkButton] {
            button.isHidden = true
            contentView.addSubview(button)
        }
        bagButton.setImage(UIImage(systemName: "bag"), for: .normal)
        bagButton.tintColor = BrandUIColors.textPrimary
        bagButton.addAction(UIAction { [weak self] _ in self?.shopLink?.action() }, for: .touchUpInside)
        var linkConfiguration = UIButton.Configuration.plain()
        linkConfiguration.title = "Open Official Item Shop"
        linkConfiguration.image = UIImage(systemName: "bag")
        linkConfiguration.imagePadding = 6
        linkConfiguration.baseForegroundColor = BrandUIColors.textPrimary
        linkConfiguration.background.backgroundColor = BrandUIColors.cardBackground
        linkConfiguration.background.cornerRadius = 12
        linkButton.configuration = linkConfiguration
        linkButton.contentHorizontalAlignment = .leading
        linkButton.addAction(UIAction { [weak self] _ in self?.shopLink?.action() }, for: .touchUpInside)
        isAccessibilityElement = false
        voiceOver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.rebuildAccessibility() } }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { if let voiceOver { NotificationCenter.default.removeObserver(voiceOver) } }

    // MARK: Configure

    /// Fills the cell.
    ///
    /// - Parameters:
    ///   - input: The row's inputs.
    ///   - width: The cell's width.
    func configure(_ input: UKSongRowInput, width: CGFloat, traits: UITraitCollection? = nil) {
        songId = input.song.songId
        row.configure(input, width: width, traits: traits)
        let tone: ShopStatusTone?
        if let offer = input.shopOffer { tone = offer.pulseTone } else { tone = input.inShop ? ShopStatusTone(highlight: input.shopHighlight) : nil }
        if let tone {
            pulse.configure(tone: tone, cornerRadius: 12)
            pulse.isHidden = false
            contrastRim.isHidden = true
        } else {
            pulse.isHidden = true
            contrastRim.isHidden = !input.highContrast
        }
        setNeedsLayout()
        rebuildAccessibility()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onOpen = nil
        onInvalidScore = nil
        shopLink = nil
        rowIdentifierOverride = nil
        rowOpens = true
    }

    private func configureShopLink() {
        bagButton.isHidden = shopLink == nil || shopLink?.below == true
        linkButton.isHidden = shopLink?.below != true
        setNeedsLayout()
    }

    // MARK: Layout

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        let below = shopLink?.below == true ? Self.linkGap + Self.linkHeight : 0
        attributes.size.height = row.height(forWidth: layoutAttributes.size.width) + below
        return attributes
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let below = shopLink?.below == true ? Self.linkGap + Self.linkHeight : 0
        card.frame = CGRect(x: 0, y: 0, width: contentView.bounds.width, height: contentView.bounds.height - below)
        row.frame = card.bounds
        if let slot = row.bagSlotFrame, shopLink?.below != true {
            let center = row.convert(CGPoint(x: slot.midX, y: slot.midY), to: contentView)
            bagButton.frame = CGRect(x: center.x - 22, y: center.y - 22, width: 44, height: 44)
        }
        if below > 0 {
            linkButton.frame = CGRect(x: 0, y: card.frame.maxY + Self.linkGap, width: contentView.bounds.width, height: Self.linkHeight)
        }
        contrastRim.frame = card.bounds
        pulse.frame = card.bounds
        rebuildAccessibility()
    }

    // MARK: Accessibility

    /// Rebuilds the row's stops: the combined button, its children while VoiceOver is off (so
    /// XCUI and assistive tools that are not VoiceOver can address them), then the invalid-score
    /// button and the profile cards.
    private func rebuildAccessibility() {
        guard row.input != nil else { return }
        let element = rowElement ?? UKSongRowElement(accessibilityContainer: self)
        rowElement = element
        element.accessibilityLabel = row.spokenParts.joined(separator: ", ")
        element.accessibilityIdentifier = rowIdentifierOverride
            ?? (row.input?.shopOffer == nil ? "fst.songs.row.\(songId)" : "fst.shop.row.\(songId)")
        element.accessibilityTraits = rowOpens ? .button : .staticText
        element.accessibilityFrameInContainerSpace = card.frame
        element.onActivate = { [weak self] in self?.onOpen?() }
        var elements: [Any] = [element]
        var next: [UKSongRowStop] = []
        func stop(_ id: String, _ label: String, _ frame: CGRect, _ traits: UIAccessibilityTraits) -> UKSongRowStop {
            let stop = UKSongRowStop(accessibilityContainer: self)
            stop.accessibilityIdentifier = id
            stop.accessibilityLabel = label
            stop.accessibilityTraits = traits
            stop.frameInCell = frame
            next.append(stop)
            return stop
        }
        if !UIAccessibility.isVoiceOverRunning {
            for child in row.childElements(songId: songId) {
                elements.append(stop(child.id, child.label, row.convert(child.frame, to: self), child.traits))
            }
        }
        if let warning = row.invalidWarning, let glyph = row.invalidGlyphFrame {
            let center = row.convert(CGPoint(x: glyph.midX, y: glyph.midY), to: self)
            let frame = CGRect(x: center.x - 22, y: center.y - 22, width: 44, height: 44)
            let button = stop("fst.songs.invalid-score.\(songId)", InvalidScoreWarning.accessibilityLabel, frame, .button)
            button.accessibilityHint = "Explains the filtered score"
            button.onActivate = { [weak self] in self?.onInvalidScore?(warning) }
            elements.append(button)
        }
        if let link = shopLink {
            let frame = link.below ? linkButton.frame : bagButton.frame
            let bag = stop(link.identifier, link.label, frame, .button)
            bag.onActivate = link.action
            elements.append(bag)
        }
        let cards = row.panelCards
        if !cards.isEmpty {
            for card in cards {
                elements.append(stop("fst.songs.profile-panel.\(songId).\(card.id)", card.label, row.convert(card.frame, to: self), .staticText))
            }
        }
        stops = next
        exposedElements = elements
    }

    // MARK: Accessibility container

    override func accessibilityElementCount() -> Int { exposedElements.count }

    override func accessibilityElement(at index: Int) -> Any? {
        exposedElements.indices.contains(index) ? exposedElements[index] : nil
    }

    override func index(ofAccessibilityElement element: Any) -> Int {
        exposedElements.firstIndex { ($0 as AnyObject) === (element as AnyObject) } ?? NSNotFound
    }

    // MARK: Taps

    /// Tap targets: the card opens the song except over the invalid-score glyph.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        super.point(inside: point, with: event)
    }

    /// Whether `point` (cell coordinates) is on the invalid-score glyph's target.
    func invalidScore(at point: CGPoint) -> InvalidScoreWarning? {
        guard let warning = row.invalidWarning, let glyph = row.invalidGlyphFrame else { return nil }
        let center = row.convert(CGPoint(x: glyph.midX, y: glyph.midY), to: self)
        return CGRect(x: center.x - 22, y: center.y - 22, width: 44, height: 44).contains(point) ? warning : nil
    }
}
#endif
