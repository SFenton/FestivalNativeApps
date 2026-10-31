#if os(iOS)
import FestivalCore
import FestivalDesign
@preconcurrency import ObjectiveC
import UIKit

// MARK: - Carousel

/// The native first-run carousel (``FirstRunCarouselView``): paged slides, white page dots,
/// Back at the leading edge of the bar from the second page on, a large prominent Next/Done
/// with Skip beneath it while pages remain. Only the pages actually shown are recorded in
/// ``viewing``. Close, swiping down and tapping outside the sheet all dismiss.
///
/// Each slide shows a page-themed illustration in place of the SwiftUI app's live mini-demo
/// (``FirstRunStaticIllustration``, the SwiftUI app's own fallback); the slide's title and
/// description carry the explanation.
@MainActor
final class UKFirstRunCarouselViewController: UIViewController, UIScrollViewDelegate {
    /// Fraction of the screen height the carousel covers (``FirstRunSheetStyle``).
    static let heightFraction: CGFloat = 0.86

    private let page: FirstRunPageKey
    private let slides: [FirstRunSlide]
    private let onFinish: () -> Void
    private let scroll = UIScrollView()
    private let slideStack = UIStackView()
    private var slideViews: [UKFirstRunSlideView] = []
    private let dots: UKFirstRunDots
    private let primary: UIButton
    private let skipRow = UIView()
    private let skip = UIButton(type: .system)
    private var index = 0
    private(set) var viewing: FirstRunViewing
    private lazy var backItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            title: "Back", image: UIImage(systemName: "chevron.backward"),
            primaryAction: UIAction { [weak self] _ in self?.goBack() }
        )
        item.accessibilityIdentifier = "fst.first-run.back"
        item.accessibilityLabel = "Back"
        return item
    }()

    /// Pages shown so far (the presenter marks only these seen when the sheet closes).
    var viewedSlides: [FirstRunSlide] { viewing.seenSlides(slides) }

    /// Creates the carousel.
    ///
    /// - Parameters:
    ///   - page: The page the guide explains.
    ///   - slides: The slides to show.
    ///   - onFinish: Called when the user closes via Done, Skip or Close; the caller dismisses.
    init(page: FirstRunPageKey, slides: [FirstRunSlide], onFinish: @escaping () -> Void) {
        self.page = page
        self.slides = slides
        self.onFinish = onFinish
        viewing = FirstRunViewing(slides: slides)
        dots = UKFirstRunDots(count: slides.count)
        primary = UKSettingsButtons.prominent(
            "Next", font: UKFont.font(.headline), identifier: "fst.first-run.next", verticalPadding: 12
        ) {}
        super.init(nibName: nil, bundle: nil)
        title = page.guideTitle
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        navigationItem.largeTitleDisplayMode = .never
        scroll.isPagingEnabled = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.bounces = false
        scroll.delegate = self
        scroll.translatesAutoresizingMaskIntoConstraints = false
        slideStack.axis = .horizontal
        slideStack.distribution = .fillEqually
        slideStack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(slideStack)
        for (position, slide) in slides.enumerated() {
            let slideView = UKFirstRunSlideView(page: page, slide: slide, layout: { [weak self] in self?.ukWindowLayout ?? .standardPhone })
            slideViews.append(slideView)
            slideStack.addArrangedSubview(slideView)
            slideView.setActive(position == 0, animated: false)
        }
        dots.isHidden = slides.count <= 1
        dots.onSelect = { [weak self] position in self?.go(to: position) }
        primary.addAction(UIAction { [weak self] _ in self?.primaryTapped() }, for: .touchUpInside)
        var skipConfig = UIButton.Configuration.plain()
        skipConfig.title = "Skip"
        skipConfig.baseForegroundColor = UKAccentText.blue
        skipConfig.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UKFont.font(.body)
            return attributes
        }
        skip.configuration = skipConfig
        skip.accessibilityIdentifier = "fst.first-run.skip"
        skip.translatesAutoresizingMaskIntoConstraints = false
        skip.addAction(UIAction { [weak self] _ in self?.onFinish() }, for: .touchUpInside)
        skipRow.translatesAutoresizingMaskIntoConstraints = false
        skipRow.addSubview(skip)
        NSLayoutConstraint.activate([
            skip.leadingAnchor.constraint(equalTo: skipRow.leadingAnchor), skip.trailingAnchor.constraint(equalTo: skipRow.trailingAnchor),
            skip.topAnchor.constraint(equalTo: skipRow.topAnchor), skip.bottomAnchor.constraint(equalTo: skipRow.bottomAnchor),
            skipRow.heightAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(FirstRunControls.minimumHeight)),
        ])
        let controls = UIStackView(arrangedSubviews: [primary, skipRow])
        controls.axis = .vertical
        controls.spacing = 4
        controls.translatesAutoresizingMaskIntoConstraints = false
        dots.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        view.addSubview(dots)
        view.addSubview(controls)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            slideStack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            slideStack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            slideStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            slideStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            slideStack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            slideStack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, multiplier: CGFloat(max(1, slides.count))),
            dots.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            dots.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            controls.topAnchor.constraint(equalTo: dots.bottomAnchor, constant: 12),
            controls.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            controls.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            controls.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -16),
        ])
        if slides.count <= 1 {
            // No dots: the controls follow the slides directly.
            dots.heightAnchor.constraint(equalToConstant: 0).isActive = true
        }
        updateControls()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Keep the page on rotation or a resize.
        let target = CGFloat(index) * scroll.bounds.width
        if scroll.bounds.width > 0, abs(scroll.contentOffset.x - target) > 1, !scroll.isDragging, !scroll.isDecelerating {
            scroll.contentOffset.x = target
        }
    }

    // MARK: Paging

    private var controls: FirstRunControls { FirstRunControls.forPage(index, of: slides.count) }

    private func primaryTapped() {
        if controls.primaryFinishes { onFinish() } else { go(to: index + 1) }
    }

    private func goBack() { go(to: max(0, index - 1)) }

    private func go(to position: Int) {
        guard slides.indices.contains(position) else { return }
        scroll.setContentOffset(CGPoint(x: CGFloat(position) * scroll.bounds.width, y: 0), animated: !UKAccessibility.reduceMotion)
        if UKAccessibility.reduceMotion { settle(on: position) }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settleFromOffset() }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { settleFromOffset() }

    private func settleFromOffset() {
        guard scroll.bounds.width > 0 else { return }
        settle(on: Int((scroll.contentOffset.x / scroll.bounds.width).rounded()))
    }

    private func settle(on position: Int) {
        guard slides.indices.contains(position), position != index || !slideViews[position].isActiveSlide else { return }
        index = position
        viewing.view(position, of: slides)
        for (slidePosition, slideView) in slideViews.enumerated() {
            slideView.setActive(slidePosition == position, animated: true)
        }
        dots.index = position
        updateControls()
        UIAccessibility.post(notification: .pageScrolled, argument: slideViews[position])
    }

    private func updateControls() {
        let state = controls
        primary.configuration?.title = state.primaryTitle
        primary.accessibilityIdentifier = state.primaryFinishes ? "fst.first-run.done" : "fst.first-run.next"
        skipRow.isHidden = !state.reservesSkipRow
        skip.isHidden = !state.showsSkip
        navigationItem.leftBarButtonItem = state.showsBack ? backItem : nil
        dots.index = index
    }
}

