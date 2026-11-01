#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Rivals page base

/// What every Rivals, Compete and Suggestions page shares: a transparent page over the
/// shared artwork background, a vertical column in a scroll view, full-page states
/// (spinner, status, empty) swapped in place of it, the "no player selected" state, Quick
/// Links over the column's sections, the pinned bar title for pages that lead with an
/// in-list title, and a rebuild when the selected account changes (the SwiftUI pages key
/// their state by account).
///
/// Subclasses build their content in ``build()`` and call ``reloadPage()`` to start over.
class UKRivalsPageViewController: UIViewController, UKPageToolsProviding, UIScrollViewDelegate {
    /// The context the page was created in.
    let context: UKContext
    /// The page's scroll view; hidden while a full-page state shows.
    let scrollView = UIScrollView()
    /// The page's vertical content column.
    let column = UIStackView()
    /// Observations that end with the page.
    let observations = UKObservationBag()
    /// Quick Links over the column's sections, once ``makeQuickLinks(title:)`` ran.
    private(set) var quickLinks: UKQuickLinks?
    /// Tasks that end with the page's current content (cancelled on a rebuild).
    var tasks: [Task<Void, Never>] = []

    private lazy var background = UKBackgroundRegistration(session: context.session, mode: .carousel)
    private var stateView: UIView?
    private var shownAccountId: String??
    private var accountChromeInstalled = false
    private var quickLinkEntries: [(section: QuickLinkSection, view: UIView)] = []
    private var pinnedTitle: UKInstrumentPageTitleView?
    private var inListTitle: UIView?
    private var titleHidden = false
    private var hasInListTitle = false
    /// Set when the column was rebuilt: the next layout scrolls to the top under the bars.
    var needsInitialOffset = true
    private var shownSignature: AnyHashable?
    private nonisolated(unsafe) var settingsObserver: NSObjectProtocol?

    /// The session the page reads.
    var session: FestivalSession { context.session }

