#if os(iOS)
import FestivalCore
import FestivalDesign
import OSLog
import UIKit

// MARK: - Song List preview

/// Read-only guide demos using native rows, artwork and the bounded catalogue.
/// The enclosing slide, not its decorative rows, is a VoiceOver stop.
@MainActor
final class UKFirstRunSongListPreview: UIView {
    private static let rowSpacing: CGFloat = 8
    private static let logger = Logger(subsystem: "com.sfenton.festivalscoretracker", category: "FirstRun")

    /// The catalogue presentation and sample values for a guide slide.
    enum Kind {
        case songList, instrumentIcons, metadata
        case shop(FirstRunDemoSongs.ShopPreview)
        case itemShopOverview
        case itemShopRows(ShopHighlight?)
        case songDetailShop(ShopStatusTone)
        case rankedSongs
        case suggestions(UKFirstRunSuggestionsPreview.Mode)
        case rivalDetail

        var visibleCount: Int {
            switch self {
            case .songList, .shop: 3
            case .instrumentIcons: 2
            case .metadata, .songDetailShop: 1
            case .itemShopOverview, .itemShopRows(.some): 6
            case .itemShopRows(nil): 4
            case .rankedSongs: FirstRunStatisticsSamples.topSongPercentiles.count
            case let .suggestions(mode): mode.songCount
            case .rivalDetail: UKFirstRunRivalDetailPreview.rowCount
            }
        }

        var rotates: Bool {
            switch self {
            case .songList, .instrumentIcons, .metadata, .rankedSongs, .rivalDetail: true
            case .shop, .itemShopOverview, .itemShopRows, .songDetailShop, .suggestions: false
            }
        }

        func entranceDelay(at index: Int) -> TimeInterval? {
            switch self {
            case .itemShopOverview: Double(index) * FirstRunMotion.tileStaggerSeconds
            case .itemShopRows: Double(index) * FirstRunMotion.rowStaggerSeconds
            case .rankedSongs: Double(index + 1) * FirstRunMotion.staggerSeconds
            default: nil
            }
        }

        var prefersShop: Bool {
            switch self {
            case .itemShopOverview, .itemShopRows: true
            default: false
            }
        }

        func shopPhase(at index: Int) -> FirstRunShopRowPhase {
            switch self {
            case let .shop(preview):
                return preview.highlight(at: index).map(FirstRunShopRowPhase.highlighted) ?? .plain
            case let .itemShopRows(highlight):
                return .phase(at: index, highlight: highlight)
            default:
                return .plain
            }
        }

        @MainActor func example(for song: Song) -> UKSongRowView.GuideExample? {
            switch self {
            case .songList, .shop, .itemShopOverview, .itemShopRows, .songDetailShop, .rankedSongs, .suggestions, .rivalDetail:
                return nil
            case .instrumentIcons:
                return .instrumentIcons(
                    SongInstrumentBadge.demoPattern(title: song.title, instruments: FirstRunNativeIconsDemo.instruments)
                )
            case .metadata:
                let meta = FirstRunSongMetadataExample.meta(for: song)
                return .metadata(score: meta.score, fields: meta.pills)
            }
        }
    }

    @MainActor private struct Slot {
        enum Content {
            case song(UKSongRowView, UKFirstRunSongSkeleton)
            case ranked(UKFirstRunRankedSongRow)
        }

        let card = UKCardView(cornerRadius: 12)
        let pulse = UKRowPulseBorderView()
        let content: Content
        var height: CGFloat = 64

        init(kind: Kind, index: Int) {
            card.translatesAutoresizingMaskIntoConstraints = true
            if case .rankedSongs = kind {
                let row = UKFirstRunRankedSongRow(percentile: FirstRunStatisticsSamples.topSongPercentiles[index])
                card.contentView.addSubview(row)
                content = .ranked(row)
            } else {
                let row = UKSongRowView()
                let skeleton = UKFirstRunSongSkeleton()
                row.isHidden = true
                card.contentView.addSubview(row)
                card.contentView.addSubview(skeleton)
                content = .song(row, skeleton)
            }
            card.addSubview(pulse)
            pulse.isHidden = true
        }
    }

