#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Drawer

/// The leading slide-over navigation panel (iPhone drawer, iPad and iPhone Duo flyout) on
/// Liquid Glass: the UIKit counterpart of ``FestivalDrawer``.
///
/// Added over the window by the shell. One presence value (``DrawerMotion``) runs from 0
/// (closed) to 1 (open) on a display link: the scrim fades in place first, then the panel
/// slides in; closing runs the sequence back. The scrim leaves the content under the
/// panel undimmed, so its cut-out follows the panel each frame. Dismisses on a scrim tap,
/// a leading swipe, the close button, the VoiceOver escape gesture and, in the flyout,
/// the hardware Escape key.
@MainActor
final class UKDrawerViewController: UIViewController {
    // MARK: Inputs

    private let session: FestivalSession
    private let layoutProvider: () -> DeviceLayout
    /// Sections shown as tabs, for pushed-versus-selected destinations.
    private var visibleSections: [FestivalSection]
    private var hideShop: Bool
    private var selected: FestivalSection
    private var topRoute: AppRoute?
    private let showsSearch: Bool
    private var searchActive: Bool
    private let closesOnEscape: Bool
    private let footerScrollsAtAccessibilitySizes: Bool
    private let slides: Bool
    private let onIntent: (DrawerIntent) -> Void
    private let onClose: () -> Void
    private let onDismissed: () -> Void

    // MARK: Views

    private let scrim = UIView()
    private let scrimMask = CAShapeLayer()
    private let panel = UIView()
    private let glass = UKGlassView(.overlay, cornerRadius: DrawerCorners.legacyRadius)
    private let content = UIView()
    private let header = UIStackView()
    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let scroll = UIScrollView()
    private let rows = UIStackView()
    private let footer = UIStackView()
    private let focusAnchor = AccessibilityFocusAnchor.AnchorView()
    private var panelPan: UIPanGestureRecognizer?

    // MARK: State

    private var presence: Double
    private var isPresented = true
    private var link: CADisplayLink?
    private var animationStart: CFTimeInterval = 0
    private var animationFrom: Double = 0
    private var animationTo: Double = 1
    private var dragOffset: CGFloat = 0
    private var placement: DrawerPlacement?
    private var focusToken = 0

