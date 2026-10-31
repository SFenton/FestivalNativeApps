#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Sheet page

/// The native "What's New" changelog (``WhatsNewSheet``): a titled, scrolling list of
/// sections with bullet items and a full-width Dismiss button in an opaque bottom bar, so the
/// list scrolls above it. Pulling the list down past its top and letting go dismisses it too.
/// The list shows a spinner while the install channel is still being detected.
@MainActor
final class UKWhatsNewViewController: UIViewController, UKModalScrollProviding {
    private let version: String
    private let onDismiss: () -> Void
    private let scroll = UIScrollView()
    private let column = UIStackView()
    private let pending = UKLoadingView(accessibilityLabel: "Getting notes for this install")
    private let bar = UIView()
    private var barHeightHidden: NSLayoutConstraint!
    private let observations = UKObservationBag()
    private var pull: UKPullDownToDismiss?
    private var shownEntries: [ChangelogEntry]??

    var ukModalScrollView: UIScrollView? { scroll }

    /// Creates the page.
    ///
    /// - Parameters:
    ///   - version: App version shown after the title.
    ///   - onDismiss: Called when the user closes the sheet.
    init(version: String, onDismiss: @escaping () -> Void) {
        self.version = version
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = BrandUIColors.cardBackground
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        column.axis = .vertical
        column.spacing = 28
        column.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(column)
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.backgroundColor = BrandUIColors.cardBackground
        let line = UKHairlineView()
        let button = UKSettingsButtons.prominent(
            "Dismiss", font: UKFont.font(.headline), identifier: "fst.whats-new.dismiss"
        ) { [weak self] in self?.onDismiss() }
        button.translatesAutoresizingMaskIntoConstraints = false
        line.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(line)
        bar.addSubview(button)
        view.addSubview(scroll)
        view.addSubview(bar)
        let guide = view.safeAreaLayoutGuide
        let barTop = scroll.bottomAnchor.constraint(equalTo: bar.topAnchor)
        barHeightHidden = bar.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor), barTop,
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor), bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            line.topAnchor.constraint(equalTo: bar.topAnchor), line.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            line.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            button.topAnchor.constraint(equalTo: bar.topAnchor, constant: 12),
            button.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 20),
            button.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -20),
            button.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12),
            column.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            column.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -12),
            column.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            column.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20),
        ])
        pull = UKPullDownToDismiss(scrollView: scroll) { [weak self] in self?.onDismiss() }
        observations.observe { [weak self] in
            let channel = AppDistributionResolver.shared.channel
            self?.render(entries: channel.map { Changelog.displayEntries(distribution: $0) })
        }
        Task { _ = await AppDistributionResolver.shared.current() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // `/duo` M1: with the iPhone Duo vertical bar the sheet's Close sits in its own side
        // bar, so the custom Dismiss bar would be a second close control; iPhone keeps it.
        let shows = WhatsNewSheet.showsDismissBar(ukWindowLayout)
        bar.isHidden = !shows
        barHeightHidden.isActive = !shows
    }

    private func render(entries: [ChangelogEntry]?) {
        column.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard let entries else {
            let holder = UIView()
            pending.accessibilityIdentifier = "fst.whats-new.pending"
            pending.translatesAutoresizingMaskIntoConstraints = false
            holder.addSubview(pending)
            NSLayoutConstraint.activate([
                pending.centerXAnchor.constraint(equalTo: holder.centerXAnchor),
                pending.topAnchor.constraint(equalTo: holder.topAnchor, constant: 48),
                pending.bottomAnchor.constraint(equalTo: holder.bottomAnchor),
            ])
            column.addArrangedSubview(holder)
            return
        }
        for entry in entries { column.addArrangedSubview(entryView(entry)) }
    }

    private func entryView(_ entry: ChangelogEntry) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 16
        if let heading = entry.displayHeading {
            stack.addArrangedSubview(UKLabel(heading, style: .title3, weight: .semibold).asHeader())
        }
        for section in entry.sections { stack.addArrangedSubview(sectionView(section)) }
        return stack
    }

    private func sectionView(_ section: ChangelogSection) -> UIView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        if !section.title.isEmpty {
            stack.addArrangedSubview(UKLabel(section.displayTitle, style: .headline).asHeader())
        }
        for item in section.items {
            let dot = UKLabel("\u{2022}", style: .body)
            dot.isAccessibilityElement = false
            dot.setContentHuggingPriority(.required, for: .horizontal)
            let text = UKLabel(item, style: .subheadline)
            let row = UIStackView(arrangedSubviews: [dot, text])
            row.axis = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 8
            stack.addArrangedSubview(row)
        }
        return stack
    }
}

// MARK: - Presentation