    private let session: FestivalSession
    private let kind: Kind
    private let grid: UKFirstRunAlbumGrid?
    private let shopHeader: UKFirstRunShopHeader?
    private let suggestions: UKFirstRunSuggestionsPreview?
    private let rivalDetail: UKFirstRunRivalDetailPreview?
    private let networkObservation = UKObservationBag()
    private var settingsObserver: UKAccessibilityObserver?
    nonisolated(unsafe) private var sceneObservers: [NSObjectProtocol] = []
    private var slots: [Slot] = []
    private var rotation: FirstRunRowRotation<Song>?
    private var loadTask: Task<Void, Never>?
    private var rotationTask: Task<Void, Never>?
    private var rivalPhase = 0
    private var isActive = false
    private var mayLoadArtwork = false
    private var configuredWidth: CGFloat = 0

    /// Tiles or cards that play a staggered guide entrance, in visual order.
    var entrances: [(view: UIView, delay: TimeInterval)] {
        if let suggestions { return suggestions.entrances }
        if let rivalDetail { return rivalDetail.entrances }
        return (grid?.tiles ?? slots.map(\.card)).enumerated().compactMap { index, view in
            kind.entranceDelay(at: index).map { (view, $0) }
        }
    }

    /// - Parameters:
    ///   - session: The shared catalogue and ephemeral image cache.
    ///   - kind: The catalogue preview to render.
    ///   - layout: Window layout used by the Song Detail Shop action.
    init(session: FestivalSession, kind: Kind = .songList, layout: @escaping () -> DeviceLayout = { .standardPhone }) {
        self.session = session
        self.kind = kind
        if case .itemShopOverview = kind {
            grid = UKFirstRunAlbumGrid(count: kind.visibleCount)
        } else {
            grid = nil
        }
        if case let .songDetailShop(tone) = kind {
            shopHeader = UKFirstRunShopHeader(tone: tone, layout: layout)
        } else {
            shopHeader = nil
        }
        if case let .suggestions(mode) = kind {
            suggestions = UKFirstRunSuggestionsPreview(session: session, mode: mode)
        } else {
            suggestions = nil
        }
        if case .rivalDetail = kind {
            rivalDetail = UKFirstRunRivalDetailPreview(session: session)
        } else {
            rivalDetail = nil
        }
        super.init(frame: .zero)
        clipsToBounds = true
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        if let grid { addSubview(grid) }
        if let shopHeader { ukPin(shopHeader) }
        if let suggestions { ukPin(suggestions) }
        if let rivalDetail { ukPin(rivalDetail) }
        for index in 0..<(grid == nil && shopHeader == nil && suggestions == nil && rivalDetail == nil ? kind.visibleCount : 0) {
            let slot = Slot(kind: kind, index: index)
            addSubview(slot.card)
            slots.append(slot)
        }
        settingsObserver = UKAccessibilityObserver { [weak self] in
            self?.refreshPlayback()
            self?.shopHeader?.updateAction()
        }
        networkObservation.observe { [weak self] in
            _ = ArtworkNetworkStatus.shared.isConstrained
            self?.refreshPlayback()
        }
        let center = NotificationCenter.default
        sceneObservers = [UIScene.didActivateNotification, UIScene.willDeactivateNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let scene = note.object as? UIScene else { return }
                let sceneID = ObjectIdentifier(scene)
                MainActor.assumeIsolated {
                    guard let self, let scene = self.window?.windowScene, ObjectIdentifier(scene) == sceneID else { return }
                    self.refreshPlayback(sceneActive: name == UIScene.didActivateNotification)
                }
            }
        }
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKFirstRunSongListPreview, _) in
            self.configureContent()
        }
        registerForTraitChanges([UITraitAccessibilityContrast.self]) { (self: UKFirstRunSongListPreview, _) in
            self.refreshPlayback()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        sceneObservers.forEach { NotificationCenter.default.removeObserver($0) }
        loadTask?.cancel()
        rotationTask?.cancel()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refreshPlayback()
    }

    /// - Parameter active: Whether the guide is stopped on this slide.
    func setActive(_ active: Bool) {
        isActive = active
        refreshPlayback()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let grid { grid.frame = bounds }
        if configuredWidth != bounds.width { configureContent() }
        let visible = slots.filter { !$0.card.isHidden }
        let height = visible.reduce(0) { $0 + $1.height } + Self.rowSpacing * CGFloat(max(0, visible.count - 1))
        let centeredY = (bounds.height - height) / 2
        var y = if case .rankedSongs = kind { centeredY } else { max(0, centeredY) }
        for slot in visible {
            slot.card.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: slot.height)
            slot.card.center = CGPoint(x: bounds.midX, y: y + slot.height / 2)
            switch slot.content {
            case let .song(row, skeleton):
                row.frame = slot.card.bounds
                skeleton.frame = slot.card.bounds
            case let .ranked(row):
                row.frame = slot.card.bounds
            }
            slot.pulse.frame = slot.card.bounds
            y += slot.height + Self.rowSpacing
        }
    }

    // MARK: - Data and motion

    private func refreshPlayback(sceneActive: Bool? = nil) {
        let visible = isActive && (sceneActive ?? (window?.windowScene?.activationState == .foregroundActive))
        let constrained = ArtworkNetworkStatus.shared.isConstrained
        let artEnabled = visible && !constrained && !UKAccessibility.cardIsOpaque
        if artEnabled != mayLoadArtwork {
            mayLoadArtwork = artEnabled
            configureContent()
        }
        suggestions?.setPlayback(
            enabled: artEnabled && !UKAccessibility.reduceMotion && !DebugAnimationOverride.stillBackground,
            hardEdge: UKAccessibility.hardEdge(traitCollection)
        )
        configurePulses()
        if visible, rotation == nil, loadTask == nil {
            let visibleCount = kind.visibleCount
            let count = kind.rotates ? FirstRunDemoSongs.rotationPoolSize : visibleCount
            let prefersShop = kind.prefersShop
            loadTask = Task { [weak self, session] in
                do {
                    let payload = try await session.catalog()
                    try Task.checkCancellation()
                    let songs = session.firstRunDemoSongs(from: payload, count: count, prefersShop: prefersShop)
                    guard let self, !songs.isEmpty else { return }
                    self.rotation = FirstRunRowRotation(pool: songs, visible: visibleCount)
                    self.configureContent()
                    self.refreshPlayback()
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    Self.logger.notice("Guide catalogue preview kept its placeholders: \(String(describing: error), privacy: .private)")
                }
            }
        } else if !visible {
            loadTask?.cancel()
            loadTask = nil
        }
        let runs = FirstRunDemoTickerPolicy.runs(
            active: artEnabled, enabled: kind.rotates && rotation?.canRotate == true, constrained: constrained,
            reduceMotion: UKAccessibility.reduceMotion, stillBackground: DebugAnimationOverride.stillBackground
        )
        if runs, rotationTask == nil {
            rotationTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: FirstRunDemoTiming.swapInterval) } catch { return }
                    guard let self else { return }
                    await self.swap()
                }
            }
        } else if !runs, let rotationTask {
            rotationTask.cancel()
            self.rotationTask = nil
            for slot in slots {
                slot.card.layer.removeAllAnimations()
                slot.card.alpha = 1
            }
            if let rivalDetail {
                rivalDetail.layer.removeAllAnimations()
                rivalDetail.alpha = 1
                rivalDetail.transform = .identity
                rivalDetail.stagger(animated: false)
            }
        }
    }

    private func swap() async {
        guard var next = rotation else { return }
        let indices = next.nextSwap()
        guard !indices.isEmpty else { return }
        let cards: [UIView] = if let rivalDetail { [rivalDetail] } else { indices.map { slots[$0].card } }
        animateOpacity(of: cards, to: 0, drop: rivalDetail == nil ? 0 : 4)
        do { try await Task.sleep(for: FirstRunDemoTiming.fade) } catch { return }
        next.replace(indices)
        rotation = next
        if let rivalDetail {
            rivalPhase += 1
            configureContent()
            rivalDetail.stagger(animated: true)
        } else {
            for index in indices { configure(slot: index) }
        }
        setNeedsLayout()
        animateOpacity(of: cards, to: 1)
    }

    private func animateOpacity(of cards: [UIView], to alpha: CGFloat, drop: CGFloat = 0) {
        let timing = UICubicTimingParameters(controlPoint1: CGPoint(x: 0.25, y: 0.1), controlPoint2: CGPoint(x: 0.25, y: 1))
        let animator = UIViewPropertyAnimator(duration: FirstRunDemoTiming.fadeSeconds, timingParameters: timing)
        let offset = rivalDetail == nil ? nil : drop
        animator.addAnimations {
            for card in cards {
                card.alpha = alpha
                if let offset { card.transform = CGAffineTransform(translationX: 0, y: offset) }
            }
        }
        animator.startAnimation()
    }

    private func configureContent() {
        guard bounds.width > 0 else { return }
        configuredWidth = bounds.width
        if let grid {
            grid.configure(rows: rotation?.rows, session: mayLoadArtwork ? session : nil)
            return
        }
        if let shopHeader {
            shopHeader.configure(song: rotation?.rows.first, session: session, allowsArtwork: mayLoadArtwork)
            return
        }
        if let suggestions {
            suggestions.configure(songs: rotation?.rows, allowsArtwork: mayLoadArtwork)
            return
        }
        if let rivalDetail {
            rivalDetail.configure(songs: rotation?.rows, phase: rivalPhase, session: session, allowsArtwork: mayLoadArtwork)
            return
        }
        for index in slots.indices { configure(slot: index) }
        configurePulses()
        setNeedsLayout()
    }

    private func configurePulses() {
        for index in slots.indices {
            let pulse = slots[index].pulse
            let phase = kind.shopPhase(at: index)
            guard phase != .plain else { continue }
            pulse.isHidden = false
            pulse.configure(
                tone: ShopStatusTone(highlight: phase.highlight), cornerRadius: 12,
                allowsMotion: mayLoadArtwork && rotation != nil && !UKAccessibility.reduceMotion
            )
        }
    }

    private func configure(slot index: Int) {
        let rows = rotation?.rows
        slots[index].card.isHidden = rows.map { !$0.indices.contains(index) } ?? false
        if case let .ranked(row) = slots[index].content {
            let song = rows.flatMap { $0.indices.contains(index) ? $0[index] : nil }
            row.configure(song: song, session: session, allowsArtwork: mayLoadArtwork)
            slots[index].height = row.preferredHeight
            return
        }
        guard case let .song(row, skeleton) = slots[index].content else { return }
        guard let rows, rows.indices.contains(index) else { return }
        var input = UKSongRowInput(song: rows[index], session: session)
        input.allowsArtwork = mayLoadArtwork
        input.showsProfile = false
        let phase = kind.shopPhase(at: index)
        input.shopHighlight = phase.highlight
        input.inShop = phase != .plain
        row.configure(input, width: configuredWidth, traits: traitCollection, guideExample: kind.example(for: input.song))
        row.isHidden = false
        skeleton.isHidden = true
        slots[index].height = row.height(forWidth: configuredWidth)
    }
}