// MARK: - Page dots

/// White page dots: the current page solid, others translucent. One adjustable element reading
/// "Page, n of N"; tapping a dot jumps to that page.
@MainActor
final class UKFirstRunDots: UIView {
    private let count: Int
    private let dotViews: [UIView]
    /// Called with the tapped page.
    var onSelect: ((Int) -> Void)?
    /// The current page.
    var index = 0 {
        didSet {
            for (position, dot) in dotViews.enumerated() { dot.backgroundColor = UIColor.white.withAlphaComponent(position == index ? 1 : 0.35) }
            accessibilityValue = "\(index + 1) of \(count)"
        }
    }

    /// Creates the dots.
    ///
    /// - Parameter count: Number of pages.
    init(count: Int) {
        self.count = count
        dotViews = (0..<count).map { _ in
            let dot = UIView()
            dot.layer.cornerRadius = 4
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
            return dot
        }
        super.init(frame: .zero)
        let slots = dotViews.enumerated().map { position, dot -> UIView in
            let slot = UIView()
            slot.translatesAutoresizingMaskIntoConstraints = false
            slot.addSubview(dot)
            NSLayoutConstraint.activate([
                dot.centerXAnchor.constraint(equalTo: slot.centerXAnchor), dot.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
                slot.widthAnchor.constraint(equalToConstant: 20), slot.heightAnchor.constraint(equalToConstant: 24),
            ])
            slot.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
            slot.tag = position
            return slot
        }
        let row = UIStackView(arrangedSubviews: slots)
        row.axis = .horizontal
        row.spacing = 0
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityLabel = "Page"
        accessibilityIdentifier = "fst.first-run.dots"
        index = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
        if let tag = recognizer.view?.tag { onSelect?(tag) }
    }