    /// Creates the page.
    ///
    /// - Parameter context: The context it was created in.
    init(context: UKContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        tasks.forEach { $0.cancel() }
        settingsObserver.map(NotificationCenter.default.removeObserver)
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scrollView.backgroundColor = .clear
        scrollView.alwaysBounceVertical = true
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .automatic
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        column.axis = .vertical
        column.spacing = columnSpacing
        column.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(column)
        view.addSubview(scrollView)
        scrollView.ukPin(to: view)
        let content = scrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor), column.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            column.topAnchor.constraint(equalTo: content.topAnchor, constant: columnInsets.top),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -columnInsets.bottom),
            column.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
        observations.observe { [weak self] in
            guard let self else { return }
            let id = self.session.selectedPlayer?.accountId
            if let shown = self.shownAccountId, shown != id {
                self.shownAccountId = .some(id)
                DispatchQueue.main.async { [weak self] in self?.reloadPage() }
            } else if self.shownAccountId == nil {
                self.shownAccountId = .some(id)
            }
        }
        settingsObserver = NotificationCenter.default.addObserver(forName: UKSettings.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.shownSignature != self.settingsSignature else { return }
                self.reloadPage()
            }
        }
        reloadPage()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if context.surface == .page { background.viewWillAppear() }
        quickLinks?.didAppear()
        refreshSheetTools()
        // A pushed page shows the bell and profile (`.pageTrailingItems()`); a section root
        // gets them from the shell.
        if ukRoute != nil, context.surface == .page, !accountChromeInstalled {
            accountChromeInstalled = true
            ukInstallAccountItems()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if context.surface == .page { background.viewDidDisappear() }
        quickLinks?.willDisappear()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if needsInitialOffset, !scrollView.isHidden, scrollView.window != nil, scrollView.adjustedContentInset.top > 0 {
            needsInitialOffset = false
            scrollView.contentOffset.y = -scrollView.adjustedContentInset.top
        }
        quickLinks?.scrollViewDidScroll()
        updateTitleHidden()
    }

    // MARK: Subclass hooks

    /// Spacing between the column's arranged subviews.
    var columnSpacing: CGFloat { 20 }
    /// Padding above and below the column.
    var columnInsets: (top: CGFloat, bottom: CGFloat) { (8, 24) }

    /// Rebuilds the page's content for the current state. Called on load and after an
    /// account change; the base has already cancelled ``tasks`` and emptied the column.
    func build() {}

    /// What the page's content depends on in Settings; a change rebuilds the page.
    var settingsSignature: AnyHashable { 0 }

    /// Extra tools besides Quick Links, in any order.
    var pageTools: [UKPageTool] { [] }

    // MARK: Page tools

    /// Inside a sheet there is no shell to place the page's tools (the SwiftUI sheet shows
    /// them in its navigation bar, where no tool floats), so they go in the bar's trailing items.
    func refreshSheetTools() {
        guard context.surface == .sheet else { return }
        navigationItem.rightBarButtonItems = ukPageTools.sorted { $0.order < $1.order }.map(\.item).reversed()
    }

    var ukPageTools: [UKPageTool] { pageTools + (quickLinks?.tool.map { [$0] } ?? []) }

    // MARK: Rebuild

    /// Cancels the page's work, empties the column and builds again.
    func reloadPage() {
        tasks.forEach { $0.cancel() }
        tasks = []
        shownSignature = settingsSignature
        needsInitialOffset = true
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        quickLinkEntries = []
        quickLinks?.discover([])
        hasInListTitle = false
        inListTitle = nil
        titleHidden = false
        updatePinnedTitle()
        showScroll()
        build()
    }

    /// Runs `work` for the page's current content; a rebuild cancels it.
    ///
    /// - Parameter work: The async work.
    final func runTask(_ work: @escaping @MainActor () async -> Void) {
        tasks.append(Task { @MainActor in await work() })
    }

    // MARK: Full-page states

    /// Shows a state view over the whole page in place of the column.
    ///
    /// - Parameter state: The spinner, status or empty state.
    func showFill(_ state: UIView, edgeToEdge: Bool = false) {
        stateView?.removeFromSuperview()
        scrollView.isHidden = true
        if scrollView.superview !== view {
            // A gate that held the scroll view is going away with its state.
            view.insertSubview(scrollView, at: 0)
            scrollView.ukPin(to: view)
        }
        state.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(state)
        if edgeToEdge {
            state.ukPin(to: view)
            stateView = state
            hasInListTitle = false
            updatePinnedTitle()
            return
        }
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            state.leadingAnchor.constraint(equalTo: guide.leadingAnchor), state.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            state.topAnchor.constraint(equalTo: guide.topAnchor), state.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
        ])
        stateView = state
        hasInListTitle = false
        updatePinnedTitle()
    }

    /// Shows the column again.
    func showScroll() {
        if scrollView.superview !== view {
            view.insertSubview(scrollView, at: 0)
            scrollView.ukPin(to: view)
        }
        stateView?.removeFromSuperview()
        stateView = nil
        scrollView.isHidden = false
    }

    /// The centred spinner state.
    ///
    /// - Parameter label: Spoken label.
    func showLoading(_ label: String) {
        let loading = UKLoadingView(accessibilityLabel: label, placement: .fill)
        loading.hingeProvider = { [weak self] in self?.ukLayout.splitHinge }
        showFill(loading)
    }

    /// The full-page service status with Retry.
    ///
    /// - Parameters:
    ///   - issue: The failure.
    ///   - title: Heading when the issue has none.
    ///   - scope: Backoff scope.
    ///   - retry: Called by Retry and when the countdown ends.
    func showStatus(_ issue: ServiceIssue, title: String, scope: String? = nil, retry: @escaping () -> Void) {
        showFill(UKServiceStatusView(issue, title: title, scope: scope, retry: retry))
    }

    /// A centred empty state.
    ///
    /// - Parameters:
    ///   - title: Title Case title.
    ///   - systemImage: Symbol.
    ///   - subtitle: Supporting line.
    ///   - identifier: Accessibility identifier.
    ///   - actions: Buttons under the text.
    func showEmpty(_ title: String, systemImage: String, subtitle: String, identifier: String? = nil, actions: [UIView] = []) {
        let empty = UKEmptyStateView(title, systemImage: systemImage, subtitle: subtitle, identifier: identifier, actions: actions)
        empty.hingeProvider = { [weak self] in self?.ukLayout.splitHinge }
        showFill(empty)
    }

    /// The "No Player Selected" state every player-only Rivals and Compete page shows.
    func showChooseProfile() {
        showEmpty(
            "No Player Selected", systemImage: "person.crop.circle.badge.questionmark",
            subtitle: "Choose a profile to see your rivals.", identifier: "fst.rivals.chooseProfile",
            actions: [UKProminentButton(title: "Choose Profile") { [weak self] in self?.context.navigator?.presentProfile() }]
        )
    }

    // MARK: Column

    /// Adds a view to the column.
    ///
    /// - Parameters:
    ///   - view: The view.
    ///   - fadeIndex: Its place in the entrance stagger; nil shows it at once.
    func add(_ view: UIView, fadeIndex: Int? = nil) {
        column.addArrangedSubview(view)
        if let fadeIndex { UKFadeIn.fadeIn(view, staggerIndex: fadeIndex) }
    }

    // MARK: Quick Links

    /// Creates the Quick Links binding over the scroll view and the registered sections.
    ///
    /// - Parameter title: Menu and rotor title.
    func makeQuickLinks(title: String = "Quick Links") {
        guard quickLinks == nil else { return }
        let links = UKQuickLinks(controller: QuickLinksController(), title: title)
        links.onToolChange = { [weak self] in
            self?.ukPageToolsDidChange()
            self?.refreshSheetTools()
        }
        links.attach(
            to: scrollView,
            rect: { [weak self] id in
                guard let self, let view = self.quickLinkEntries.first(where: { $0.section.id == id })?.view, view.window != nil
                else { return nil }
                return self.scrollView.convert(view.bounds, from: view)
            },
            element: { [weak self] id in self?.quickLinkEntries.first(where: { $0.section.id == id })?.view }
        )
        quickLinks = links
        ukPageToolsDidChange()
    }

    /// Registers (or replaces) a section for the Quick Links menu.
    ///
    /// - Parameters:
    ///   - section: The menu entry.
    ///   - view: The section's view in the column.
    func registerQuickLink(_ section: QuickLinkSection, view: UIView) {
        quickLinkEntries.removeAll { $0.section.id == section.id }
        quickLinkEntries.append((section, view))
        view.isAccessibilityElement = false
        publishQuickLinks()
    }

    /// Forgets every registered section (the page is rebuilding them).
    func clearQuickLinks() {
        quickLinkEntries = []
        quickLinks?.discover([])
    }

    /// Removes a section (it became empty or failed).
    ///
    /// - Parameter id: The section's id.
    func unregisterQuickLink(id: String) {
        guard quickLinkEntries.contains(where: { $0.section.id == id }) else { return }
        quickLinkEntries.removeAll { $0.section.id == id }
        publishQuickLinks()
    }

    private func publishQuickLinks() {
        guard let quickLinks else { return }
        let ordered = quickLinkEntries.sorted { precedes(order(of: $0.view), order(of: $1.view)) }
        quickLinks.discover(ordered.map(\.section))
    }

    /// The view's place in the column as a path of indexes, so nested stacks sort in page order.
    private func order(of view: UIView) -> [Int] {
        var path: [Int] = []
        var current: UIView? = view
        while let candidate = current, candidate !== column, let parent = candidate.superview {
            let siblings = (parent as? UIStackView)?.arrangedSubviews ?? parent.subviews
            path.append(siblings.firstIndex(of: candidate) ?? Int.max)
            current = parent
        }
        return path.reversed()
    }

    private func precedes(_ lhs: [Int], _ rhs: [Int]) -> Bool {
        for (a, b) in zip(lhs, rhs) where a != b { return a < b }
        return lhs.count < rhs.count
    }

    // MARK: Pinned title

    /// Leads the page with an in-list title that pins to the bar once it scrolls away
    /// (`InstrumentPageTitle` + `InstrumentPageTitleToolbarItem`).
    ///
    /// - Parameters:
    ///   - instrument: The leading icon.
    ///   - title: Title text.
    ///   - subtitle: Supporting line.
    ///   - subtitleInstrument: Icon before the subtitle.
    ///   - identifier: Header identifier.
    ///   - pinnedIdentifier: Pinned bar title identifier.
    /// - Returns: The in-list title to add to the column.
    func makeHeroTitle(
        instrument: Instrument?, title: String, subtitle: String? = nil, subtitleInstrument: Instrument? = nil,
        identifier: String, pinnedIdentifier: String
    ) -> UIView {
        let hero = UKInstrumentPageTitleView(
            instrument: instrument, title: title, subtitle: subtitle, subtitleInstrument: subtitleInstrument,
            style: .header, identifier: identifier
        )
        pinnedTitle = UKInstrumentPageTitleView(
            instrument: instrument, title: title, subtitle: subtitle, subtitleInstrument: subtitleInstrument,
            style: .pinned, identifier: pinnedIdentifier
        )
        inListTitle = hero
        hasInListTitle = true
        titleHidden = false
        updatePinnedTitle()
        return hero.ukPadded()
    }

    /// Sets the pinned title's identity for a state without an in-list title (always shown).
    ///
    /// - Parameters:
    ///   - instrument: Leading icon.
    ///   - title: Title text.
    ///   - subtitle: Supporting line.
    ///   - subtitleInstrument: Icon before the subtitle.
    ///   - pinnedIdentifier: Identifier.
    func setPinnedTitle(
        instrument: Instrument?, title: String, subtitle: String? = nil, subtitleInstrument: Instrument? = nil,
        pinnedIdentifier: String
    ) {
        pinnedTitle = UKInstrumentPageTitleView(
            instrument: instrument, title: title, subtitle: subtitle, subtitleInstrument: subtitleInstrument,
            style: .pinned, identifier: pinnedIdentifier
        )
        updatePinnedTitle()
    }

    private func updateTitleHidden() {
        guard hasInListTitle, let inListTitle, inListTitle.window != nil else { return }
        let frame = inListTitle.convert(inListTitle.bounds, to: view)
        let hidden = SongDetailPinnedTitlePolicy.isHeroHidden(titleMaxY: frame.maxY - view.safeAreaInsets.top)
        guard hidden != titleHidden else { return }
        titleHidden = hidden
        updatePinnedTitle()
    }

    private func updatePinnedTitle() {
        guard let pinnedTitle, InstrumentPageTitleToolbarItem.pinsTitle(in: ukLayout.sectionChrome) else {
            navigationItem.titleView = nil
            return
        }
        let shown = !hasInListTitle || titleHidden
        let target: UIView
        if shown {
            target = pinnedTitle
        } else {
            // Holds the slot so the bar does not fall back to the navigation title above the
            // in-list title (issue #93).
            let placeholder = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            placeholder.isAccessibilityElement = false
            target = placeholder
        }
        guard navigationItem.titleView !== target else { return }
        if UKAccessibility.reduceMotion || !isViewLoaded || view.window == nil {
            navigationItem.titleView = target
        } else {
            UIView.transition(with: navigationController?.navigationBar ?? view, duration: 0.2, options: .transitionCrossDissolve) {
                self.navigationItem.titleView = target
            }
        }
    }

    // MARK: Scrolling

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        quickLinks?.scrollViewDidScroll()
        updateTitleHidden()
    }
}

// MARK: - Page tool helper

extension UKRivalsPageViewController {
    /// A tool-bar button with a symbol, title and identifier.
    ///
    /// - Parameters:
    ///   - title: Spoken name.
    ///   - symbol: SF Symbol.
    ///   - identifier: Accessibility identifier.
    ///   - order: Position in the tool row.
    ///   - action: Called when pressed.
    /// - Returns: The tool.
    static func tool(title: String, symbol: String, identifier: String, order: Int = PageToolOrder.primary, action: @escaping () -> Void) -> UKPageTool {
        let item = UIBarButtonItem(title: title, image: UIImage(systemName: symbol), primaryAction: UIAction { _ in action() })
        item.accessibilityLabel = title
        item.accessibilityIdentifier = identifier
        item.tintColor = BrandUIColors.textPrimary
        return UKPageTool(order: order, item: item)
    }
}
#endif