// MARK: - Song Detail Shop action example

/// One catalogue header and a sample Shop glyph; the action never opens a link or reads offers.
private final class UKFirstRunShopHeader: UIView {
    private static let inset: CGFloat = 14
    private static let gap: CGFloat = 12
    private static let actionGap: CGFloat = 2 * gap + 8
    private static let artSize: CGFloat = 56
    private static let capsuleInset: CGFloat = 12
    private static let symbolGap: CGFloat = 8

    private let tone: ShopStatusTone
    private let layout: () -> DeviceLayout
    private let artwork = UKArtworkTileView(size: artSize)
    private let header = UKSongHeaderTextView(title: "", artist: "", titleFont: UKFont.font(.headline), spacing: 2)
    private let skeleton = UKFirstRunSongSkeleton(inset: 0, gap: gap, artSize: artSize)
    private let action = UIView()
    private var actionContent: UIView?
    private var titledActionParts: (title: UKLabel, icon: UIImageView)?
    private var style: SongDetailShopActionStyle?
    private var allowsMotion = false

    /// - Parameters:
    ///   - tone: The illustrative offer status, independent of the example song.
    ///   - layout: Window layout supplying the current toolbar orientation.
    init(tone: ShopStatusTone, layout: @escaping () -> DeviceLayout) {
        self.tone = tone
        self.layout = layout
        super.init(frame: .zero)
        let card = UKCardView(cornerRadius: 16)
        let row = UIStackView(arrangedSubviews: [artwork, header, action])
        row.spacing = Self.gap
        row.setCustomSpacing(Self.actionGap, after: header)
        row.alignment = .center
        let inset = Self.inset
        card.contentView.ukPin(row, insets: UIEdgeInsets(top: inset, left: inset, bottom: inset, right: inset))
        artwork.alpha = 0
        artwork.layer.cornerRadius = 8
        header.alpha = 0
        skeleton.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(skeleton)
        addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor), card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor),
            skeleton.leadingAnchor.constraint(equalTo: artwork.leadingAnchor),
            skeleton.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            skeleton.topAnchor.constraint(equalTo: row.topAnchor), skeleton.bottomAnchor.constraint(equalTo: row.bottomAnchor),
        ])
        updateAction()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateAction()
    }

    /// - Parameters:
    ///   - song: The bounded catalogue example; nil keeps the row redacted.
    ///   - session: The shared cache owner.
    ///   - allowsArtwork: Artwork and decorative motion are permitted for this visible slide.
    func configure(song: Song?, session: FestivalSession, allowsArtwork: Bool) {
        allowsMotion = allowsArtwork
        header.titleView.text = song?.title ?? ""
        header.artistView.text = song?.artist ?? ""
        header.titleView.animationEnabled = allowsArtwork
        header.artistView.animationEnabled = allowsArtwork
        artwork.configure(raw: allowsArtwork ? song?.albumArt : nil, session: session)
        artwork.alpha = song == nil ? 0 : 1
        header.alpha = song == nil ? 0 : 1
        skeleton.isHidden = song != nil
        updateAction()
    }

    /// Updates the inert action when the chrome or Shop highlighting setting changes.
    func updateAction() {
        let disabled = UKSettings.bool("fst.settings.disableShopHighlighting", default: false)
        let chrome = layout().sectionChrome
        let next = SongDetailShopActionStyle.resolve(tone: disabled ? nil : tone, chrome: chrome)
        if style != next {
            style = next
            actionContent?.removeFromSuperview()
            titledActionParts = nil
            let content: UIView
            switch next {
            case let .breathing(tone):
                let glyph = UKShopBreathingGlyphView(tone: tone)
                glyph.allowsMotion = allowsMotion
                content = glyph
            case .titled:
                content = titledAction()
            }
            actionContent = content
            action.ukPin(content)
        }
        wrapTitleIfNeeded()
        (actionContent as? UKShopBreathingGlyphView)?.allowsMotion = allowsMotion
    }

    private func titledAction() -> UIView {
        let pill = UKCardView(cornerRadius: 17, capsule: true)
        let icon = UIImageView(image: UIImage(systemName: "bag"))
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.subheadline, weight: .semibold))
        icon.tintColor = BrandUIColors.textPrimary
        icon.setContentCompressionResistancePriority(.required, for: .horizontal)
        let title = UKLabel("Item Shop", style: .subheadline, weight: .semibold, lines: 2)
        titledActionParts = (title, icon)
        let row = UIStackView(arrangedSubviews: [icon, title])
        row.spacing = Self.symbolGap
        row.alignment = .firstBaseline
        let inset = Self.capsuleInset
        pill.contentView.ukPin(row, insets: UIEdgeInsets(top: 4, left: inset, bottom: 4, right: inset))
        pill.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
        return pill
    }

    private func wrapTitleIfNeeded() {
        guard let (title, icon) = titledActionParts, bounds.width > 0 else { return }
        let inlineTitle = "Item Shop"
        let font: UIFont = title.font
        let titleWidth = ceil((inlineTitle as NSString).size(withAttributes: [.font: font]).width)
        let capsuleWidth = 2 * Self.capsuleInset + icon.intrinsicContentSize.width + Self.symbolGap + titleWidth
        let headerWidth = max(header.titleView.intrinsicContentSize.width, header.artistView.intrinsicContentSize.width)
        let remaining = bounds.width - 2 * Self.inset - Self.artSize - Self.gap - Self.actionGap
        let text = max(0, headerWidth) + capsuleWidth > remaining ? "Item\nShop" : inlineTitle
        if title.text != text { title.text = text }
    }
}