    override func accessibilityIncrement() { onSelect?(min(count - 1, index + 1)) }
    override func accessibilityDecrement() { onSelect?(max(0, index - 1)) }
}

// MARK: - One slide

/// One slide's illustration, title and description as a single VoiceOver element; position is
/// announced by the page dots. Compact height and accessibility text sizes scroll.
@MainActor
final class UKFirstRunSlideView: UIView {
    private let page: FirstRunPageKey
    private let slide: FirstRunSlide
    private let layoutProvider: () -> DeviceLayout
    private let scroll = UIScrollView()
    private let content = UIStackView()
    private let demo = UKCardView(cornerRadius: 20)
    private let icon = UIImageView()
    private let titleLabel: UKLabel
    private let descriptionLabel: UKLabel
    private var demoHeight: NSLayoutConstraint!
    private var topConstraint: NSLayoutConstraint!
    /// Whether this slide is the page on screen.
    private(set) var isActiveSlide = false

    /// Creates the slide.
    ///
    /// - Parameters:
    ///   - page: The guide's page.
    ///   - slide: The slide.
    ///   - layout: The window layout provider (compact height shortens the demo).
    init(page: FirstRunPageKey, slide: FirstRunSlide, layout: @escaping () -> DeviceLayout) {
        self.page = page
        self.slide = slide
        layoutProvider = layout
        titleLabel = UKLabel(slide.title, style: .title2, weight: .bold, alignment: .center)
        descriptionLabel = UKLabel(slide.description, style: .subheadline, alignment: .center)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = false
        addSubview(scroll)
        icon.image = UIImage(systemName: page.firstRunSymbolName)
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 64, weight: .semibold)
        icon.tintColor = BrandUIColors.accentBlue
        icon.contentMode = .center
        icon.isAccessibilityElement = false
        demo.embed(icon)
        demo.isAccessibilityElement = false
        demo.accessibilityElementsHidden = true
        let demoHolder = UIView()
        demo.translatesAutoresizingMaskIntoConstraints = false
        demoHolder.addSubview(demo)
        NSLayoutConstraint.activate([
            demo.leadingAnchor.constraint(equalTo: demoHolder.leadingAnchor, constant: 20),
            demo.trailingAnchor.constraint(equalTo: demoHolder.trailingAnchor, constant: -20),
            demo.topAnchor.constraint(equalTo: demoHolder.topAnchor), demo.bottomAnchor.constraint(equalTo: demoHolder.bottomAnchor),
        ])
        demoHeight = demo.heightAnchor.constraint(equalToConstant: 260)
        demoHeight.isActive = true
        let texts = UIStackView(arrangedSubviews: [titleLabel, descriptionLabel])
        texts.axis = .vertical
        texts.spacing = 8
        let textHolder = UIView()
        texts.translatesAutoresizingMaskIntoConstraints = false
        textHolder.addSubview(texts)
        NSLayoutConstraint.activate([
            texts.leadingAnchor.constraint(equalTo: textHolder.leadingAnchor, constant: 28),
            texts.trailingAnchor.constraint(equalTo: textHolder.trailingAnchor, constant: -28),
            texts.topAnchor.constraint(equalTo: textHolder.topAnchor), texts.bottomAnchor.constraint(equalTo: textHolder.bottomAnchor),
        ])
        content.axis = .vertical
        content.spacing = 20
        content.addArrangedSubview(demoHolder)
        content.addArrangedSubview(textHolder)
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(content)
        topConstraint = content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 36)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            topConstraint,
            content.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -8),
        ])
        isAccessibilityElement = false
        scroll.isAccessibilityElement = true
        scroll.accessibilityTraits = .staticText
        scroll.accessibilityLabel = "\(slide.title). \(slide.description)"
        accessibilityElements = [scroll]
        updateMetrics()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitVerticalSizeClass.self]) { (self: UKFirstRunSlideView, _) in
            self.updateMetrics()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func updateMetrics() {
        let compact = layoutProvider().heightClass == .compact || UKFont.isAccessibilitySize(traitCollection)
        demoHeight.constant = compact ? 120 : 260
        topConstraint.constant = compact ? 8 : 36
        content.spacing = compact ? 12 : 20
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateMetrics()
    }

    /// Marks the slide as the page on screen: it plays its entrance (title and description
    /// fade in after the demo cascade) and is exposed to VoiceOver.
    ///
    /// - Parameters:
    ///   - active: Whether the slide is on screen.
    ///   - animated: Whether to play the entrance.
    func setActive(_ active: Bool, animated: Bool) {
        isActiveSlide = active
        accessibilityElementsHidden = !active
        guard active else { return }
        let animates = FirstRunMotion.entranceAnimates(reduceMotion: UKAccessibility.reduceMotion, stillBackground: DebugAnimationOverride.stillBackground)
        let delays = FirstRunMotion.textDelays(slideId: slide.id)
        for (label, delay) in [(titleLabel, delays.title), (descriptionLabel, delays.description)] {
            if animates && animated {
                label.alpha = 0
                UIView.animate(withDuration: 0.4, delay: delay, options: .curveEaseOut) { label.alpha = 1 }
            } else {
                label.alpha = 1
            }
        }
    }
}

