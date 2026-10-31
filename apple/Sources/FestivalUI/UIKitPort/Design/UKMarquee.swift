#if os(iOS)
import FestivalDesign
import QuartzCore
import UIKit

// MARK: - Sync group

/// Marquees that scroll in lock step (``MarqueeSyncGroup``): every member of a group
/// scrolls the distance of the widest overflowing one, so a song's title and artist
/// move together and finish together.
@MainActor
final class UKMarqueeSyncGroup {
    private struct Member {
        weak var view: UKMarqueeLabel?
        var width: CGFloat
    }

    private var members: [ObjectIdentifier: Member] = [:]
    /// Gap between the repeated copies of the text.
    private(set) var gap: CGFloat

    /// Creates a group.
    ///
    /// - Parameter gap: Gap between the repeated copies.
    init(gap: CGFloat = 28) { self.gap = gap }

    /// Shared distance, when two or more members overflow.
    var syncDistance: CGFloat? {
        MarqueeTiming.syncDistance(widths: members.values.map(\.width), gap: gap)
    }

    fileprivate func register(_ view: UKMarqueeLabel, width: CGFloat) {
        let before = syncDistance
        members[ObjectIdentifier(view)] = Member(view: view, width: width)
        prune()
        notify(from: before, except: view)
    }

    fileprivate func unregister(_ view: UKMarqueeLabel) {
        let before = syncDistance
        members[ObjectIdentifier(view)] = nil
        prune()
        notify(from: before, except: view)
    }

    private func prune() { members = members.filter { $0.value.view != nil } }

    private func notify(from before: CGFloat?, except sender: UKMarqueeLabel) {
        guard syncDistance != before else { return }
        for member in members.values where member.view !== sender { member.view?.syncDistanceChanged() }
    }
}

// MARK: - Marquee label

/// A single line of text that scrolls when it overflows (``MarqueeText``): the text is
/// rendered once to an image, drawn twice `gap` apart, and a Core Animation keyframe
/// animation on a layer slides it (dwell, scroll, dwell, repeat). The render server runs
/// it, so the main thread pays nothing per frame.
///
/// Static (truncated with an ellipsis) under system or in-app Reduce Motion, in an
/// inactive scene or hidden window, with ``animationEnabled`` off, or under
/// `FST_DEBUG_STILL_BACKGROUND=1`; wrapping at accessibility text sizes when
/// ``wrapsAtAccessibilitySizes``. Spoken as its text (static text).
final class UKMarqueeLabel: UIView {
    private let staticLabel = UILabel()
    private let trackLayer = CALayer()
    private let firstCopy = CALayer()
    private let secondCopy = CALayer()
    private var renderKey: String?
    private var textSize: CGSize = .zero
    private var plan: Plan?
    private var registered = false
    private weak var group: UKMarqueeSyncGroup?
    private var observer: UKAccessibilityObserver?
    nonisolated(unsafe) private var sceneObservers: [NSObjectProtocol] = []

    private struct Plan: Equatable {
        let distance: CGFloat
        let cycleDuration: Double
        let renderKey: String
    }

    /// The string.
    var text: String { didSet { if text != oldValue { textChanged() } } }
    /// The font; Dynamic Type applies through `UKFont`.
    var font: UIFont { didSet { textChanged() } }
    /// The text colour (white by default).
    var textColor: UIColor { didSet { textChanged() } }
    /// Gap between the repeated copies.
    var gap: CGFloat = 28
    /// Seconds for one dwell-scroll-dwell cycle.
    var cycleDuration: Double = 8
    /// Wrap onto several lines at accessibility sizes instead of scrolling.
    var wrapsAtAccessibilitySizes = true { didSet { refresh() } }
    /// Off pins the text (``EnvironmentValues/marqueeAnimationEnabled``).
    var animationEnabled = true { didSet { refresh() } }
    /// Group that keeps several marquees in step.
    var syncGroup: UKMarqueeSyncGroup? {
        get { group }
        set {
            guard group !== newValue else { return }
            leaveGroup()
            group = newValue
            refresh()
        }
    }