    /// Creates a drawer.
    ///
    /// - Parameters:
    ///   - session: The shared session (selected player).
    ///   - layout: The current window layout.
    ///   - visibleSections: Sections shown as tabs.
    ///   - hideShop: Settings › Hide Item Shop.
    ///   - selected: The selected root section.
    ///   - topRoute: The route on top of the selected section's stack.
    ///   - showsSearch: A Search row heads the list (the iPad flyout).
    ///   - searchActive: Global search is showing.
    ///   - closesOnEscape: The hardware Escape key closes the panel.
    ///   - footerScrolls: The footer scrolls with the rows at accessibility sizes.
    ///   - slides: Whether the panel slides (false: it fades in place, Reduce Motion).
    ///   - onIntent: A row was chosen.
    ///   - onClose: Close without choosing.
    ///   - onDismissed: The close sequence finished.
    init(
        session: FestivalSession, layout: @escaping () -> DeviceLayout, visibleSections: [FestivalSection],
        hideShop: Bool, selected: FestivalSection, topRoute: AppRoute?, showsSearch: Bool, searchActive: Bool,
        closesOnEscape: Bool, footerScrolls: Bool, slides: Bool, onIntent: @escaping (DrawerIntent) -> Void,
        onClose: @escaping () -> Void, onDismissed: @escaping () -> Void
    ) {
        self.session = session
        self.layoutProvider = layout
        self.visibleSections = visibleSections
        self.hideShop = hideShop
        self.selected = selected
        self.topRoute = topRoute
        self.showsSearch = showsSearch
        self.searchActive = searchActive
        self.closesOnEscape = closesOnEscape
        self.footerScrollsAtAccessibilitySizes = footerScrolls
        self.slides = slides
        self.onIntent = onIntent
        self.onClose = onClose
        self.onDismissed = onDismissed
        presence = 0
        super.init(nibName: nil, bundle: nil)
        overrideUserInterfaceStyle = .dark
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        scrim.backgroundColor = .black
        scrim.alpha = 0
        scrimMask.fillRule = .evenOdd
        scrim.layer.mask = scrimMask
        scrim.isAccessibilityElement = false
        scrim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(scrimTapped)))
        view.addSubview(scrim)

        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.3
        panel.layer.shadowRadius = 20
        panel.layer.shadowOffset = CGSize(width: 4, height: 0)
        view.addSubview(panel)
        // The panel is `FestivalGlassModifier(role: .overlay)` on a concentric shape in
        // SwiftUI: the same surface, including the Reduce Transparency and Increase
        // Contrast fallbacks.
        glass.translatesAutoresizingMaskIntoConstraints = true
        glass.concentricMinimumRadius = DrawerCorners.minimumRadius
        glass.clipsToBounds = true
        panel.addSubview(glass)

        content.accessibilityIdentifier = "fst.shell.drawer"
        content.accessibilityViewIsModal = true
        glass.contentView.addSubview(content)
        content.clipsToBounds = true
        applyCorners(to: content)
        buildStructure()
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        panel.addGestureRecognizer(pan)
        panelPan = pan
        focusAnchor.isUserInteractionEnabled = false
        focusAnchor.isAccessibilityElement = false
        content.addSubview(focusAnchor)
        reload()
        applyPresence()
    }

    private func applyCorners(to target: UIView) {
        if #available(iOS 26.0, *) {
            target.cornerConfiguration = .corners(radius: .containerConcentric(minimum: DrawerCorners.minimumRadius))
        } else {
            target.layer.cornerRadius = DrawerCorners.legacyRadius
            target.layer.cornerCurve = .continuous
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let layout = layoutProvider()
        let resolved = DrawerPlacement.resolve(
            size: view.bounds.size, uikitSafeArea: view.safeAreaInsets, layout: layout
        )
        placement = resolved
        scrim.frame = view.bounds
        scrimMask.frame = scrim.bounds
        let frame = resolved.panelFrame(in: view.bounds.size)
        panel.bounds = CGRect(origin: .zero, size: frame.size)
        panel.center = CGPoint(x: frame.midX, y: frame.midY)
        glass.frame = panel.bounds
        glass.layoutIfNeeded()
        content.frame = glass.contentView.bounds
        layoutContent(resolved)
        applyPresence()
    }

    private func layoutContent(_ placement: DrawerPlacement) {
        let inset = DrawerCorners.contentInset
        header.frame = .zero
        let top = placement.contentTop
        let bottom = placement.contentBottom
        content.directionalLayoutMargins = NSDirectionalEdgeInsets(top: top, leading: inset, bottom: bottom, trailing: inset)
        focusAnchor.frame = content.bounds
        // Layout passes come often: move the footer only when its placement changed.
        if footerPlacedScrolling != footerScrolls { updateFooterPlacement() }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        view.setNeedsLayout()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            reload()
        }
    }

    // MARK: Structure

    private func buildStructure() {
        titleLabel.text = "Festival Score Tracker"
        titleLabel.font = UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .title3).pointSize, weight: .bold)
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = BrandUIColors.textPrimary
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(textStyle: .body, scale: .default))
        configuration.baseForegroundColor = BrandUIColors.textSecondary
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        closeButton.configuration = configuration
        closeButton.accessibilityLabel = "Close Navigation"
        closeButton.accessibilityIdentifier = "fst.shell.drawer.close"
        closeButton.addAction(UIAction { [weak self] _ in self?.onClose() }, for: .touchUpInside)
        closeButton.setContentHuggingPriority(.required, for: .horizontal)
        closeButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        closeButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true

        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 8
        header.isLayoutMarginsRelativeArrangement = true
        header.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 0)
        header.addArrangedSubview(titleLabel)
        header.addArrangedSubview(closeButton)

        rows.axis = .vertical
        rows.spacing = 2
        footer.axis = .vertical
        footer.spacing = 2

        scroll.alwaysBounceVertical = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never

        let column = UIStackView(arrangedSubviews: [header, scroll, footer])
        column.axis = .vertical
        column.spacing = 12
        column.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(column)
        rows.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(rows)
        let guide = content.layoutMarginsGuide
        NSLayoutConstraint.activate([
            column.topAnchor.constraint(equalTo: guide.topAnchor),
            column.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            rows.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            rows.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            rows.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        let height = rows.heightAnchor.constraint(equalTo: scroll.heightAnchor)
        height.priority = .defaultLow
        height.isActive = true
        scroll.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    }

    private var profile: FestivalProfileKind { session.selectedPlayer == nil ? .none : .player }

    private var footerScrolls: Bool {
        footerScrollsAtAccessibilitySizes && traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    }

    /// Rebuilds the rows for the current selection, profile and text size.
    func reload() {
        guard isViewLoaded else { return }
        let items = (showsSearch ? [DrawerMenu.search] : [])
            + DrawerMenu.browse(profile: profile, visibleSections: visibleSections, hideShop: hideShop)
        // The shell reloads on every session, settings and path change; rebuild only when the
        // rows would differ, or a refresh mid-tap swaps the touched control (Deselect lost taps).
        let signature = items.map { "\($0.id):\(isCurrent($0))" }.joined(separator: ",")
            + "|\(session.selectedPlayer?.accountId ?? "")/\(session.selectedPlayer?.displayName ?? "")|\(footerScrolls)|\(traitCollection.preferredContentSizeCategory.rawValue)"
        guard signature != shownSignature else { return }
        shownSignature = signature
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        footer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in items { rows.addArrangedSubview(row(for: item)) }
        updateFooterPlacement()
    }

    private var shownSignature: String?

    /// Whether a row names the page on screen.
    private func isCurrent(_ item: DrawerItem) -> Bool {
        item.intent == .openSearch
            ? searchActive
            : !searchActive && DrawerMenu.isCurrent(item, selected: selected, topRoute: topRoute)
    }

    /// Whether the footer rows sit at the end of the scrolling rows, as last placed.
    private var footerPlacedScrolling: Bool?

    private func updateFooterPlacement() {
        guard isViewLoaded else { return }
        footerPlacedScrolling = footerScrolls
        footer.arrangedSubviews.forEach { $0.removeFromSuperview() }
        // Footer rows that scroll live at the end of the rows; otherwise pinned below.
        let scrolling = footerScrolls
        let target = scrolling ? rows : footer
        // Remove previously scrolled footer rows.
        rows.arrangedSubviews.filter { $0.tag == Self.footerTag }.forEach { $0.removeFromSuperview() }
        let views = footerViews()
        for (index, view) in views.enumerated() {
            view.tag = Self.footerTag
            if scrolling, target === rows {
                if index == 0 {
                    let spacer = UIView()
                    spacer.heightAnchor.constraint(equalToConstant: 6).isActive = true
                    spacer.tag = Self.footerTag
                    rows.addArrangedSubview(spacer)
                }
                rows.addArrangedSubview(view)
            } else {
                footer.addArrangedSubview(view)
            }
        }
    }

    private static let footerTag = 7_001

    private func footerViews() -> [UIView] {
        var views: [UIView] = [profileSection()]
        for item in DrawerMenu.more { views.append(row(for: item)) }
        return views
    }

    private func row(for item: DrawerItem) -> UKDrawerRow {
        let view = UKDrawerRow(title: item.title, symbol: item.symbol, isCurrent: isCurrent(item))
        view.accessibilityIdentifier = "fst.shell.drawer.\(item.id)"
        view.addAction(UIAction { [weak self] _ in self?.onIntent(item.intent) }, for: .touchUpInside)
        return view
    }

    private func profileSection() -> UIView {
        guard let player = session.selectedPlayer else {
            let view = UKDrawerRow(
                title: "Select Profile", symbol: "person.crop.circle.badge.plus", tint: BrandUIColors.accentBlue
            )
            view.accessibilityIdentifier = "fst.shell.drawer.select-profile"
            view.addAction(UIAction { [weak self] _ in self?.onIntent(.chooseProfile) }, for: .touchUpInside)
            return view
        }
        let name = UKDrawerRow(title: player.displayName, symbol: nil, avatar: player.displayName)
        name.accessibilityLabel = DrawerMenu.selectedPlayerAccessibilityLabel(player.displayName)
        name.accessibilityHint = "Opens your profile"
        name.accessibilityIdentifier = "fst.shell.drawer.view-profile"
        name.addAction(UIAction { [weak self] _ in
            self?.onIntent(.push(.player(accountId: player.accountId, displayName: player.displayName)))
        }, for: .touchUpInside)
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Deselect"
        configuration.baseBackgroundColor = BrandUIColors.statusRed
        configuration.baseForegroundColor = .white
        configuration.buttonSize = .large
        configuration.cornerStyle = .capsule
        let deselect = UIButton(configuration: configuration)
        deselect.accessibilityLabel = "Deselect Profile"
        deselect.accessibilityIdentifier = "fst.shell.drawer.deselect-profile"
        deselect.titleLabel?.adjustsFontForContentSizeCategory = true
        deselect.setContentHuggingPriority(.required, for: .horizontal)
        deselect.addAction(UIAction { [weak self] _ in self?.confirmDeselect(from: deselect) }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [name, deselect])
        stack.axis = traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
        stack.alignment = stack.axis == .vertical ? .leading : .center
        stack.spacing = stack.axis == .vertical ? 4 : 8
        return stack
    }

    private func confirmDeselect(from source: UIView) {
        let name = session.selectedPlayer?.displayName ?? "Profile"
        let alert = UIAlertController(
            title: "Deselect \(name)?", message: "Scores and profile tabs will be hidden until you select a profile again.",
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "Deselect Profile", style: .destructive) { [weak self] _ in
            self?.onIntent(.deselectProfile)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = source
        alert.popoverPresentationController?.sourceRect = source.bounds
        present(alert, animated: true)
    }

    /// Updates the highlighted destination and profile rows without rebuilding the panel.
    ///
    /// - Parameters:
    ///   - selected: The selected root section.
    ///   - topRoute: The route on top of its stack.
    ///   - searchActive: Whether Search shows.
    ///   - visibleSections: Sections shown as tabs.
    ///   - hideShop: Settings › Hide Item Shop.
    func update(selected: FestivalSection, topRoute: AppRoute?, searchActive: Bool, visibleSections: [FestivalSection], hideShop: Bool) {
        self.selected = selected
        self.topRoute = topRoute
        self.searchActive = searchActive
        self.visibleSections = visibleSections
        self.hideShop = hideShop
        reload()
    }

    // MARK: Gestures

    @objc private func scrimTapped() { onClose() }

    @objc private func panned(_ gesture: UIPanGestureRecognizer) {
        let width = panel.bounds.width
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .changed:
            dragOffset = min(0, translation.x)
            applyPresence()
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: view).x
            let predicted = translation.x + velocity * 0.2
            if translation.x < -width / 3 || predicted < -width / 2 {
                onClose()
            } else {
                animateDrag(to: 0)
            }
        default: break
        }
    }

    private func animateDrag(to value: CGFloat) {
        let reduce = UIAccessibility.isReduceMotionEnabled
        let start = dragOffset
        guard start != value else { return }
        if reduce { dragOffset = value; applyPresence(); return }
        let duration = 0.25
        let begin = CACurrentMediaTime()
        let timer = CADisplayLink(target: BlockTarget { [weak self] link in
            guard let self else { link.invalidate(); return }
            let t = min(1, (CACurrentMediaTime() - begin) / duration)
            let eased = 1 - pow(1 - t, 3)
            self.dragOffset = start + (value - start) * CGFloat(eased)
            self.applyPresence()
            if t >= 1 { link.invalidate() }
        }, selector: #selector(BlockTarget.fire(_:)))
        timer.add(to: .main, forMode: .common)
    }

    // MARK: Motion

    /// Shows the drawer open at once (a launch that starts with it open).
    func skipToOpen() {
        presence = 1
        applyPresence()
    }

    /// Runs the open sequence (scrim, then panel).
    func animateIn() {
        run(to: 1)
    }

    /// Runs the close sequence (panel, then scrim) and reports ``onDismissed``.
    func animateOut() {
        isPresented = false
        view.isUserInteractionEnabled = false
        content.accessibilityViewIsModal = false
        view.accessibilityElementsHidden = true
        run(to: 0)
    }

    private func run(to target: Double) {
        link?.invalidate()
        animationFrom = presence
        animationTo = target
        animationStart = CACurrentMediaTime()
        let timer = CADisplayLink(target: BlockTarget { [weak self] link in self?.step(link) }, selector: #selector(BlockTarget.fire(_:)))
        timer.add(to: .main, forMode: .common)
        link = timer
    }

    private func step(_ link: CADisplayLink) {
        let total = DrawerMotion.totalDuration * DrawerMotion.timeScale
        let elapsed = CACurrentMediaTime() - animationStart
        let t = total > 0 ? min(1, elapsed / total) : 1
        presence = animationFrom + (animationTo - animationFrom) * t
        applyPresence()
        if t >= 1 {
            link.invalidate()
            self.link = nil
            if animationTo == 0 {
                onDismissed()
            } else {
                UIAccessibility.post(notification: .screenChanged, argument: titleLabel)
            }
        }
    }

    private func applyPresence() {
        guard isViewLoaded else { return }
        let motion = DrawerMotion(presence: presence, slides: slides)
        let width = max(panel.bounds.width, 1)
        let progress = max(0, min(1, 1 + dragOffset / width))
        scrim.alpha = DrawerMotion.scrimOpacity * motion.scrim * progress
        let hidden = (placement?.uikitPanelPadding.left ?? 0) + width + DrawerMotion.shadowClearance
        let offset = motion.panelOffset(hiddenDistance: hidden) + min(0, dragOffset)
        panel.transform = CGAffineTransform(translationX: offset, y: 0)
        panel.alpha = motion.panelOpacity
        // The scrim's cut-out follows the panel.
        let frame = panel.frame
        let radius = cutoutRadius()
        let path = UIBezierPath(rect: scrim.bounds)
        path.append(UIBezierPath(roundedRect: frame, cornerRadius: radius))
        scrimMask.path = path.cgPath
    }

    private func cutoutRadius() -> CGFloat {
        if #available(iOS 26.0, *) {
            return max(DrawerCorners.minimumRadius, glass.effectiveCornerRadius)
        }
        return DrawerCorners.legacyRadius
    }

    // MARK: Accessibility & keys

    override func accessibilityPerformEscape() -> Bool {
        onClose()
        return true
    }

    override var keyCommands: [UIKeyCommand]? {
        guard closesOnEscape, isPresented else { return nil }
        let command = UIKeyCommand(title: "Close Navigation", action: #selector(escapePressed), input: UIKeyCommand.inputEscape)
        command.wantsPriorityOverSystemBehavior = true
        return [command]
    }

    @objc private func escapePressed() { onClose() }
}

extension UKDrawerViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y) && velocity.x < 0
    }
}