/// Builds and presents What's New: the launch presentation once per changelog, Settings' replay
/// and the Help menu's command.
@MainActor
enum UKWhatsNew {
    /// The sheet's navigation controller, configured as ``View/whatsNewPresentation``: a full
    /// cover on iPhone, a centred sheet on the iPhone Duo inner display (and wherever
    /// ``WhatsNewPresentationStyle`` says so).
    ///
    /// - Parameters:
    ///   - layout: The window's layout.
    ///   - onDismiss: Called when the user closes the sheet; the caller dismisses and records.
    /// - Returns: The controller to present.
    static func make(layout: DeviceLayout, onDismiss: @escaping () -> Void) -> UKSheetNavigationController {
        let version = WhatsNewGate.appVersion()
        let page = UKWhatsNewViewController(version: version, onDismiss: onDismiss)
        let sheet = UKSheet.make(
            page, title: WhatsNewSheet.title(version: version), closeIdentifier: "fst.whats-new.close", size: .large,
            regularWidth: WhatsNewPresentationStyle.usesSheet(layout),
            coverage: WhatsNewPresentationStyle.usesSheet(layout) ? .sheet : .fullScreen, onClose: onDismiss
        )
        sheet.view.backgroundColor = BrandUIColors.cardBackground
        return sheet
    }

    /// Presents What's New from a Settings replay: Dismiss or Close records the changelog seen.
    ///
    /// - Parameters:
    ///   - session: The shared session (unused beyond symmetry with the shell factory).
    ///   - presenter: The controller to present from.
    static func present(session: FestivalSession, from presenter: UIViewController) {
        var sheet: UKSheetNavigationController?
        sheet = make(layout: presenter.ukWindowLayout) {
            ChangelogSeenStore().markSeen(version: WhatsNewGate.appVersion())
            sheet?.dismiss(animated: true)
        }
        if let sheet { presenter.present(sheet, animated: true) }
    }

    /// The Help menu's What's New sheet content (the shell presents it).
    ///
    /// - Parameter session: The shared session.
    /// - Returns: The sheet to present; Dismiss and Close dismiss it.
    static func shellSheet(_ session: FestivalSession) -> UIViewController {
        var sheet: UKSheetNavigationController?
        let layout = UIApplication.shared.ukKeyShell?.layout ?? .standardPhone
        sheet = make(layout: layout) {
            ChangelogSeenStore().markSeen(version: WhatsNewGate.appVersion())
            sheet?.dismiss(animated: true)
        }
        return sheet ?? UIViewController()
    }
}

// MARK: - Launch presentation

/// Presents "What's New" once per changelog after the launch page's first-run carousel, and
/// persists dismissal (``WhatsNewLaunchModifier``), through the shared ``WhatsNewLauncher``.
@MainActor
final class UKWhatsNewLaunch {
    private let session: FestivalSession
    private weak var shell: UKRootViewController?
    private var presented = false
    private let observations = UKObservationBag()

    /// Starts the launch flow for a window.
    ///
    /// - Parameters:
    ///   - session: Shared session (its first-run coordinator arbitrates the one onboarding sheet).
    ///   - shell: The window root that presents the sheet.
    init(session: FestivalSession, shell: UKRootViewController) {
        self.session = session
        self.shell = shell
        Task { await presentWhenSettled() }
        var first = true
        observations.observe { [weak self] in
            guard let self else { return }
            let key = session.firstRunCenter.activeKey
            if first { first = false; return }
            guard key == nil else { return }
            Task { await self.presentWhenSettled() }
        }
    }

    /// Wait for the launch carousel to claim the slot, then present if nothing else holds it.
    private func presentWhenSettled() async {
        // Detect the install channel at every launch, so the sheet and Settings' replay open with
        // the right notes.
        _ = await AppDistribution.current()
        let launcher = WhatsNewLauncher.shared
        guard launcher.resolveIfNeeded(), !presented else { return }
        try? await Task.sleep(for: WhatsNewGate.settleDelay)
        guard !presented, let shell, shell.view.window != nil, launcher.claim(in: session.firstRunCenter) else { return }
        presented = true
        var sheet: UKSheetNavigationController?
        let finish = { [weak self] in
            guard let self else { return }
            sheet?.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                launcher.finish(in: session.firstRunCenter)
                presented = false
            }
        }
        sheet = UKWhatsNew.make(layout: shell.layout, onDismiss: finish)
        (shell.presentedViewController ?? shell).present(sheet!, animated: true)
    }
}

extension UIApplication {
    /// The shell of the key window, if the app is showing one.
    var ukKeyShell: UKRootViewController? {
        connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            .first { $0.isKeyWindow }?.rootViewController as? UKRootViewController
    }
}
#endif
