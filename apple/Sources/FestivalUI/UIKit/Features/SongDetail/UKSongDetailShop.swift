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
    private let status = ShopPulseView()
    private let icon = UIImageView(image: UIImage(systemName: "bag"))
    private let tone: ShopStatusTone
    private let limitsSymbolSize: Bool
    private var observer: UKAccessibilityObserver?
    nonisolated(unsafe) private var sceneObservers: [NSObjectProtocol] = []

    /// Off-slide guide glyphs, unlike the live action, stay still inside a visible window.
    var allowsMotion = true { didSet { if allowsMotion != oldValue { refresh() } } }

    /// Creates the glyph.
    ///
    /// - Parameters:
    ///   - tone: The song's Shop status.
    ///   - limitsSymbolSize: Match the floating row's Dynamic Type cap.
    init(tone: ShopStatusTone, limitsSymbolSize: Bool = false) {
        self.tone = tone
        self.limitsSymbolSize = limitsSymbolSize
        super.init(frame: CGRect(x: 0, y: 0, width: 34, height: 34))
        translatesAutoresizingMaskIntoConstraints = false
        isUserInteractionEnabled = false
        backgroundColor = ShopStatusTone.ukBase
        layer.cornerRadius = 17
        layer.masksToBounds = true
        ukPin(status)
        icon.tintColor = BrandUIColors.textPrimary
        icon.contentMode = .center
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 34), heightAnchor.constraint(equalToConstant: 34),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor), icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        isAccessibilityElement = false
        updateSymbolSize()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (glyph: UKShopBreathingGlyphView, _) in
            glyph.updateSymbolSize()
        }
        observer = UKAccessibilityObserver { [weak self] in self?.refresh() }
        let center = NotificationCenter.default
        sceneObservers = [UIScene.didActivateNotification, UIScene.willDeactivateNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let scene = notification.object as? UIScene else { return }
                let sceneID = ObjectIdentifier(scene)
                MainActor.assumeIsolated {
                    guard let self, let scene = self.window?.windowScene,
                          ObjectIdentifier(scene) == sceneID else { return }
                    self.refresh(sceneActive: name == UIScene.didActivateNotification)
                }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { sceneObservers.forEach(NotificationCenter.default.removeObserver) }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refresh()
    }

    private func updateSymbolSize() {
        let size = limitsSymbolSize
            ? UKFloatingPageToolsView.symbolPointSize(for: traitCollection)
            : UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection).pointSize
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: size, weight: .semibold)
    }

    private func refresh(sceneActive: Bool? = nil) {
        let foreground = sceneActive ?? (window?.windowScene?.activationState == .foregroundActive)
        let running = ShopStatusBreathe.animates(
            reduceMotion: UKAccessibility.reduceMotion, sceneActive: allowsMotion && foreground,
            still: DebugAnimationOverride.stillBackground
        )
        let pulse = ShopPulseLayer(
            shape: .disc, color: tone.target, period: ShopStatusTone.period,
            restingOpacity: ShopStatusTone.peakOpacity, running: running
        ) { ShopStatusBreathe.intensity(at: $0, animating: true) * ShopStatusTone.peakOpacity }
        status.apply(pulse, color: tone.ukTarget.cgColor)
    }
}

// MARK: - Shop action

/// Builds Song Detail's Item Shop page tool (``SongDetailScreen/shopAction(_:fillsSlot:)``):
/// an external link to the official Shop page with a spoken status.
@MainActor
enum UKSongDetailShopAction {
    /// The Shop link and its optional live floating glyph.
    ///
    /// - Parameters:
    ///   - offer: The song's validated Shop row.
    ///   - tone: Shop status tone, nil when highlighting is off.
    ///   - chrome: The section chrome (a vertical bar needs a titled symbol item).
    ///   - floating: The item is hosted in the floating row instead of the bar.
    /// - Returns: The page tool for the current chrome.
    static func tool(offer: ShopSong, tone: ShopStatusTone?, chrome: DeviceLayout.SectionChrome, floating: Bool) -> UKPageTool {
        let identifier = "fst.song-detail.shop"
        let image = UIImage(systemName: "bag")
        let open = UIAction(title: "Item Shop", image: image) { _ in UIApplication.shared.open(offer.shopUrl) }
        open.accessibilityIdentifier = identifier
        let style = SongDetailShopActionStyle.resolve(tone: tone, chrome: chrome)
        let item: UIBarButtonItem
        let floatingGlyph: UIView?
        switch style {
        case let .breathing(tone):
            let glyph = UKShopBreathingGlyphView(tone: tone, limitsSymbolSize: floating)
            if floating {
                item = UIBarButtonItem(title: "Item Shop", image: image, primaryAction: open)
                floatingGlyph = glyph
            } else {
                let button = UIButton(type: .custom)
                button.addAction(open, for: .primaryActionTriggered)
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
                floatingGlyph = nil
            }
            item.accessibilityLabel = "Item Shop, \(tone.spokenStatus)"
        case let .titled(spoken):
            item = UIBarButtonItem(title: "Item Shop", image: image, primaryAction: open)
            item.menuRepresentation = open
            item.accessibilityLabel = spoken
            floatingGlyph = nil
        }
        item.accessibilityTraits = .link
        item.accessibilityIdentifier = identifier
        item.tintColor = chrome.isVerticalBar ? .systemBlue : BrandUIColors.textPrimary
        UKRootChrome.applyRailPriority(.songDetailAction, to: item, chrome: chrome)
        return UKPageTool(order: PageToolOrder.primary, item: item, floatingGlyph: floatingGlyph)
    }
}
#endif
