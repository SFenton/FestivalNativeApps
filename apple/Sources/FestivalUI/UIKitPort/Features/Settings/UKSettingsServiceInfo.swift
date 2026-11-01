#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Progress bar

/// The web-style capsule progress bar (``ServiceProgressBar``): a purple fill on a muted
/// track, 10 pt tall. An unknown total shows the sliding 38 % segment (the shared
/// ``ServiceProgressSweepView``), held still under system or in-app Reduce Motion, in an
/// inactive scene and in UI-test runs. Hidden from accessibility.
@MainActor
final class UKServiceProgressBar: UIView {
    private let fill = UIView()
    private let sweep = ServiceProgressSweepView()
    private var percent: Double?
    private var observer: UKAccessibilityObserver?
    nonisolated(unsafe) private var sceneObservers: [NSObjectProtocol] = []

    /// Creates the bar.
    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = BrandUIColors.surfaceMuted
        clipsToBounds = true
        isAccessibilityElement = false
        accessibilityElementsHidden = true
        fill.backgroundColor = BrandUIColors.accentPurple
        sweep.isHidden = true
        sweep.apply(color: BrandUIColors.accentPurple.cgColor)
        addSubview(fill)
        addSubview(sweep)
        heightAnchor.constraint(equalToConstant: 10).isActive = true
        observer = UKAccessibilityObserver { [weak self] in self?.refresh() }
        sceneObservers = [UIApplication.didBecomeActiveNotification, UIApplication.willResignActiveNotification].map {
            NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { sceneObservers.forEach { NotificationCenter.default.removeObserver($0) } }

    /// Sets the progress.
    ///
    /// - Parameter percent: 0-100, or nil for an unknown total.
    func setPercent(_ percent: Double?) {
        self.percent = percent
        refresh()
    }

    private func refresh() {
        let sceneActive = UIApplication.shared.applicationState == .active && window != nil
        let sweeps = ServiceProgressBar.sweeps(
            percent: percent, reduceMotion: UKAccessibility.reduceMotion, sceneActive: sceneActive,
            still: DebugAnimationOverride.stillBackground
        )
        sweep.isHidden = !sweeps
        fill.isHidden = percent == nil
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refresh()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        if let percent {
            let width = max(8, bounds.width * percent / 100)
            let change = { self.fill.frame = CGRect(x: 0, y: 0, width: min(width, self.bounds.width), height: self.bounds.height) }
            if UKAccessibility.reduceMotion || window == nil { change() } else { UIView.animate(withDuration: 0.18, delay: 0, options: .curveEaseOut, animations: change) }
        }
        sweep.frame = bounds
    }
}

// MARK: - Section

/// Settings "Service Info" card (``SettingsServiceInfoSection``): live leaderboard update state,
/// phase progress and last publication, polled every 5 s while the page is visible, through the
/// same ``SettingsServiceInfoModel`` and ``ServiceInfoRows``.
@MainActor
final class UKSettingsServiceInfoSection: UIView {
    private let session: FestivalSession
    private let model: SettingsServiceInfoModel
    private let titled: Bool
    private let card: UKSettingsSection
    private let stateRow: UKSettingsValueRow
    private let stateLabel = UKLabel(style: .headline, lines: 0)
    private let spinner = UKArcView(size: .small)
    private let phaseTitle = UKLabel(style: .body, weight: .semibold)
    private let bar = UKServiceProgressBar()
    private let attemptLabel = UKLabel(style: .subheadline)
    private let phaseRow = UIStackView()
    private let lastPublished = UKSettingLabel("")
    private let observations = UKObservationBag()
    private var polling: Task<Void, Never>?
    private var lastKey: String?

