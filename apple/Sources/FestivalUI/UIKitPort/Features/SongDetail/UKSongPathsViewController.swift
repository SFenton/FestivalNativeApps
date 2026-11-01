#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Pane

/// One Paths pane (image or text): a spinner that fades in and out between charts, and the
/// loaded content (image viewport, activation cards or a status view with Retry) that fades
/// over it. Image and Text load independently.
@MainActor
private final class UKPathPane: UIView {
    let display: PathDisplayMode
    private(set) var content: UIView?
    private var spinner: UKLoadingView?

    init(display: PathDisplayMode) {
        self.display = display
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setSpinner(visible: true, fade: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Fills the pane with Auto Layout (the loading and status views opt out of autoresizing).
    private func pin(_ view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Shows or hides the spinner, fading over `fade` seconds.
    func setSpinner(visible: Bool, fade: TimeInterval) {
        if visible {
            guard spinner == nil else { return }
            let loading = UKLoadingView(accessibilityLabel: "Loading \(display.label.lowercased()) path", placement: .fill)
            loading.alpha = fade > 0 ? 0 : 1
            addSubview(loading)
            pin(loading)
            spinner = loading
            if fade > 0 { UIView.animate(withDuration: fade) { loading.alpha = 1 } }
        } else if let loading = spinner {
            spinner = nil
            if fade > 0 {
                UIView.animate(withDuration: fade, animations: { loading.alpha = 0 }, completion: { _ in loading.removeFromSuperview() })
            } else {
                loading.removeFromSuperview()
            }
        }
    }

    /// Replaces the content, fading the new one in (or out when nil).
    func setContent(_ view: UIView?, fade: TimeInterval) {
        let old = content
        content = view
        if let view {
            view.alpha = fade > 0 ? 0 : 1
            insertSubview(view, at: 0)
            pin(view)
            if fade > 0 { UIView.animate(withDuration: fade) { view.alpha = 1 } }
        }
        if let old {
            if fade > 0 {
                UIView.animate(withDuration: fade, animations: { old.alpha = 0 }, completion: { _ in old.removeFromSuperview() })
            } else {
                old.removeFromSuperview()
            }
        }
    }
}

// MARK: - Image viewport

/// The zoomable path image: scrolls both ways once zoomed wider than the viewport, centred
/// horizontally while it fits (`imageScroll`). Pinch changes the zoom, 1x to 3x.
private final class UKPathImageScrollView: UIScrollView {
    let imageView = UIImageView()
    private let image: CGImage
    var zoom: CGFloat = 1 { didSet { if zoom != oldValue { setNeedsLayout() } } }
    var onPinch: ((CGFloat, Bool) -> Void)?

    init(image: CGImage, label: String) {
        self.image = image
        super.init(frame: .zero)
        imageView.image = UIImage(cgImage: image)
        imageView.layer.minificationFilter = .trilinear
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = label
        imageView.accessibilityTraits = .image
        imageView.accessibilityIdentifier = "fst.paths.image"
        imageView.isUserInteractionEnabled = true
        addSubview(imageView)
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        alwaysBounceVertical = true
        accessibilityIdentifier = "fst.paths.image-viewport"
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:))))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let fit = min(1, bounds.width / CGFloat(image.width))
        let width = CGFloat(image.width) * fit * zoom
        let height = CGFloat(image.height) * fit * zoom
        let contentWidth = max(width, bounds.width)
        let before = contentSize
        contentSize = CGSize(width: contentWidth, height: max(height, bounds.height))
        imageView.frame = CGRect(x: (contentWidth - width) / 2, y: 0, width: width, height: height)
        if width <= bounds.width + 0.5, contentOffset.x != 0 { contentOffset.x = 0 }
        _ = before
    }

    private var origin: CGFloat = 1

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began: origin = zoom
        case .changed: onPinch?(min(3, max(1, origin * gesture.scale)), false)
        case .ended, .cancelled: onPinch?(min(3, max(1, origin * gesture.scale)), true)
        default: break
        }
    }
}

// MARK: - Page

/// The CHOpt Paths viewer (``SongPathsSheet``): the path image or activation table filling
/// the sheet, zoom controls in the bar, and a selector row (Instrument, Difficulty, View) at
/// the bottom. Image and Text load independently, so Side by Side (the iPhone Duo inner
/// display, iPad) shows both; switching reloads only the form that appears, fading through a
/// spinner (``PathSwitchTransition``). A Karaoke notice follows the first loaded chart.
final class UKSongPathsViewController: UIViewController, UKModalScrollProviding {
    private let song: Song
    private let context: UKContext
    private let instruments: [Instrument]
    private let warnAboutKaraoke: Bool
    private let defaultDisplay: PathDisplayMode
    private let coverage: FestivalModalCoverage

