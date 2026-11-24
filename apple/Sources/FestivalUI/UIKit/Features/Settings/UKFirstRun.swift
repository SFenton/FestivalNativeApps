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
/// A slide displays its live UIKit preview where ported and the page's illustration otherwise.
@MainActor
final class UKFirstRunCarouselViewController: UIViewController, UIScrollViewDelegate {
    /// Fraction of the screen height the carousel covers (``FirstRunSheetStyle``).
    static let heightFraction: CGFloat = 0.86

    private let page: FirstRunPageKey
    private let slides: [FirstRunSlide]
    private let session: FestivalSession
    private let onFinish: () -> Void
    private let scroll = UIScrollView()
    private let slideStack = UIStackView()
    private var slideViews: [UKFirstRunSlideView] = []
    private let dots: UKFirstRunDots
    private let primary: UIButton
    private let skipRow = UIView()
    private let skip = UIButton(type: .system)
    private var index = 0
    private var enteringIndex: Int?
    private var pageWidth: CGFloat = 0
    private(set) var viewing: FirstRunViewing
    private lazy var backItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            title: "Back", image: UIImage(systemName: "chevron.backward"),
            primaryAction: UIAction { [weak self] _ in self?.goBack() }
        )
        item.tintColor = BrandUIColors.accentBlue
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
    ///   - session: The shared session used by live previews.
    ///   - onFinish: Called when the user closes via Done, Skip or Close; the caller dismisses.
    init(page: FirstRunPageKey, slides: [FirstRunSlide], session: FestivalSession, onFinish: @escaping () -> Void) {
        self.page = page
        self.slides = slides
        self.session = session
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
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.bounces = false
        scroll.delegate = self
        scroll.translatesAutoresizingMaskIntoConstraints = false
        slideStack.axis = .horizontal
        slideStack.distribution = .fillEqually
        slideStack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(slideStack)
        for (position, slide) in slides.enumerated() {
            let preview = UKFirstRunControllerPreview.make(for: slide.id)
            if let preview { addChild(preview.controller) }
            let slideView = UKFirstRunSlideView(page: page, slide: slide, session: session, preview: preview) { [weak self] in
                self?.ukWindowLayout ?? .standardPhone
            }
            slideViews.append(slideView)
            slideStack.addArrangedSubview(slideView)
            preview?.controller.didMove(toParent: self)
            slideView.setActive(position == 0, animated: false)
        }
        dots.isHidden = slides.count <= 1
        dots.onSelect = { [weak self] position in self?.go(to: position) }
        primary.addAction(UIAction { [weak self] _ in self?.primaryTapped() }, for: .touchUpInside)
        primary.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
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
            scroll.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: guide.topAnchor),
            slideStack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            slideStack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            slideStack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            slideStack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            slideStack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            slideStack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, multiplier: CGFloat(max(1, slides.count))),
            dots.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            dots.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
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
        let width = scroll.bounds.width
        guard width > 0, width != pageWidth else { return }
        pageWidth = width
        cancelEntrance()
        scroll.setContentOffset(CGPoint(x: CGFloat(index) * width, y: 0), animated: false)
    }

    // MARK: Paging

    private var controls: FirstRunControls { FirstRunControls.forPage(index, of: slides.count) }

    private func primaryTapped() {
        if controls.primaryFinishes { onFinish() } else { go(to: index + 1) }
    }

    private func goBack() { go(to: max(0, index - 1)) }

    private func go(to position: Int) {
        guard slides.indices.contains(position) else { return }
        let animated = !UKAccessibility.reduceMotion
        if animated { startEntrance(on: position) }
        scroll.setContentOffset(CGPoint(x: CGFloat(position) * scroll.bounds.width, y: 0), animated: animated)
        if !animated { settle(on: position) }
    }

    func scrollViewWillEndDragging(
        _ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>
    ) {
        guard scrollView.bounds.width > 0 else { return }
        startEntrance(on: Int((targetContentOffset.pointee.x / scrollView.bounds.width).rounded()))
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { settleFromOffset() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settleFromOffset() }
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { settleFromOffset() }

    /// Starts the visual entrance while keeping focus and viewed-slide accounting on the settled page.
    private func startEntrance(on position: Int) {
        guard slides.indices.contains(position), position != index, position != enteringIndex else { return }
        cancelEntrance()
        enteringIndex = position
        slideViews[position].beginEntrance()
    }

    private func cancelEntrance() {
        guard let position = enteringIndex else { return }
        enteringIndex = nil
        slideViews[position].setActive(false, animated: false)
    }

    private func settleFromOffset() {
        guard scroll.bounds.width > 0 else { return }
        settle(on: Int((scroll.contentOffset.x / scroll.bounds.width).rounded()))
    }

    private func settle(on position: Int) {
        guard slides.indices.contains(position) else { return }
        guard position != index || !slideViews[position].isActiveSlide else {
            cancelEntrance()
            return
        }
        let entranceStarted = enteringIndex == position
        enteringIndex = nil
        index = position
        viewing.view(position, of: slides)
        for (slidePosition, slideView) in slideViews.enumerated() {
            let active = slidePosition == position
            slideView.setActive(active, animated: true, keepsEntrance: active && entranceStarted)
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
    private let slide: FirstRunSlide
    private let layoutProvider: () -> DeviceLayout
    private let scroll = UIScrollView()
    private let content = UIStackView()
    private let cataloguePreview: UKFirstRunSongListPreview?
    private let rankingsPreview: UKFirstRunRankingsPreview?
    private let competitionPreview: UKFirstRunCompetitionPreview?
    private let statisticsPreview: UKFirstRunStatisticsPreview?
    private let songChartPreview: UKFirstRunSongChartPreview?
    private let pathsPreview: UKFirstRunPathsPreview?
    private let historyRows: [UKBoardScoreHistoryRowView]
    private let titleLabel: UKLabel
    private let descriptionLabel: UKLabel
    private var compactDemoConstraints: [NSLayoutConstraint] = []
    private var regularDemoConstraints: [NSLayoutConstraint] = []
    /// Whether this slide is the page on screen.
    private(set) var isActiveSlide = false

    /// Creates the slide.
    ///
    /// - Parameters:
    ///   - page: The guide's page.
    ///   - slide: The slide.
    ///   - session: The session supplying catalogue songs for previews.
    ///   - preview: An optional read-only preview with its child already attached.
    ///   - layout: The window layout provider (compact height shortens the demo).
    init(
        page: FirstRunPageKey, slide: FirstRunSlide, session: FestivalSession,
        preview: UKFirstRunControllerPreview?, layout: @escaping () -> DeviceLayout
    ) {
        self.slide = slide
        cataloguePreview = switch slide.id {
        case "songs-song-list": UKFirstRunSongListPreview(session: session)
        case "songs-icons": UKFirstRunSongListPreview(session: session, kind: .instrumentIcons)
        case "songs-metadata": UKFirstRunSongListPreview(session: session, kind: .metadata)
        case "songs-shop-highlight": UKFirstRunSongListPreview(session: session, kind: .shop(.highlights))
        case "songs-new-in-shop": UKFirstRunSongListPreview(session: session, kind: .shop(.new))
        case "songs-leaving-tomorrow": UKFirstRunSongListPreview(session: session, kind: .shop(.leaving))
        case "songinfo-shop-button": UKFirstRunSongListPreview(session: session, kind: .songDetailShop(.inShop), layout: layout)
        case "songinfo-new-in-shop": UKFirstRunSongListPreview(session: session, kind: .songDetailShop(.new), layout: layout)
        case "songinfo-leaving-tomorrow": UKFirstRunSongListPreview(session: session, kind: .songDetailShop(.leaving), layout: layout)
        case "suggestions-category-card": UKFirstRunSongListPreview(session: session, kind: .suggestions(.category))
        case "suggestions-infinite-scroll": UKFirstRunSongListPreview(session: session, kind: .suggestions(.scrolling))
        case "rivals-detail": UKFirstRunSongListPreview(session: session, kind: .rivalDetail)
        case "shop-overview": UKFirstRunSongListPreview(session: session, kind: .itemShopOverview)
        case "shop-highlighting": UKFirstRunSongListPreview(session: session, kind: .itemShopRows(nil))
        case "shop-new-items": UKFirstRunSongListPreview(session: session, kind: .itemShopRows(.new))
        case "shop-leaving-tomorrow": UKFirstRunSongListPreview(session: session, kind: .itemShopRows(.leavingTomorrow))
        case "statistics-top-songs": UKFirstRunSongListPreview(session: session, kind: .rankedSongs)
        default: nil
        }
        rankingsPreview = UKFirstRunRankingsPreview(slideID: slide.id)
        competitionPreview = UKFirstRunCompetitionPreview(slideID: slide.id)
        statisticsPreview = UKFirstRunStatisticsPreview(slideID: slide.id, layout: layout)
        songChartPreview = UKFirstRunSongChartPreview(slideID: slide.id)
        pathsPreview = slide.id == "songinfo-paths" ? UKFirstRunPathsPreview(layout: layout) : nil
        historyRows = slide.id == "playerhistory-score-list" ? Self.makeHistoryRows() : []
        layoutProvider = layout
        titleLabel = UKLabel(slide.title, style: .title2, weight: .bold, alignment: .center)
        descriptionLabel = UKLabel(slide.description, style: .subheadline, alignment: .center)
        super.init(frame: .zero)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 2
        descriptionLabel.attributedText = NSAttributedString(string: slide.description, attributes: [.paragraphStyle: paragraph])
        translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = false
        scroll.contentInsetAdjustmentBehavior = .never
        addSubview(scroll)
        let demo: UIView
        if let cataloguePreview {
            demo = cataloguePreview
        } else if let rankingsPreview {
            demo = rankingsPreview
        } else if let competitionPreview {
            demo = competitionPreview
        } else if let statisticsPreview {
            demo = statisticsPreview
        } else if let songChartPreview {
            demo = songChartPreview
        } else if let pathsPreview {
            demo = pathsPreview
        } else if !historyRows.isEmpty {
            let preview = UIView()
            preview.clipsToBounds = true
            let rows = UIStackView(arrangedSubviews: historyRows)
            rows.axis = .vertical
            rows.spacing = 8
            rows.translatesAutoresizingMaskIntoConstraints = false
            preview.addSubview(rows)
            let top = rows.topAnchor.constraint(greaterThanOrEqualTo: preview.topAnchor)
            let center = rows.centerYAnchor.constraint(equalTo: preview.centerYAnchor)
            center.priority = .defaultHigh
            NSLayoutConstraint.activate([
                rows.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
                rows.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
                top, center,
            ])
            demo = preview
        } else if let preview {
            demo = preview
        } else {
            let card = UKCardView(cornerRadius: 20)
            let icon = UIImageView(image: UIImage(systemName: page.firstRunSymbolName))
            icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 64, weight: .semibold)
            icon.tintColor = BrandUIColors.accentBlue
            icon.contentMode = .center
            card.embed(icon)
            demo = card
        }
        demo.translatesAutoresizingMaskIntoConstraints = false
        demo.isAccessibilityElement = false
        demo.accessibilityElementsHidden = true
        demo.isUserInteractionEnabled = false
        let demoHolder = UIView()
        demo.translatesAutoresizingMaskIntoConstraints = false
        demoHolder.addSubview(demo)
        NSLayoutConstraint.activate([
            demo.leadingAnchor.constraint(equalTo: demoHolder.leadingAnchor, constant: 20),
            demo.trailingAnchor.constraint(equalTo: demoHolder.trailingAnchor, constant: -20),
            demo.topAnchor.constraint(equalTo: demoHolder.topAnchor), demo.bottomAnchor.constraint(equalTo: demoHolder.bottomAnchor),
        ])
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
        let topInset = content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 36)
        topInset.priority = UILayoutPriority(249)
        // On short viewports, give the full narration priority over the decorative insets.
        let fitNarration = content.bottomAnchor.constraint(lessThanOrEqualTo: scroll.frameLayoutGuide.bottomAnchor)
        fitNarration.priority = .defaultLow
        let fillViewport = content.bottomAnchor.constraint(equalTo: scroll.frameLayoutGuide.bottomAnchor, constant: -20)
        fillViewport.priority = UILayoutPriority(248)
        compactDemoConstraints = [
            demo.heightAnchor.constraint(equalToConstant: 120),
            content.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
        ]
        regularDemoConstraints = [
            demo.heightAnchor.constraint(greaterThanOrEqualToConstant: 170),
            demo.heightAnchor.constraint(lessThanOrEqualToConstant: 320),
            fitNarration, topInset, fillViewport,
        ]
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.topAnchor.constraint(greaterThanOrEqualTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
            scroll.contentLayoutGuide.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
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
        competitionPreview?.setCompact(compact)
        if compact {
            NSLayoutConstraint.deactivate(regularDemoConstraints)
            NSLayoutConstraint.activate(compactDemoConstraints)
        } else {
            NSLayoutConstraint.deactivate(compactDemoConstraints)
            NSLayoutConstraint.activate(regularDemoConstraints)
        }
        content.spacing = compact ? 12 : 20
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateMetrics()
    }

    /// Builds the same illustrative scores and shared columns as the SwiftUI guide, never
    /// the currently selected player's history.
    private static func makeHistoryRows() -> [UKBoardScoreHistoryRowView] {
        let entries = FirstRunDemoPool.ownHistory
        let columns = LeaderboardRowColumns.scoreHistory(entries.map(\.newScore))
        return entries.enumerated().map { index, entry in
            let row = UKBoardScoreHistoryRowView()
            row.apply(.init(
                entry: entry, isBest: index == 0, seasonColumn: false, currentSeason: nil,
                columns: columns, identifier: "fst.first-run.history.\(index)"
            ))
            return row
        }
    }

    /// Marks the slide as the page on screen: it plays its entrance (title and description
    /// fade in after the demo cascade) and is exposed to VoiceOver.
    ///
    /// - Parameters:
    ///   - active: Whether the slide is on screen.
    ///   - animated: Whether to play the entrance.
    ///   - keepsEntrance: Whether movement has already started this slide's entrance.
    func setActive(_ active: Bool, animated: Bool, keepsEntrance: Bool = false) {
        isActiveSlide = active
        accessibilityElementsHidden = !active
        cataloguePreview?.setActive(active)
        rankingsPreview?.setActive(active)
        competitionPreview?.setActive(active)
        statisticsPreview?.setActive(active)
        songChartPreview?.setActive(active)
        if !keepsEntrance { positionEntrance(visible: active, animated: active && animated) }
    }

    /// Plays the incoming content fade without exposing the moving slide to VoiceOver.
    func beginEntrance() {
        positionEntrance(visible: true, animated: true)
    }

    private func positionEntrance(visible: Bool, animated: Bool) {
        let motionEnabled = FirstRunMotion.entranceAnimates(
            reduceMotion: UKAccessibility.reduceMotion, stillBackground: DebugAnimationOverride.stillBackground
        )
        let delays = FirstRunMotion.textDelays(slideId: slide.id)
        func place(_ view: UIView, delay: Double) {
            Self.enter(view, delay: delay, visible: visible || !motionEnabled, animated: animated && motionEnabled)
        }
        for entrance in cataloguePreview?.entrances ?? [] {
            place(entrance.view, delay: entrance.delay)
        }
        if let rankingsPreview {
            for (index, item) in rankingsPreview.entranceItems.enumerated() {
                place(item, delay: Double(index) * rankingsPreview.staggerInterval)
            }
        }
        if let competitionPreview {
            for (index, item) in competitionPreview.entranceItems.enumerated() {
                place(item, delay: Double(index) * FirstRunMotion.rowStaggerSeconds)
            }
        }
        if let content = statisticsPreview?.entranceContent {
            place(content, delay: 0)
        }
        if let pathsPreview {
            place(pathsPreview.selectors, delay: 0)
            place(pathsPreview.path, delay: FirstRunMotion.staggerSeconds)
        }
        for (index, row) in historyRows.enumerated() {
            place(row, delay: Double(index) * FirstRunMotion.staggerSeconds)
        }
        place(titleLabel, delay: delays.title)
        place(descriptionLabel, delay: delays.description)
    }

    /// Positions an illustration before or after the carousel's staggered entrance.
    static func enter(_ view: UIView, delay: Double, visible: Bool, animated: Bool) {
        view.layer.removeAllAnimations()
        let held = animated || !visible
        view.alpha = held ? 0 : 1
        view.transform = held ? CGAffineTransform(translationX: 0, y: FirstRunDemoTiming.entranceRise) : .identity
        guard animated else { return }
        UIView.animate(withDuration: FirstRunDemoTiming.fadeSeconds, delay: delay, options: [.curveEaseOut, .beginFromCurrentState]) {
            view.alpha = 1
            view.transform = .identity
        }
    }
}

// MARK: - Embedded previews

/// An inert preview of a native form or tab bar, without the app's routes or actions.
@MainActor
final class UKFirstRunControllerPreview: UIView {
    let controller: UIViewController
    private let previewHeight: CGFloat
    private let bottomAligned: Bool

    /// Returns a read-only child controller preview with its reference height and alignment.
    ///
    /// - Parameter slideID: The guide slide's catalogue identifier.
    static func make(for slideID: String) -> UKFirstRunControllerPreview? {
        switch slideID {
        case "songs-sort":
            UKFirstRunControllerPreview(
                UKSongsSortSheetController(mode: .title, ascending: true, showShop: true, shopAvailable: true) { _, _ in },
                height: 420
            )
        case "songs-navigation":
            UKFirstRunControllerPreview(navigationDemo(), height: 150, bottomAligned: true)
        case "songs-filter":
            UKFirstRunControllerPreview(
                UKSongsFilterSheetController(.init(
                    appliedGeneral: SongGeneralFilter(shop: .availableOnly),
                    showShop: true, shopAvailable: true, availableDecades: [1970, 1980, 1990, 2000, 2010, 2020],
                    availableDurations: [], appliedPlayerFilter: SongPlayerScoreFilter(), appliedInstrument: .lead,
                    visibleInstruments: Set(Instrument.allCases), selectedPlayer: true, scoreAvailable: true,
                    invalidScoreFilteringEnabled: false, availableSeasons: []
                )) { _, _, _ in },
                height: 460
            )
        case "playerhistory-sort":
            UKFirstRunControllerPreview(UKPlayerHistorySortViewController(mode: .score, ascending: false) { _, _ in }, height: 420)
        case "suggestions-global-filter", "suggestions-instrument-filter":
            UKFirstRunControllerPreview(
                UKSuggestionsFilterViewController(
                    applied: SuggestionFilterSettings(),
                    visibleInstruments: slideID == "suggestions-global-filter" ? [] : [.lead, .bass, .drums, .vocals]
                ) { _ in },
                height: 460
            )
        default: nil
        }
    }

    private init(_ controller: UIViewController, height: CGFloat, bottomAligned: Bool = false) {
        self.controller = controller
        previewHeight = height
        self.bottomAligned = bottomAligned
        super.init(frame: .zero)
        clipsToBounds = true
    }

    /// Shows the same example tabs and initial selection as the SwiftUI guide.
    private static func navigationDemo() -> UITabBarController {
        let tabs = UITabBarController()
        tabs.viewControllers = FirstRunNativeNavigationDemo.tabs.enumerated().map { index, section in
            let page = UIViewController()
            page.view.backgroundColor = BrandUIColors.appBackground
            page.tabBarItem = UITabBarItem(title: section.title, image: UIImage(systemName: section.symbol), tag: index)
            return page
        }
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        tabs.tabBar.standardAppearance = appearance
        tabs.tabBar.scrollEdgeAppearance = appearance
        tabs.tabBar.accessibilityElementsHidden = true
        return tabs
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Embeds the preview after its controller joins the carousel's containment hierarchy.
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        guard superview != nil, let preview = controller.view, preview.superview == nil else { return }
        if let scroll = (controller as? any UKModalScrollProviding)?.ukModalScrollView {
            scroll.contentInsetAdjustmentBehavior = .never
            scroll.isScrollEnabled = false
            scroll.showsVerticalScrollIndicator = false
        }
        preview.layer.cornerRadius = 22
        preview.layer.cornerCurve = .continuous
        preview.layer.borderWidth = 1
        preview.layer.borderColor = BrandUIColors.glassBorder.cgColor
        preview.clipsToBounds = true
        preview.translatesAutoresizingMaskIntoConstraints = false
        addSubview(preview)
        NSLayoutConstraint.activate([
            preview.leadingAnchor.constraint(equalTo: leadingAnchor), preview.trailingAnchor.constraint(equalTo: trailingAnchor),
            preview.heightAnchor.constraint(equalToConstant: previewHeight),
            bottomAligned ? preview.bottomAnchor.constraint(equalTo: bottomAnchor)
                : preview.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
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
    ///   - session: The shared session used by live previews.
    ///   - presenter: The controller to present from.
    ///   - onClosed: Runs once with the slides actually viewed, however the sheet closed.
    init(page: FirstRunPageKey, slides: [FirstRunSlide], session: FestivalSession, presenter: UIViewController, onClosed: @escaping ([FirstRunSlide]) -> Void) {
        self.slides = slides
        self.onClosed = onClosed
        var finish: () -> Void = {}
        carousel = UKFirstRunCarouselViewController(page: page, slides: slides, session: session) { finish() }
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
            "Show", font: UKFont.font(.subheadline, weight: .semibold),
            identifier: "fst.settings.first-run.\(page.rawValue)", compactCapsule: true
        ) { [weak self] in self?.replay(page) }
        // The sheet already dims its backdrop. Keep the branded fill, as SwiftUI's explicit tint does.
        button.tintAdjustmentMode = .normal
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
        _ = UKFirstRunPresentation(page: page, slides: replay, session: session, presenter: presenter) { viewed in
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
        presentation = UKFirstRunPresentation(page: page, slides: slides, session: session, presenter: host) { [weak self] viewed in
            guard let self else { return }
            center.store.markSeen(viewed)
            center.release(page.rawValue)
            shown = []
            presentation = nil
        }
    }
}
#endif