/// Selector target for a display link.
@MainActor
private final class BlockTarget {
    private let block: (CADisplayLink) -> Void
    init(_ block: @escaping (CADisplayLink) -> Void) { self.block = block }
    @objc func fire(_ link: CADisplayLink) { block(link) }
}

// MARK: - Row

/// A full-width drawer row with an SF Symbol (or the selected player's avatar), at least
/// 48 pt tall, highlighted while pressed and while it names the page on screen.
@MainActor
final class UKDrawerRow: UIControl {
    private let stack = UIStackView()
    private let iconView = UIImageView()
    private let label = UILabel()
    private let isCurrent: Bool
    private let tint: UIColor?

    /// Creates a row.
    ///
    /// - Parameters:
    ///   - title: Row title.
    ///   - symbol: SF Symbol name, or nil with an avatar.
    ///   - tint: Symbol tint; nil is the secondary text colour.
    ///   - isCurrent: Highlights the page on screen.
    ///   - avatar: The selected player's name; draws the monogram instead of a symbol.
    init(title: String, symbol: String?, tint: UIColor? = nil, isCurrent: Bool = false, avatar: String? = nil) {
        self.isCurrent = isCurrent
        self.tint = tint
        super.init(frame: .zero)
        layer.cornerRadius = DrawerCorners.rowRadius
        layer.cornerCurve = .continuous
        backgroundColor = isCurrent ? BrandUIColors.accentBlue.withAlphaComponent(0.28) : .clear
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = isCurrent ? [.button, .selected] : .button
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = DrawerRow.iconSpacing
        stack.isUserInteractionEnabled = false
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let column = UIFontMetrics(forTextStyle: .body).scaledValue(for: DrawerRow.iconWidth)
        iconView.contentMode = .center
        iconView.isAccessibilityElement = false
        if let avatar {
            iconView.image = UKMonogram.image(name: avatar, size: column, scale: UIScreen.main.scale)
            iconView.contentMode = .scaleAspectFit
        } else if let symbol {
            iconView.image = UIImage(
                systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(textStyle: .body, scale: .default)
                    .applying(UIImage.SymbolConfiguration(weight: .medium))
            )
            iconView.tintColor = tint ?? BrandUIColors.textSecondary
        }
        iconView.widthAnchor.constraint(equalToConstant: column).isActive = true
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = BrandUIColors.textPrimary
        label.numberOfLines = avatar == nil ? 0 : 1
        label.lineBreakMode = .byTruncatingTail
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet {
            backgroundColor = isHighlighted
                ? UIColor.white.withAlphaComponent(0.12)
                : (isCurrent ? BrandUIColors.accentBlue.withAlphaComponent(0.28) : .clear)
        }
    }
}
#endif