// MARK: - Presentation

/// One carousel presentation: the slides offered, the pages actually viewed, and the
/// bookkeeping when it closes by any route (Done, Skip, Close, swipe or tap outside).
@MainActor
final class UKFirstRunPresentation: NSObject, UISheetPresentationControllerDelegate {
    private let carousel: UKFirstRunCarouselViewController
    private let navigation: UKSheetNavigationController
    private let slides: [FirstRunSlide]
    private var finished = false
    private let onClosed: ([FirstRunSlide]) -> Void

    /// Presents a carousel.
    ///
    /// - Parameters:
    ///   - page: The guide's page.
    ///   - slides: Slides offered.
    ///   - presenter: The controller to present from.
    ///   - onClosed: Runs once with the slides actually viewed, however the sheet closed.
    init(page: FirstRunPageKey, slides: [FirstRunSlide], presenter: UIViewController, onClosed: @escaping ([FirstRunSlide]) -> Void) {
        self.slides = slides
        self.onClosed = onClosed
        var finish: () -> Void = {}
        carousel = UKFirstRunCarouselViewController(page: page, slides: slides) { finish() }
        navigation = UKSheet.make(
            carousel, title: page.guideTitle, closeIdentifier: "fst.first-run.close", size: .large,
            regularWidth: presenter.traitCollection.horizontalSizeClass == .regular, onClose: { finish() }
        )
        super.init()
        finish = { [weak self] in self?.dismiss() }
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.custom(identifier: .init("fst.first-run")) { context in
                context.maximumDetentValue * UKFirstRunCarouselViewController.heightFraction
            }]
            sheet.prefersGrabberVisible = true
            sheet.delegate = self
        }
        objc_setAssociatedObject(navigation, &presentationKey, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        (presenter.presentedViewController ?? presenter).present(navigation, animated: true)
    }

    private func dismiss() {
        navigation.dismiss(animated: true) { [weak self] in self?.closed() }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { closed() }

    private func closed() {
        guard !finished else { return }
        finished = true
        onClosed(carousel.viewedSlides)
    }
}

nonisolated(unsafe) private var presentationKey: UInt8 = 0

// MARK: - Settings section

/// The Settings "First Run Guides" section (``FirstRunSettingsSection``): one "Show" row per
/// registered page that replays its entire slide catalog, ignoring gates and seen-state.
@MainActor
final class UKFirstRunSettingsSection: UIView {
    private let session: FestivalSession