    /// Creates a marquee.
    ///
    /// - Parameters:
    ///   - text: The string.
    ///   - font: Defaults to `.body`.
    ///   - color: Defaults to white (``FestivalText``).
    init(_ text: String, font: UIFont = UKFont.font(.body), color: UIColor = BrandUIColors.textPrimary) {
        self.text = text
        self.font = font
        self.textColor = color
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = true
        staticLabel.lineBreakMode = .byTruncatingTail
        staticLabel.numberOfLines = 1
        staticLabel.adjustsFontForContentSizeCategory = true
        staticLabel.isAccessibilityElement = false
        staticLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(staticLabel)
        NSLayoutConstraint.activate([
            staticLabel.leadingAnchor.constraint(equalTo: leadingAnchor), staticLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            staticLabel.topAnchor.constraint(equalTo: topAnchor), staticLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for copy in [firstCopy, secondCopy] {
            copy.contentsGravity = .resize
            trackLayer.addSublayer(copy)
        }
        layer.addSublayer(trackLayer)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityLabel = text
        applyText()
        observer = UKAccessibilityObserver { [weak self] in self?.refresh() }
        let center = NotificationCenter.default
        sceneObservers = [UIScene.didActivateNotification, UIScene.willDeactivateNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKMarqueeLabel, _) in
            self.textChanged()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { sceneObservers.forEach { NotificationCenter.default.removeObserver($0) } }

    // MARK: Layout

    private var wraps: Bool {
        wrapsAtAccessibilitySizes && UKFont.isAccessibilitySize(traitCollection)
    }

    private var naturalWidth: CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    override var intrinsicContentSize: CGSize {
        if wraps { return CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric) }
        return CGSize(width: naturalWidth, height: ceil(font.lineHeight))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        refresh()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        plan = nil
        if window == nil {
            leaveGroup()
            trackLayer.removeAnimation(forKey: "marquee")
        } else {
            refresh()
        }
    }

    // MARK: State

    private var mayScroll: Bool {
        guard animationEnabled, !UKAccessibility.reduceMotion, !DebugAnimationOverride.stillBackground,
              let scene = window?.windowScene else { return false }
        return scene.activationState == .foregroundActive
    }

    private func textChanged() {
        accessibilityLabel = text
        applyText()
        renderKey = nil
        plan = nil
        invalidateIntrinsicContentSize()
        refresh()
    }

    private func applyText() {
        staticLabel.text = text
        staticLabel.font = font
        staticLabel.textColor = textColor
        staticLabel.numberOfLines = wraps ? 0 : 1
    }

    func syncDistanceChanged() { refresh() }

    private func leaveGroup() {
        guard registered else { return }
        registered = false
        group?.unregister(self)
    }

    private func currentKey() -> String {
        "\(text)|\(font.fontName)|\(font.pointSize)|\(textColor.hash)|\(traitCollection.displayScale)"
    }

    private func renderIfNeeded() {
        let key = currentKey()
        guard key != renderKey else { return }
        renderKey = key
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let size = CGSize(width: naturalWidth, height: ceil(font.lineHeight))
        let format = UIGraphicsImageRendererFormat()
        format.scale = max(traitCollection.displayScale, 1)
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            (text as NSString).draw(at: .zero, withAttributes: attributes)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        firstCopy.contents = image.cgImage
        secondCopy.contents = image.cgImage
        CATransaction.commit()
        textSize = size
        plan = nil
    }

    /// Lays out the track and starts or stops the scroll.
    private func refresh() {
        applyText()
        let scrolls = !wraps && mayScroll && bounds.width > 0
        let overflowing = scrolls && MarqueeTiming.overflows(textWidth: naturalWidth, available: bounds.width)
        if scrolls { renderIfNeeded() }
        if overflowing {
            if !registered, let group {
                registered = true
                group.register(self, width: textSize.width)
            }
        } else {
            leaveGroup()
        }
        staticLabel.alpha = overflowing ? 0 : 1
        trackLayer.isHidden = !overflowing
        let distance = MarqueeTiming.distance(textWidth: textSize.width, gap: gap, syncDistance: group?.syncDistance)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = bounds
        let y = (bounds.height - textSize.height) / 2
        firstCopy.frame = CGRect(x: 0, y: y, width: textSize.width, height: textSize.height)
        secondCopy.frame = CGRect(x: distance, y: y, width: textSize.width, height: textSize.height)
        CATransaction.commit()
        let next = overflowing && cycleDuration > 0 && renderKey != nil
            ? Plan(distance: distance, cycleDuration: cycleDuration, renderKey: renderKey!) : nil
        guard next != plan else { return }
        plan = next
        trackLayer.removeAnimation(forKey: "marquee")
        guard let next else { return }
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = MarqueeTrackLayer.offsets(distance: next.distance).map { NSNumber(value: $0) }
        animation.keyTimes = MarqueeTrackLayer.keyTimes.map { NSNumber(value: $0) }
        animation.calculationMode = .linear
        animation.duration = next.cycleDuration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.beginTime = CACurrentMediaTime()
        trackLayer.add(animation, forKey: "marquee")
    }
}
#endif