// MARK: - Ranked catalogue example

/// A compact, decorative Statistics row with a fixed illustrative percentile per slot.
private final class UKFirstRunRankedSongRow: UIView {
    private static let inset: CGFloat = 10
    private static let gap: CGFloat = 12
    private static let artSize: CGFloat = 44
    private let artwork = UKArtworkTileView(size: artSize)
    private let skeleton = UKFirstRunSongSkeleton(inset: inset, gap: gap)
    private let title = UKMarqueeLabel("", font: UKFont.font(.subheadline, weight: .semibold))
    private let subtitle = UKMarqueeLabel("", font: UKFont.font(.caption1))
    private let lines = UIStackView()
    private let rank: UKLabel

    /// - Parameter percentile: Illustrative top percentage for this slot, not a player score.
    init(percentile: Double) {
        let value = percentile.formatted(.number.precision(.fractionLength(1)))
        rank = UKLabel("Top \(value)%", style: .caption1, weight: .semibold, color: BrandUIColors.gold, lines: 1)
        super.init(frame: .zero)
        lines.axis = .vertical
        lines.spacing = 2
        lines.translatesAutoresizingMaskIntoConstraints = false
        for label in [title, subtitle] {
            label.wrapsAtAccessibilitySizes = false
            lines.addArrangedSubview(label)
        }
        rank.setContentCompressionResistancePriority(.required, for: .horizontal)
        rank.setContentHuggingPriority(.required, for: .horizontal)
        skeleton.translatesAutoresizingMaskIntoConstraints = false
        for child in [skeleton, artwork, lines, rank] { addSubview(child) }
        NSLayoutConstraint.activate([
            artwork.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.inset),
            artwork.centerYAnchor.constraint(equalTo: centerYAnchor),
            lines.leadingAnchor.constraint(equalTo: artwork.trailingAnchor, constant: Self.gap),
            lines.centerYAnchor.constraint(equalTo: centerYAnchor),
            lines.trailingAnchor.constraint(equalTo: rank.leadingAnchor, constant: -2 * Self.gap),
            rank.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.inset),
            rank.centerYAnchor.constraint(equalTo: centerYAnchor),
            skeleton.leadingAnchor.constraint(equalTo: leadingAnchor),
            skeleton.trailingAnchor.constraint(equalTo: lines.trailingAnchor, constant: Self.inset),
            skeleton.topAnchor.constraint(equalTo: topAnchor),
            skeleton.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The padded row fits the artwork and both lines at the current text size.
    var preferredHeight: CGFloat {
        2 * Self.inset + max(
            Self.artSize, rank.intrinsicContentSize.height,
            title.intrinsicContentSize.height + lines.spacing + subtitle.intrinsicContentSize.height
        )
    }

    /// - Parameters:
    ///   - song: The catalogue example, or nil to redact the artwork and song text.
    ///   - session: The shared artwork cache and service.
    ///   - allowsArtwork: Whether the active slide can load and animate decorative content.
    func configure(song: Song?, session: FestivalSession, allowsArtwork: Bool) {
        title.text = song?.title ?? ""
        subtitle.text = song.map(FirstRunStatisticsSamples.topSongSubtitle) ?? ""
        title.font = UKFont.font(.subheadline, weight: .semibold)
        subtitle.font = UKFont.font(.caption1)
        title.animationEnabled = allowsArtwork
        subtitle.animationEnabled = allowsArtwork
        artwork.configure(raw: allowsArtwork ? song?.albumArt : nil, session: session)
        artwork.isHidden = song == nil
        lines.isHidden = song == nil
        skeleton.isHidden = song != nil
    }
}

// MARK: - Item Shop overview

/// Three columns of decorative square album tiles; muted until catalogue artwork is usable.
private final class UKFirstRunAlbumGrid: UIView {
    private static let columns = 3
    private static let spacing: CGFloat = 8
    let tiles: [UIView]
    private var paths: [String?]?
    private var session: FestivalSession?
    private var renderedSide: CGFloat = 0