    /// Creates the section.
    ///
    /// - Parameters:
    ///   - session: Shared session (first-run coordinator and seen-state store).
    ///   - titled: Show the section title (false on its own page).
    init(session: FestivalSession, titled: Bool = true) {
        self.session = session
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let section = UKSettingsSection("First Run Guides", subtitle: "Re-visit the first run experience for each page.", titled: titled)
        section.setRows(FirstRunSettingsSection.settingsOrder.map(row))
        section.translatesAutoresizingMaskIntoConstraints = false
        addSubview(section)
        NSLayoutConstraint.activate([
            section.leadingAnchor.constraint(equalTo: leadingAnchor), section.trailingAnchor.constraint(equalTo: trailingAnchor),
            section.topAnchor.constraint(equalTo: topAnchor), section.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func row(_ page: FirstRunPageKey) -> UIView {
        let label = UKSettingLabel(FirstRunSettingsSection.rowLabel(page))
        let button = UKSettingsButtons.prominent(
            "Show", font: UKFont.font(.subheadline, weight: .semibold), identifier: "fst.settings.first-run.\(page.rawValue)", verticalPadding: 6
        ) { [weak self] in self?.replay(page) }
        button.accessibilityLabel = "Show \(FirstRunSettingsSection.rowLabel(page)) guide"
        button.accessibilityHint = "Shows every first-run guide slide for \(FirstRunSettingsSection.rowLabel(page))"
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [label, button])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        return row
    }

    /// Reset the page's seen-state (as the web's `open()` calling `resetPage` first) and present
    /// its full, ungated slide catalog.
    private func replay(_ page: FirstRunPageKey) {
        guard let presenter = nearestViewController() else { return }
        let slides = FirstRunCatalog.slides(for: page)
        session.firstRunCenter.store.resetPage(slides.map(\.id))
        let replay = FirstRunSettingsSection.replaySlides(page)
        let center = session.firstRunCenter
        _ = UKFirstRunPresentation(page: page, slides: replay, presenter: presenter) { viewed in
            center.store.markSeen(viewed)
        }
    }
}

extension UIView {
    /// The view controller whose view contains this view.
    func nearestViewController() -> UIViewController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }
}

// MARK: - Page watcher

/// Shows a page's first-run carousel when the page appears and has unseen, gate-passing slides
/// (``FirstRunPageModifier``), re-evaluating when the selected player or an app setting a gate
/// depends on changes, and releasing the shared "one carousel at a time" slot when the page goes.
@MainActor
final class UKFirstRunPageWatcher {
    private let page: FirstRunPageKey
    private let session: FestivalSession
    private weak var host: UIViewController?
    private var presentation: UKFirstRunPresentation?
    private var shown: [FirstRunSlide] = []
    private let observations = UKObservationBag()
    nonisolated(unsafe) private var defaultsObserver: NSObjectProtocol?
    private var lastGate: [Bool]?
    private var visible = false

    /// Creates the watcher.
    ///
    /// - Parameters:
    ///   - page: The page whose catalogue to evaluate.
    ///   - session: Shared session.
    ///   - host: The page's controller, which presents the carousel.
    init(page: FirstRunPageKey, session: FestivalSession, host: UIViewController) {
        self.page = page
        self.session = session
        self.host = host
        observations.observe { [weak self] in
            _ = self?.session.selectedPlayer
            self?.evaluate()
        }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UKSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let gate = self.gateFlags()
                guard gate != self.lastGate else { return }
                self.evaluate()
            }
        }
    }

    deinit {
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
    }

    private func gateFlags() -> [Bool] {
        [
            UKSettings.bool("fst.settings.hideShop", default: false),
            UKSettings.bool("fst.settings.disableShopHighlighting", default: false),
            UKSettings.bool(ExperimentalRanks.storageKey, default: ExperimentalRanks.defaultValue),
        ]
    }

    /// The page appeared.
    func appeared() {
        visible = true
        evaluate()
    }

    /// The page went away: free the slot.
    func disappeared() {
        visible = false
        session.firstRunCenter.release(page.rawValue)
    }

    /// Recompute which slides (if any) should show, and claim the shared slot if so.
    func evaluate() {
        let center = session.firstRunCenter
        lastGate = gateFlags()
        guard visible, center.debugMode != .off, presentation == nil, let host, host.view.window != nil else { return }
        let flags = gateFlags()
        let context = FirstRunPresentationPolicy.gateContext(
            hasPlayer: session.selectedPlayer != nil, hideShop: flags[0], disableShopHighlighting: flags[1],
            experimentalRanks: flags[2], alwaysShow: center.debugMode == .force
        )
        let slides = FirstRunPresentationPolicy.slides(for: page, debugMode: center.debugMode, context: context, seen: center.store.load())
        guard !slides.isEmpty, center.claim(page.rawValue) else { return }
        shown = slides
        presentation = UKFirstRunPresentation(page: page, slides: slides, presenter: host) { [weak self] viewed in
            guard let self else { return }
            center.store.markSeen(viewed)
            center.release(page.rawValue)
            shown = []
            presentation = nil
        }
    }
}
#endif
