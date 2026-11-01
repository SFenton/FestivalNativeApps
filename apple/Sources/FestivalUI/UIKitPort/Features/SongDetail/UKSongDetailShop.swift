#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Shop status colours

extension ShopStatusTone {
    /// The tone's peak fill (``ShopStatusTone/target``) as a UIKit colour.
    var ukTarget: UIColor {
        switch self {
        case .inShop: BrandUIColors.statusGreenStroke
        case .new: BrandUIColors.goldStroke
        case .leaving: UIColor(red: 239 / 255, green: 68 / 255, blue: 68 / 255, alpha: 1)
        }
    }

    /// The web's resting fill, `rgb(18 24 38 / 96%)` (``ShopStatusTone/base``).
    static var ukBase: UIColor { UIColor(red: 18 / 255, green: 24 / 255, blue: 38 / 255, alpha: 0.96) }
}

// MARK: - Breathing glyph

/// The Item Shop action's 34 pt circle (``SongDetailShopGlyph``): a `bag` symbol on the
/// resting fill, with the status colour breathing over it (opacity 0 to 0.8 and back over
/// three seconds, rendered by Core Animation). Still, at the peak fill, under Reduce Motion
/// (system or in-app), in an inactive scene and with `FST_DEBUG_STILL_BACKGROUND`.
final class UKShopBreathingGlyphView: UIView {
    private let status = CALayer()
    private let tone: ShopStatusTone
    private var observer: UKAccessibilityObserver?
    nonisolated(unsafe) private var sceneObservers: [NSObjectProtocol] = []

    /// Creates the glyph.
    ///
    /// - Parameter tone: The song's Shop status.
    init(tone: ShopStatusTone) {
        self.tone = tone
        super.init(frame: CGRect(x: 0, y: 0, width: 34, height: 34))
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        backgroundColor = ShopStatusTone.ukBase
        layer.cornerRadius = 17
        layer.masksToBounds = true
        status.backgroundColor = tone.ukTarget.cgColor
        status.opacity = Float(ShopStatusTone.peakOpacity)
        layer.addSublayer(status)
        let icon = UIImageView(image: UIImage(systemName: "bag"))
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.body, weight: .semibold))
        icon.tintColor = BrandUIColors.textPrimary
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 34), heightAnchor.constraint(equalToConstant: 34),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor), icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isAccessibilityElement = false
        observer = UKAccessibilityObserver { [weak self] in self?.refresh() }
        let center = NotificationCenter.default
        for name in [UIScene.didActivateNotification, UIScene.willDeactivateNotification, UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification] {
            sceneObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { sceneObservers.forEach(NotificationCenter.default.removeObserver) }

    override func layoutSubviews() {
        super.layoutSubviews()
        status.frame = bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refresh()
    }

    private func refresh() {
        status.removeAnimation(forKey: "breathe")
        let active = window != nil && UIApplication.shared.applicationState == .active
        guard ShopStatusBreathe.animates(reduceMotion: UKAccessibility.reduceMotion, sceneActive: active, still: DebugAnimationOverride.stillBackground) else {
            status.opacity = Float(ShopStatusTone.peakOpacity)
            return
        }
        let breathe = CABasicAnimation(keyPath: "opacity")
        breathe.fromValue = 0
        breathe.toValue = ShopStatusTone.peakOpacity
        breathe.duration = ShopStatusTone.period / 2
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        status.opacity = 0
        status.add(breathe, forKey: "breathe")
    }

    /// A still picture of the glyph, for a floating page tool (which draws bar items from
    /// their image): the resting fill, the peak status colour and the bag.
    ///
    /// - Parameter tone: The Shop status.
    /// - Returns: The glyph as an original-rendering image.
    static func stillImage(tone: ShopStatusTone) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 34, height: 34))
        let image = renderer.image { _ in
            let circle = UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: 34, height: 34))
            ShopStatusTone.ukBase.setFill()
            circle.fill()
            tone.ukTarget.withAlphaComponent(ShopStatusTone.peakOpacity).setFill()
            circle.fill()
            let configuration = UIImage.SymbolConfiguration(font: UKFont.font(.body, weight: .semibold))
            if let bag = UIImage(systemName: "bag", withConfiguration: configuration)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                bag.draw(at: CGPoint(x: (34 - bag.size.width) / 2, y: (34 - bag.size.height) / 2))
            }
        }
        return image.withRenderingMode(.alwaysOriginal)
    }
}

// MARK: - Shop action

/// Builds Song Detail's Item Shop page tool (``SongDetailScreen/shopAction(_:fillsSlot:)``):
/// an external link to the official Shop page with a spoken status.
@MainActor
enum UKSongDetailShopAction {
    /// The bar item.
    ///
    /// - Parameters:
    ///   - offer: The song's validated Shop row.
    ///   - tone: Shop status tone, nil when highlighting is off.
    ///   - chrome: The section chrome (a vertical bar needs a titled symbol item).
    ///   - floating: The item is drawn as a floating page tool (from its image).
    /// - Returns: The bar button item.
    static func item(offer: ShopSong, tone: ShopStatusTone?, chrome: DeviceLayout.SectionChrome, floating: Bool) -> UIBarButtonItem {
        let open = UIAction { _ in UIApplication.shared.open(offer.shopUrl) }
        let style = SongDetailShopActionStyle.resolve(tone: tone, chrome: chrome)
        let item: UIBarButtonItem
        switch style {
        case let .breathing(tone):
            if floating {
                item = UIBarButtonItem(title: "Item Shop", image: UKShopBreathingGlyphView.stillImage(tone: tone), primaryAction: open)
            } else {
                let button = UIButton(type: .custom)
                button.addAction(open, for: .primaryActionTriggered)
                let glyph = UKShopBreathingGlyphView(tone: tone)
                button.addSubview(glyph)
                button.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    glyph.centerXAnchor.constraint(equalTo: button.centerXAnchor), glyph.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                    button.widthAnchor.constraint(equalToConstant: 44), button.heightAnchor.constraint(equalToConstant: 44),
                ])
                button.accessibilityLabel = "Item Shop, \(tone.spokenStatus)"
                button.accessibilityTraits = .link
                button.accessibilityIdentifier = "fst.song-detail.shop"
                item = UIBarButtonItem(customView: button)
            }
            item.accessibilityLabel = "Item Shop, \(tone.spokenStatus)"
        case let .titled(spoken):
            item = UIBarButtonItem(title: "Item Shop", image: UIImage(systemName: "bag"), primaryAction: open)
            item.accessibilityLabel = spoken
        }
        item.accessibilityTraits = .link
        item.accessibilityIdentifier = "fst.song-detail.shop"
        item.tintColor = BrandUIColors.textPrimary
        return item
    }
}
#endif
