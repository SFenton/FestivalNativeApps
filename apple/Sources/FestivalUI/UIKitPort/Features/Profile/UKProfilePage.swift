#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Scrolling page

/// The shared body of the lane's scrolling pages (Player profile, Statistics, Band Detail,
/// Bands): a scroll view holding one 20 pt-spaced column of sections inside 16 pt padding
/// (`ScrollView { VStack(spacing: 20) { ... }.padding(16) }`), a full-page state placeholder
/// (loading, empty, error) that replaces it, the Quick Links binding and the page-tools hook.
///
/// A section that depends on its width conforms to ``UKWidthDependent``; the page passes the
/// column width to every section before Auto Layout sizes it and again when the width changes.
@MainActor
class UKProfileScrollViewController: UIViewController, UIScrollViewDelegate, UKPageToolsProviding {
    /// The screen's context.
    let context: UKContext
    /// The scrolling surface.
    let scrollView = UIScrollView()
    /// The 20 pt-spaced column.
    let column = UKProfileColumnStack()
    /// The page's Quick Links binding, once installed.
    private(set) var quickLinks: UKQuickLinks?
    /// Quick-link anchors by section id, in page order.
    private(set) var quickLinkViews: [(section: QuickLinkSection, view: UIView)] = []
    /// Window layout and observation helpers.
    let observations = UKObservationBag()
    private var stateView: UIView?
    private var centreOffset: NSLayoutConstraint?
    private var widthConstraint: NSLayoutConstraint?
    private var readableConstraint: NSLayoutConstraint?
    /// Caps the column at this width, centred (``ReadableWidthContainer``), while the window is regular width.
    var readableWidth: CGFloat?
    private var preparedWidth: CGFloat = -1