    /// Creates the section.
    ///
    /// - Parameters:
    ///   - session: Shared session whose client performs the keyless reads.
    ///   - titled: Show the section title (false on its own page).
    init(session: FestivalSession, titled: Bool = true) {
        self.session = session
        self.titled = titled
        model = SettingsServiceInfoModel()
        card = UKSettingsSection(ServiceInfoText.title, subtitle: ServiceInfoText.hint, titled: titled)
        let value = UIStackView(arrangedSubviews: [stateLabel, spinner])
        value.axis = .horizontal
        value.spacing = 8
        value.alignment = .center
        stateRow = UKSettingsValueRow(
            ServiceInfoText.serviceStateTitle, detail: "Loading", spokenValue: ServiceProcessState.loading.label,
            identifier: "fst.settings.service-info.state", value: value
        )
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        spinner.isAccessibilityElement = false
        spinner.accessibilityElementsHidden = true
        phaseRow.axis = .vertical
        phaseRow.spacing = 4
        for view in [phaseTitle, bar, attemptLabel] { phaseRow.addArrangedSubview(view) }
        phaseRow.isAccessibilityElement = true
        phaseRow.accessibilityTraits = .staticText
        phaseRow.accessibilityIdentifier = "fst.settings.service-info.phase"
        lastPublished.isAccessibilityElement = true
        lastPublished.accessibilityIdentifier = "fst.settings.service-info.last-published"
        addSubview(card)
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor), card.trailingAnchor.constraint(equalTo: trailingAnchor),
            card.topAnchor.constraint(equalTo: topAnchor), card.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        observations.observe { [weak self] in self?.render() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Starts polling every 5 s; call while the page is visible.
    func startPolling() {
        guard polling == nil else { return }
        let session = session
        polling = Task { [model] in
            await model.poll { try await session.client().serviceInfo() }
        }
    }

    /// Stops polling; call when the page hides.
    func stopPolling() {
        polling?.cancel()
        polling = nil
    }

    private func render() {
        let rows = ServiceInfoRows.make(model.phase)
        stateLabel.text = rows.processState.label
        spinner.isHidden = !(rows.processState == .loading || rows.processState == .updating)
        stateRow.setDetail(rows.stateDescription, spokenValue: rows.processState.label)
        var views: [UIView] = [stateRow]
        if let title = rows.phaseTitle {
            phaseTitle.text = title
            if let barPercent = rows.barPercent {
                bar.isHidden = false
                bar.setPercent(barPercent)
                attemptLabel.text = rows.attemptText
                attemptLabel.isHidden = rows.attemptText == nil
            } else {
                bar.isHidden = true
                attemptLabel.isHidden = true
            }
            phaseRow.accessibilityLabel = title
            phaseRow.accessibilityValue = [rows.progressText, rows.unitsText, rows.attemptText].compactMap { $0 }
                .joined(separator: ". ")
            views.append(phaseRow)
        }
        if let published = rows.lastPublished {
            lastPublished.setDetail(published)
            lastPublished.setTitleText(ServiceInfoText.lastPublishedTitle)
            lastPublished.accessibilityLabel = "\(ServiceInfoText.lastPublishedTitle), \(published)"
            views.append(lastPublished)
        }
        let key = "\(views.count)|\(rows.phaseTitle ?? "")|\(rows.lastPublished ?? "")"
        if key != lastKey || lastKey == nil {
            lastKey = key
            card.setRows(views)
        }
    }
}

extension UKSettingLabel {
    /// Replaces the title.
    ///
    /// - Parameter text: The new title.
    func setTitleText(_ text: String) {
        (arrangedSubviews.first as? UILabel)?.text = text
    }
}

// MARK: - Fixture tools

/// The fixture-only "Check Publication" card (``SettingsFixtureToolsSection``): the label and
/// status identifier the existing Songs journeys use.
@MainActor
final class UKSettingsFixtureTools: UIView {
    private let status = UKLabel(style: .subheadline)

    /// Creates the card.
    ///
    /// - Parameter session: Session whose publication and catalogue are refreshed.
    init(session: FestivalSession) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let section = UKSettingsSection("Fixture Tools", subtitle: "Debug fixture runs only.")
        var configuration = UIButton.Configuration.plain()
        configuration.title = "Check Publication"
        configuration.baseForegroundColor = UKAccentText.blue
        configuration.contentInsets = .zero
        let button = UIButton(configuration: configuration)
        button.contentHorizontalAlignment = .leading
        button.accessibilityIdentifier = "fst.settings.check-publication"
        status.isHidden = true
        status.accessibilityIdentifier = "fst.settings.publication-status"
        button.addAction(UIAction { [weak self] _ in
            Task { @MainActor in
                if let text = await SettingsPublicationCheck.run(session: session) {
                    self?.status.text = text
                    self?.status.isHidden = false
                }
            }
        }, for: .touchUpInside)
        let content = UIStackView(arrangedSubviews: [button, status])
        content.axis = .vertical
        content.spacing = 4
        content.alignment = .fill
        section.setRows([content])
        section.translatesAutoresizingMaskIntoConstraints = false
        addSubview(section)
        NSLayoutConstraint.activate([
            section.leadingAnchor.constraint(equalTo: leadingAnchor), section.trailingAnchor.constraint(equalTo: trailingAnchor),
            section.topAnchor.constraint(equalTo: topAnchor), section.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