    private var instrument: Instrument
    private var difficulty = PathDifficulty.expert
    private var viewMode: PathViewMode
    private var shown: [PathDisplayMode: SongPathsLoadState] = [:]
    private var spinnerHidden: Set<PathDisplayMode> = []
    private var announcesSwitches = false
    private var retryRevision = 0
    private var zoom: CGFloat = 1
    private var warningConsidered = false
    private var requestKeys: [PathDisplayMode: String] = [:]
    private var tasks: [PathDisplayMode: Task<Void, Never>] = [:]
    private let observations = UKObservationBag()
    private var pullDowns: [UKPullDownToDismiss] = []
    private var lastShownMode: PathViewMode?

    private let panesHolder = UIView()
    private let imagePane = UKPathPane(display: .image)
    private let textPane = UKPathPane(display: .text)
    private let columns = UKHingeColumnsView()
    private let selectorHolder = UIView()
    private var selectorStack: UIView?
    private let zoomLabel = UILabel()

    /// The page's scroll view for the top edge fade: none (panes scroll independently).
    var ukModalScrollView: UIScrollView? { nil }

    /// Creates the viewer.
    ///
    /// - Parameters:
    ///   - song: The song.
    ///   - context: The page's context.
    ///   - instruments: Offered instruments (visible, non-Karaoke).
    ///   - firstInstrument: The initial instrument.
    ///   - defaultDisplay: Settings' Path Default View.
    ///   - warnAboutKaraoke: Karaoke is visible in Settings (the notice applies).
    ///   - coverage: Sheet or the whole window (the full-window cover pulls down to dismiss).
    ///   - viewMode: Initial View selection; defaults to `defaultDisplay`.
    init(
        song: Song, context: UKContext, instruments: [Instrument], firstInstrument: Instrument,
        defaultDisplay: PathDisplayMode, warnAboutKaraoke: Bool, coverage: FestivalModalCoverage, viewMode: PathViewMode? = nil
    ) {
        self.song = song
        self.context = context
        self.instruments = instruments
        self.warnAboutKaraoke = warnAboutKaraoke
        self.defaultDisplay = defaultDisplay
        self.coverage = coverage
        instrument = firstInstrument
        self.viewMode = viewMode ?? PathViewMode(defaultDisplay)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { tasks.values.forEach { $0.cancel() } }

    private var layout: DeviceLayout { ukWindowLayout }
    private var shownMode: PathViewMode { SongPathsPolicy.resolve(viewMode, layout: layout, fallback: defaultDisplay) }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        panesHolder.translatesAutoresizingMaskIntoConstraints = false
        selectorHolder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panesHolder)
        view.addSubview(selectorHolder)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            panesHolder.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            panesHolder.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            panesHolder.topAnchor.constraint(equalTo: view.topAnchor),
            selectorHolder.topAnchor.constraint(equalTo: panesHolder.bottomAnchor, constant: 10),
            selectorHolder.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            selectorHolder.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            selectorHolder.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12),
        ])
        columns.layoutProvider = { [weak self] in self?.layout ?? .standardPhone }
        columns.spacing = 16
        zoomLabel.font = UKFont.font(.subheadline, monospacedDigit: true)
        zoomLabel.textColor = BrandUIColors.textPrimary
        zoomLabel.adjustsFontForContentSizeCategory = true
        observations.observe { [weak self] in
            _ = self?.context.session.publicationRevision
            self?.refresh()
        }
        NotificationCenter.default.addObserver(self, selector: #selector(contentSizeChanged), name: UIContentSizeCategory.didChangeNotification, object: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let mode = shownMode
        if mode != lastShownMode { refresh() }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refresh()
    }

    @objc private func contentSizeChanged() { rebuildSelector(); rebuildPanes() }

    // MARK: Request keys

    private func key(for display: PathDisplayMode) -> String {
        "\(instrument.rawValue)|\(difficulty.rawValue)|\(display.rawValue)|\(context.session.publicationRevision)|\(retryRevision)|\(shownMode.displays.contains(display))"
    }

    /// Re-lays the panes and selector for the current mode, and (re)starts the loads whose
    /// request key changed (the two `.task(id:)` blocks of the SwiftUI sheet).
    private func refresh() {
        guard isViewLoaded else { return }
        let mode = shownMode
        if mode != lastShownMode {
            lastShownMode = mode
            rebuildPanes()
            rebuildSelector()
        }
        navigationItem.title = SongPathsSheet.title(for: instrument, pose: layout.pose)
        for display in PathDisplayMode.allCases {
            let newKey = key(for: display)
            guard requestKeys[display] != newKey else { continue }
            requestKeys[display] = newKey
            tasks[display]?.cancel()
            tasks[display] = Task { [weak self] in await self?.loadPath(display) }
        }
    }

    private func pane(_ display: PathDisplayMode) -> UKPathPane { display == .image ? imagePane : textPane }

    private func rebuildPanes() {
        let mode = shownMode
        panesHolder.subviews.forEach { $0.removeFromSuperview() }
        columns.leadingContent.subviews.forEach { $0.removeFromSuperview() }
        columns.trailingContent.subviews.forEach { $0.removeFromSuperview() }
        func place(_ pane: UKPathPane, in host: UIView) {
            pane.removeFromSuperview()
            host.addSubview(pane)
            pane.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                pane.leadingAnchor.constraint(equalTo: host.leadingAnchor), pane.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                pane.topAnchor.constraint(equalTo: host.topAnchor), pane.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            ])
        }
        if mode == .sideBySide {
            columns.translatesAutoresizingMaskIntoConstraints = false
            panesHolder.addSubview(columns)
            NSLayoutConstraint.activate([
                columns.leadingAnchor.constraint(equalTo: panesHolder.leadingAnchor), columns.trailingAnchor.constraint(equalTo: panesHolder.trailingAnchor),
                columns.topAnchor.constraint(equalTo: panesHolder.topAnchor), columns.bottomAnchor.constraint(equalTo: panesHolder.bottomAnchor),
            ])
            columns.layoutIfNeeded()
            place(imagePane, in: columns.leadingContent)
            place(textPane, in: columns.trailingContent)
        } else {
            let display = mode.displays[0]
            let single = pane(display)
            single.translatesAutoresizingMaskIntoConstraints = false
            single.removeFromSuperview()
            panesHolder.addSubview(single)
            NSLayoutConstraint.activate([
                single.leadingAnchor.constraint(equalTo: panesHolder.leadingAnchor), single.trailingAnchor.constraint(equalTo: panesHolder.trailingAnchor),
                single.topAnchor.constraint(equalTo: panesHolder.topAnchor), single.bottomAnchor.constraint(equalTo: panesHolder.bottomAnchor),
            ])
        }
        reconcileChrome()
    }

    // MARK: Loading

    private var systemTiming: PathSwitchTransition.Timing {
        PathSwitchTransition.timing(for: .image, reduceMotion: UKAccessibility.reduceMotion)
    }

    private func loadPath(_ display: PathDisplayMode) async {
        let instrument = instrument, difficulty = difficulty, song = song, session = context.session
        let requestedKey = key(for: display)
        guard shownMode.displays.contains(display) else {
            shown[display] = nil
            spinnerHidden.remove(display)
            pane(display).setContent(nil, fade: 0)
            pane(display).setSpinner(visible: true, fade: 0)
            if display == .image { resetZoom() }
            reconcileChrome()
            return
        }
        let timing = SongPathsSheet.switchTiming(
            for: display, systemReduceMotion: UIAccessibility.isReduceMotionEnabled, appReduceMotion: UKAccessibility.appReduceMotion
        )
        do {
            try await PathSwitchTransition.run(
                timing: timing, contentShown: shown[display] != nil, clock: ContinuousClock(),
                load: { try await SongPathsLoadState.fetch(display, instrument: instrument, difficulty: difficulty, song: song, session: session) },
                apply: { step in apply(step, display: display, instrument: instrument, difficulty: difficulty, timing: timing, requestedKey: requestedKey) }
            )
        } catch {
            // Cancelled by a newer selection, which now owns the pane.
        }
    }

    private func announces(_ display: PathDisplayMode) -> Bool {
        SongPathsSheet.announcesSwitch(of: display, in: shownMode, afterSwitch: announcesSwitches)
    }

    private func apply(
        _ step: PathSwitchTransition.Step<SongPathsLoadState>, display: PathDisplayMode, instrument: Instrument,
        difficulty: PathDifficulty, timing: PathSwitchTransition.Timing, requestedKey: String
    ) {
        let fade = timing.fadeSeconds
        let pane = pane(display)
        switch step {
        case .hideContent:
            shown[display] = nil
            pane.setContent(nil, fade: fade)
            reconcileChrome()
        case .showSpinner:
            if display == .image { resetZoom() }
            spinnerHidden.remove(display)
            pane.setSpinner(visible: true, fade: fade)
            if announces(display) {
                UIAccessibility.post(notification: .announcement, argument: SongPathsSheet.loadingAnnouncement(
                    instrument: instrument, difficulty: difficulty, display: display
                ))
            }
        case .hideSpinner:
            spinnerHidden.insert(display)
            pane.setSpinner(visible: false, fade: fade)
        case let .showContent(content):
            guard key(for: display) == requestedKey else { return }
            shown[display] = content
            pane.setContent(makeContent(content, display: display), fade: fade)
            reconcileChrome()
            if announces(display), let spoken = content.loadedAnnouncement(instrument: instrument, difficulty: difficulty) {
                UIAccessibility.post(notification: .announcement, argument: spoken)
            }
            presentWarningIfDue()
        }
    }

    // MARK: Content

    private func makeContent(_ state: SongPathsLoadState, display: PathDisplayMode) -> UIView {
        switch state {
        case let .failed(issue):
            let status = UKServiceStatusView(issue, title: "Path unavailable") { [weak self] in
                self?.retryRevision += 1
                self?.refresh()
            }
            status.accessibilityIdentifier = "fst.paths.error"
            return status
        case let .image(payload):
            let scroll = UKPathImageScrollView(image: payload.image, label: "\(instrument.label) \(difficulty.label) CHOpt path")
            scroll.zoom = zoom
            scroll.onPinch = { [weak self] value, ended in self?.setZoom(value, commit: ended) }
            installPullDown(scroll)
            return container(freshness: payload.publicationId, content: scroll)
        case let .text(payload):
            let scroll = UIScrollView()
            scroll.alwaysBounceVertical = true
            let stack = UIStackView()
            stack.axis = .vertical
            stack.spacing = 8
            // Names the chart and difficulty shown; the scroll view runs under the header
            // (its inset keeps the first card clear), like the SwiftUI ScrollView.
            scroll.accessibilityIdentifier = "fst.paths.text.\(instrument.rawValue).\(difficulty.rawValue)"
            stack.translatesAutoresizingMaskIntoConstraints = false
            scroll.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
                stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
                stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
                stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -12),
                stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            ])
            if payload.rows.isEmpty {
                let empty = UKLabel("Path data not available for this chart.", alignment: .center)
                stack.addArrangedSubview(empty)
            }
            for row in payload.rows { stack.addArrangedSubview(activationCard(row)) }
            installPullDown(scroll)
            return container(freshness: payload.publicationId, content: scroll)
        }
    }

    private func container(freshness publicationId: Int?, content: UIView) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        if publicationId == nil {
            stack.addArrangedSubview(UKFreshnessDisclosureView(message: "Showing live path without publication verification", symbol: "info.circle"))
        }
        stack.addArrangedSubview(content)
        return stack
    }

    private func installPullDown(_ scroll: UIScrollView) {
        guard coverage == .fullScreen else { return }
        pullDowns.append(UKPullDownToDismiss(scrollView: scroll) { [weak self] in self?.dismiss(animated: true) })
    }

    private func caption(_ text: String) -> UILabel {
        let label = UKLabel(text.uppercased(), style: .caption1, weight: .semibold)
        return label
    }

    private func activationCard(_ row: PathActivationRow) -> UIView {
        let card = UKCardView(cornerRadius: 12)
        let frets = UIStackView(arrangedSubviews: SongPathsActivation.frets.map { name in
            let square = UIView()
            let active = row.frets.contains(name)
            square.layer.cornerRadius = 4
            if active, let rgb = SongPathsActivation.fretRGB(name) {
                square.backgroundColor = UIColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
            } else {
                square.backgroundColor = BrandUIColors.surfaceMuted
                square.layer.borderWidth = 2
                square.layer.borderColor = BrandUIColors.borderSubtle.cgColor
            }
            square.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([square.widthAnchor.constraint(equalToConstant: 22), square.heightAnchor.constraint(equalToConstant: 22)])
            return square
        })
        frets.spacing = 4
        let note = UIStackView(arrangedSubviews: [caption("Note"), frets])
        note.axis = .vertical
        note.spacing = 8
        note.alignment = .leading

        func value(_ label: String, _ text: String?) -> UIView {
            let value = UKLabel(text ?? "\u{2014}", style: .body, weight: .semibold, monospacedDigit: true, lines: 1)
            value.adjustsFontSizeToFitWidth = true
            value.minimumScaleFactor = 0.8
            let column = UIStackView(arrangedSubviews: [caption(label), value])
            column.axis = .vertical
            column.spacing = 4
            return column
        }
        let values = UKPathValuesView(columns: [
            value("Beat", row.beat.formatted(.number.precision(.fractionLength(2)))),
            value("Time", SongPathsActivation.time(row.seconds)),
            value("Score", row.scoreBeforeActivation?.formatted()),
        ])

        let overdrive: UIView
        if let amount = row.odPercent {
            overdrive = UKOverdriveBarView(percent: amount)
        } else {
            overdrive = UKLabel("\u{2014}", style: .body, weight: .semibold)
        }
        let od = UIStackView(arrangedSubviews: [caption("Overdrive"), overdrive])
        od.axis = .vertical
        od.spacing = 8
        od.alignment = .fill

        let column = UIStackView(arrangedSubviews: [note, values, od])
        column.axis = .vertical
        column.spacing = 16
        column.isUserInteractionEnabled = false
        card.embed(column, insets: UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16))
        card.isAccessibilityElement = true
        card.accessibilityLabel = "Activation \(row.number)"
        card.accessibilityValue = SongPathsActivation.spokenValue(row)
        card.accessibilityIdentifier = "fst.paths.activation.\(row.number)"
        return card
    }

    // MARK: Zoom

    private var showsZoom: Bool {
        guard shownMode.displays.contains(.image) else { return false }
        if case .image? = shown[.image] { return true }
        return false
    }

    private func setZoom(_ proposed: CGFloat, commit: Bool = true) {
        zoom = min(3, max(1, proposed))
        if let scroll = imagePane.content.flatMap(Self.imageScroll(in:)) { scroll.zoom = zoom }
        if commit { updateZoomItems() }
    }

    private func resetZoom() {
        zoom = 1
        if let scroll = imagePane.content.flatMap(Self.imageScroll(in:)) { scroll.zoom = 1 }
        updateZoomItems()
    }

    private static func imageScroll(in view: UIView) -> UKPathImageScrollView? {
        if let scroll = view as? UKPathImageScrollView { return scroll }
        return view.subviews.lazy.compactMap { imageScroll(in: $0) }.first
    }

    private func reconcileChrome() {
        updateZoomItems()
    }

    private func updateZoomItems() {
        guard showsZoom else {
            navigationItem.leftBarButtonItems = nil
            return
        }
        let percent = Int(zoom * 100)
        let out = UIBarButtonItem(title: "Zoom Out", image: UIImage(systemName: "minus.magnifyingglass"), primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            self.setZoom(self.zoom / 1.5)
        })
        out.isEnabled = zoom > 1
        out.accessibilityIdentifier = "fst.paths.zoom-out"
        out.accessibilityLabel = "Zoom Out"
        zoomLabel.text = "\(percent)%"
        zoomLabel.accessibilityLabel = "Zoom \(percent) percent"
        zoomLabel.sizeToFit()
        let label = UIBarButtonItem(customView: zoomLabel)
        let zoomIn = UIBarButtonItem(title: "Zoom In", image: UIImage(systemName: "plus.magnifyingglass"), primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            self.setZoom(self.zoom * 1.5)
        })
        zoomIn.isEnabled = zoom < 3
        zoomIn.accessibilityIdentifier = "fst.paths.zoom-in"
        zoomIn.accessibilityLabel = "Zoom In"
        navigationItem.leftBarButtonItems = [out, label, zoomIn]
    }

    // MARK: Karaoke notice

    private func presentWarningIfDue() {
        let dismissed = UKSettings.bool("fst.settings.pathUnavailableWarningDismissed", default: false)
        guard SongPathsSheet.presentsUnavailableWarning(
            warnAboutKaraoke: warnAboutKaraoke, dismissed: dismissed, alreadyConsidered: warningConsidered,
            resolved: Set(shown.keys), onScreen: shownMode.displays
        ) else { return }
        warningConsidered = true
        let alert = UIAlertController(
            title: "Some Instruments Unavailable", message: "Karaoke is not available for path visualization yet.", preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        let never = UIAlertAction(title: "Don't show again", style: .default) { _ in
            UserDefaults.standard.set(true, forKey: "fst.settings.pathUnavailableWarningDismissed")
        }
        never.accessibilityIdentifier = "fst.paths.warning.dismiss"
        alert.addAction(never)
        present(alert, animated: true)
    }

    // MARK: Selector row

    private var accessibilitySize: Bool { UKFont.isAccessibilitySize(traitCollection) }

    private var showsNames: Bool {
        SongPathsPolicy.selectorsShowNames(layout, stacked: accessibilitySize)
    }

    private func rebuildSelector() {
        selectorStack?.removeFromSuperview()
        let showsNames = showsNames
        let hugsIcon = !showsNames && !accessibilitySize
        let keyboardIcon: (Instrument) -> Bool = { [song] in song.usesKeyboardIcon && ($0 == .lead || $0 == .proLead) }

        let instrumentMenu = menuButton(
            title: "Instrument", value: instrument.label, identifier: "fst.paths.instrument",
            current: {
                let row = UIStackView()
                row.spacing = 6
                row.alignment = .center
                row.addArrangedSubview(UKInstrumentIconView(self.instrument, keyboard: keyboardIcon(self.instrument), size: UKFont.scaled(24, relativeTo: .body), hidesFromAccessibility: true))
                if showsNames { row.addArrangedSubview(UKLabel(self.instrument.label, lines: 2)) }
                return row
            }(),
            options: instruments.map { choice in
                UIAction(
                    title: choice.label,
                    image: UKInstrumentIconView.image(for: choice, keyboard: keyboardIcon(choice))?
                        .preparingThumbnail(of: CGSize(width: 22, height: 22))?.withRenderingMode(.alwaysOriginal),
                    state: choice == instrument ? .on : .off
                ) { [weak self] _ in self?.instrument = choice; self?.selectionChanged() }
            },
            fills: !hugsIcon
        )
        let difficultyMenu = menuButton(
            title: "Difficulty", value: difficulty.label, identifier: "fst.paths.difficulty",
            current: UKLabel(difficulty.label, lines: 1),
            options: PathDifficulty.allCases.map { choice in
                UIAction(title: choice.label, state: choice == difficulty ? .on : .off) { [weak self] _ in
                    self?.difficulty = choice
                    self?.selectionChanged()
                }
            },
            fills: true
        )
        var menus = [instrumentMenu, difficultyMenu]
        if SongPathsPolicy.showsViewMenu(layout) {
            let mode = shownMode
            let current: UIView
            if showsNames {
                let row = UIStackView(arrangedSubviews: [UIImageView(image: UIImage(systemName: mode.systemImage)), UKLabel(mode.label, lines: 1)])
                row.spacing = 6
                row.alignment = .center
                current = row
            } else {
                let image = UIImageView(image: UIImage(systemName: mode.systemImage))
                image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.body), scale: .large)
                image.tintColor = BrandUIColors.textPrimary
                current = image
            }
            menus.append(menuButton(
                title: "View", value: mode.label, identifier: "fst.paths.display", current: current,
                options: SongPathsPolicy.modes(for: layout).map { choice in
                    UIAction(title: choice.label, image: UIImage(systemName: choice.systemImage), state: choice == mode ? .on : .off) { [weak self] _ in
                        self?.viewMode = choice
                        self?.selectionChanged()
                    }
                },
                fills: !hugsIcon
            ))
        }
        let host: UIView
        if SongPathsPolicy.showsViewMenu(layout) || accessibilitySize {
            let stack = UIStackView(arrangedSubviews: menus)
            stack.axis = accessibilitySize ? .vertical : .horizontal
            stack.spacing = 8
            stack.alignment = accessibilitySize ? .fill : .fill
            host = stack
        } else {
            let row = UKHingeColumnsView()
            row.spacing = 8
            row.layoutProvider = { [weak self] in self?.layout ?? .standardPhone }
            row.leadingContent.addSubview(menus[0])
            row.trailingContent.addSubview(menus[1])
            for menu in menus {
                menu.translatesAutoresizingMaskIntoConstraints = true
                menu.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            }
            row.heightAnchor.constraint(equalToConstant: 44).isActive = true
            host = row
        }
        host.translatesAutoresizingMaskIntoConstraints = false
        selectorHolder.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: selectorHolder.leadingAnchor), host.trailingAnchor.constraint(equalTo: selectorHolder.trailingAnchor),
            host.topAnchor.constraint(equalTo: selectorHolder.topAnchor), host.bottomAnchor.constraint(equalTo: selectorHolder.bottomAnchor),
        ])
        selectorStack = host
    }

    private func menuButton(title: String, value: String, identifier: String, current: UIView, options: [UIAction], fills: Bool) -> UIButton {
        let button = UIButton(type: .custom)
        button.menu = UIMenu(options: [.singleSelection], children: options)
        button.showsMenuAsPrimaryAction = true
        button.preferredMenuElementOrder = .fixed
        let card = UKCardView(cornerRadius: 22, capsule: true)
        card.isUserInteractionEnabled = false
        card.translatesAutoresizingMaskIntoConstraints = false
        let chevron = UIImageView(image: UIImage(systemName: "chevron.up.chevron.down"))
        chevron.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.footnote, weight: .semibold))
        chevron.tintColor = BrandUIColors.textPrimary
        chevron.setContentHuggingPriority(.required, for: .horizontal)
        chevron.isAccessibilityElement = false
        current.isAccessibilityElement = false
        let row = UIStackView(arrangedSubviews: [current, chevron])
        row.spacing = 6
        row.alignment = .center
        row.isUserInteractionEnabled = false
        card.embed(row, insets: UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12))
        button.addSubview(card)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: button.leadingAnchor), card.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            card.topAnchor.constraint(equalTo: button.topAnchor), card.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44), button.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        button.setContentHuggingPriority(fills ? .defaultLow : .required, for: .horizontal)
        button.accessibilityLabel = title
        button.accessibilityValue = value
        button.accessibilityIdentifier = identifier
        return button
    }

    private func selectionChanged() {
        announcesSwitches = true
        rebuildSelector()
        refresh()
    }
}