    init(count: Int) {
        tiles = (0..<count).map { _ in
            let tile = UIView()
            tile.backgroundColor = BrandUIColors.surfaceMuted
            tile.layer.cornerRadius = 8
            tile.layer.cornerCurve = .continuous
            tile.clipsToBounds = true
            return tile
        }
        super.init(frame: .zero)
        tiles.forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(rows: [Song]?, session: FestivalSession?) {
        let paths = rows?.map(\.albumArt)
        guard paths != self.paths || session !== self.session else { return }
        self.paths = paths
        self.session = session
        clearArtwork()
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let columns = Self.columns
        let stepSpacing = Self.spacing
        let side = (bounds.width - CGFloat(columns - 1) * stepSpacing) / CGFloat(columns)
        guard side > 0 else { return }
        if side != renderedSide {
            renderedSide = side
            clearArtwork()
        }
        let count = min(tiles.count, paths?.count ?? tiles.count)
        let rowCount = (count + columns - 1) / columns
        let height = CGFloat(rowCount) * side + CGFloat(max(0, rowCount - 1)) * stepSpacing
        let top = max(0, (bounds.height - height) / 2)
        for (index, tile) in tiles.enumerated() {
            tile.isHidden = index >= count
            guard index < count else { continue }
            tile.bounds = CGRect(x: 0, y: 0, width: side, height: side)
            tile.center = CGPoint(
                x: CGFloat(index % columns) * (side + stepSpacing) + side / 2,
                y: top + CGFloat(index / columns) * (side + stepSpacing) + side / 2
            )
            if tile.subviews.isEmpty, let session, let raw = paths?[index] {
                let artwork = UKArtworkTileView(size: side)
                artwork.translatesAutoresizingMaskIntoConstraints = true
                tile.addSubview(artwork)
                artwork.configure(raw: raw, session: session)
            }
        }
    }

    private func clearArtwork() {
        for tile in tiles { tile.subviews.forEach { $0.removeFromSuperview() } }
    }
}

// MARK: - Redacted row

/// Neutral Song List placeholder geometry; never renders or exposes an invented song.
private final class UKFirstRunSongSkeleton: UIView {
    private let tile = UIView()
    private let title = UIView()
    private let subtitle = UIView()
    private let inset: CGFloat
    private let gap: CGFloat
    private let artSize: CGFloat

    init(inset: CGFloat = UKSongRowView.padH, gap: CGFloat = UKSongRowView.padH, artSize: CGFloat = 44) {
        self.inset = inset
        self.gap = gap
        self.artSize = artSize
        super.init(frame: .zero)
        for (view, radius) in [(tile, CGFloat(8)), (title, 4), (subtitle, 4)] {
            view.backgroundColor = BrandUIColors.surfaceMuted
            view.layer.cornerRadius = radius
            view.layer.cornerCurve = .continuous
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        tile.frame = CGRect(x: inset, y: (bounds.height - artSize) / 2, width: artSize, height: artSize)
        let textX = tile.frame.maxX + gap
        let available = max(0, bounds.width - textX - inset)
        title.frame = CGRect(x: textX, y: bounds.midY - 14, width: min(154, available), height: 12)
        subtitle.frame = CGRect(x: textX, y: bounds.midY + 4, width: min(108, available), height: 10)
    }
}
#endif