    /// Creates the page.
    ///
    /// - Parameter context: The screen's context.
    init(context: UKContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The session.
    var session: FestivalSession { context.session }

    /// The window layout this page adapts to.
    var layout: DeviceLayout { ukLayout }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scrollView.delegate = self
        scrollView.alwaysBounceVertical = true
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .automatic
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        column.onLayout = { [weak self] in self?.columnDidLayout() }
        column.axis = .vertical
        column.alignment = .fill
        column.spacing = UKProfileMetrics.sectionSpacing
        column.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(column)
        let content = scrollView.contentLayoutGuide
        let frame = scrollView.frameLayoutGuide
        let pad = UKProfileMetrics.pagePadding
        let centre = column.centerXAnchor.constraint(equalTo: frame.centerXAnchor)
        let width = column.widthAnchor.constraint(equalTo: frame.widthAnchor, constant: -2 * pad)
        width.priority = .defaultHigh
        let readable = column.widthAnchor.constraint(lessThanOrEqualToConstant: 10_000)
        centreOffset = centre
        widthConstraint = width
        readableConstraint = readable
        NSLayoutConstraint.activate([
            centre, width, readable,
            column.topAnchor.constraint(equalTo: content.topAnchor, constant: pad),
            column.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -pad),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        quickLinks?.didAppear()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        quickLinks?.willDisappear()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateMargins()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateMargins()
        columnDidLayout()
        quickLinks?.scrollViewDidScroll()
    }

    private func columnDidLayout() {
        let columnWidth = column.bounds.width
        if columnWidth > 0, abs(columnWidth - preparedWidth) > 0.5 { prepareSections(width: columnWidth) }
    }

    /// Horizontal safe-area insets (a Duo hinge cut-out, landscape notch) keep the column clear.
    private func updateMargins() {
        let insets = view.safeAreaInsets
        let pad = UKProfileMetrics.pagePadding
        centreOffset?.constant = (insets.left - insets.right) / 2
        widthConstraint?.constant = -(2 * pad + insets.left + insets.right)
        let cap = layout.widthClass == .regular ? readableWidth : nil
        readableConstraint?.constant = cap ?? 10_000
    }

    private func prepareSections(width: CGFloat) {
        preparedWidth = width
        column.arrangedSubviews.forEach { $0.ukPrepare(width: width) }
    }

    // MARK: Sections

    /// Replaces the page's sections and shows the scrolling column.
    ///
    /// - Parameters:
    ///   - sections: The sections, top to bottom.
    ///   - fadeIn: Stagger the sections in (new content as it loads); false updates silently.
    func setSections(_ sections: [UIView], fadeIn: Bool) {
        hideState()
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        sections.forEach(column.addArrangedSubview)
        preparedWidth = -1
        let width = column.bounds.width
        if width > 0 { prepareSections(width: width) }
        view.setNeedsLayout()
        if fadeIn {
            for (index, section) in sections.enumerated() { UKFadeIn.fadeIn(section, staggerIndex: index) }
        }
    }

    /// Replaces the scrolling column with a full-page state (loading, empty, error).
    ///
    /// - Parameter state: The placeholder, filling the page.
    func showState(_ state: UIView) {
        stateView?.removeFromSuperview()
        scrollView.isHidden = true
        state.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(state)
        NSLayoutConstraint.activate([
            state.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            state.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            state.topAnchor.constraint(equalTo: view.topAnchor),
            state.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        stateView = state
    }

    /// Removes the state placeholder and shows the column.
    func hideState() {
        stateView?.removeFromSuperview()
        stateView = nil
        scrollView.isHidden = false
    }

    /// The hinge (window coordinates) a full-page state centres itself away from.
    var hingeProvider: () -> CGRect? { { [weak self] in self?.layout.splitHinge } }

    // MARK: Quick Links

    /// Installs the Quick Links binding once.
    ///
    /// - Parameter title: Menu title (`Quick Links`).
    func installQuickLinks(title: String = "Quick Links") {
        guard quickLinks == nil else { return }
        let links = UKQuickLinks(controller: QuickLinksController(), title: title)
        links.attach(
            to: scrollView,
            rect: { [weak self] id in
                guard let view = self?.quickLinkViews.first(where: { $0.section.id == id })?.view, view.window != nil,
                      let scroll = self?.scrollView else { return nil }
                return view.convert(view.bounds, to: scroll)
            },
            element: { [weak self] id in self?.quickLinkViews.first(where: { $0.section.id == id })?.view }
        )
        links.onToolChange = { [weak self] in self?.pageToolsChanged() }
        quickLinks = links
    }

    /// Replaces the page's Quick Link anchors (call after the sections are built).
    ///
    /// - Parameter anchors: Sections with the view each one scrolls to, in page order.
    func setQuickLinks(_ anchors: [(QuickLinkSection, UIView)]) {
        quickLinkViews = anchors.map { (section: $0.0, view: $0.1) }
        quickLinks?.discover(anchors.map(\.0))
        quickLinks?.scrollViewDidScroll()
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        quickLinks?.scrollViewDidScroll()
    }

    // MARK: Page tools

    var ukPageTools: [UKPageTool] { quickLinks?.tool.map { [$0] } ?? [] }

    /// Whether the shell installs this page's bar (a section root); a pushed page does.
    var isSectionRoot: Bool { false }

    /// Extra bar items before the page tools (the identity button), leading to trailing.
    var pageBarItems: [UIBarButtonItem] { [] }

    /// Tells the shell the page's tools changed and re-places the bar items.
    func pageToolsChanged() {
        if !isSectionRoot {
            let floats = ukShell?.floatsPageTools ?? false
            var items = pageBarItems
            if !floats { items += ukPageTools.sorted { $0.order < $1.order }.map(\.item) }
            navigationItem.rightBarButtonItems = items.reversed()
        }
        ukPageToolsDidChange()
    }
}

/// The page's column: reports each layout so sections learn width changes at once.
final class UKProfileColumnStack: UIStackView {
    /// Called after every layout pass.
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
#endif