// MARK: - Activation values

/// Beat, Time and Score side by side when the widest fits three equal columns, else
/// stacked (``PathActivationValuesLayout``); always stacked at accessibility sizes.
private final class UKPathValuesView: UIView {
    private let stack = UIStackView()
    private let columns: [UIView]

    init(columns: [UIView]) {
        self.columns = columns
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        columns.forEach(stack.addArrangedSubview)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        apply(sideBySide: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func apply(sideBySide: Bool) {
        let axis: NSLayoutConstraint.Axis = sideBySide ? .horizontal : .vertical
        guard stack.axis != axis else { return }
        stack.axis = axis
        stack.distribution = sideBySide ? .fillEqually : .fill
        stack.spacing = sideBySide ? PathActivationValuesLayout.columnSpacing : PathActivationValuesLayout.stackSpacing
        stack.alignment = sideBySide ? .top : .fill
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let widths = columns.map { $0.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width }
        let fits = !UKFont.isAccessibilitySize(traitCollection)
            && PathActivationValuesLayout.fitsSideBySide(widths: widths, available: bounds.width)
        if (stack.axis == .horizontal) != fits {
            apply(sideBySide: fits)
            setNeedsLayout()
        }
    }
}

// MARK: - Overdrive bar

/// The activation's overdrive amount (``OverdriveBar``): a system progress bar tinted amber
/// and the percentage; hidden from accessibility (the card speaks it).
private final class UKOverdriveBarView: UIView {
    init(percent: Double) {
        super.init(frame: .zero)
        let clamped = Int(min(max(percent, 0), 100).rounded())
        let bar = UIProgressView(progressViewStyle: .default)
        bar.progress = Float(clamped) / 100
        bar.progressTintColor = BrandUIColors.statusAmber
        bar.trackTintColor = UIColor.white.withAlphaComponent(0.2)
        bar.transform = CGAffineTransform(scaleX: 1, y: 2)
        bar.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.widthAnchor.constraint(greaterThanOrEqualToConstant: 80).isActive = true
        let text = UKLabel("\(clamped)%", style: .body, weight: .semibold, monospacedDigit: true, lines: 1, alignment: .right)
        text.widthAnchor.constraint(greaterThanOrEqualToConstant: 40).isActive = true
        let row = UIStackView(arrangedSubviews: [bar, text])
        row.spacing = 12
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor), row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor), row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isAccessibilityElement = false
        accessibilityElementsHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
