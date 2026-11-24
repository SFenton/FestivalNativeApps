#if os(iOS)
import FestivalCore
import FestivalDesign
import UIKit

// MARK: - Fold-avoiding fill

/// A scroll view that centres its content in the larger side of an iPhone Duo hinge
/// (``FestivalCentredFill`` and ``FoldAvoidingPlacement``): content is `padding` inset,
/// at least as tall as the region, and bounces only when it overflows.
final class UKCentredFillView: UIScrollView {
    /// The centred content.
    let contentContainer = UIView()
    /// The hinge in window coordinates, or nil while there is no fold
    /// (`DeviceLayout.splitHinge`).
    var hingeProvider: (() -> CGRect?)?
    private let padding: CGFloat

    /// Creates the fill.
    ///
    /// - Parameter padding: Inset around the content (24 pt for empty states).
    init(padding: CGFloat) {
        self.padding = padding
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        alwaysBounceVertical = false
        keyboardDismissMode = .onDrag
        showsVerticalScrollIndicator = true
        addSubview(contentContainer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let container = convert(bounds, to: nil)
        let region = FoldAvoidingPlacement.region(
            container: window == nil ? CGRect(origin: .zero, size: bounds.size) : container, fold: hingeProvider?()
        )
        let width = max(region.width - padding * 2, 1)
        let fitted = contentContainer.systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
            withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel
        )
        let top = region.minY + max(padding, (region.height - fitted.height) / 2)
        contentContainer.frame = CGRect(x: region.minX + padding, y: top, width: width, height: fitted.height)
        contentSize = CGSize(width: bounds.width, height: max(bounds.height, top + fitted.height + padding))
        alwaysBounceVertical = contentSize.height > bounds.height + 0.5
    }
}

// MARK: - Empty state

/// The shared empty state (``FestivalEmptyState``): an optional large symbol, a bold
/// centred title (heading), a centred body subtitle and optional actions. `fill` centres
/// it in the page, avoiding an iPhone Duo hinge; `inline` sits in a list with 48 pt
/// vertical padding. A `combined` reading speaks title and subtitle as one static text.
final class UKEmptyStateView: UIView {
    /// ``FestivalEmptyState/Placement``.
    typealias Placement = FestivalEmptyStatePlacement
    /// ``FestivalEmptyState/Reading``.
    typealias Reading = FestivalEmptyStateReading

    /// Spacing inside the state.
    static let spacing: CGFloat = 12
    /// Padding around a `fill` state and beside an `inline` one.
    static let fillPadding: CGFloat = 24
    /// Vertical padding of an `inline` state.
    static let inlineVerticalPadding: CGFloat = 48

    /// Hinge provider for `fill` placement.
    var hingeProvider: (() -> CGRect?)? {
        get { fill?.hingeProvider }
        set {
            fill?.hingeProvider = newValue
            fill?.setNeedsLayout()
        }
    }

    private var fill: UKCentredFillView?

    /// Creates an empty state.
    ///
    /// - Parameters:
    ///   - title: Title Case title.
    ///   - systemImage: SF Symbol name above the title.
    ///   - subtitle: Supporting line.
    ///   - placement: Centred `fill` or `inline`.
    ///   - reading: Whether title and subtitle read as one element.
    ///   - identifier: Accessibility identifier of the state (or of the combined text).
    ///   - actions: Buttons shown under the text.
    init(
        _ title: String, systemImage: String? = nil, subtitle: String? = nil, placement: Placement = .fill,
        reading: Reading = .separate, identifier: String? = nil, actions: [UIView] = []
    ) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let content = UIStackView()
        content.axis = .vertical
        content.alignment = .fill
        content.spacing = Self.spacing
        content.translatesAutoresizingMaskIntoConstraints = false
        if let systemImage {
            let image = UIImageView(image: UIImage(systemName: systemImage))
            image.tintColor = BrandUIColors.textPrimary
            image.contentMode = .scaleAspectFit
            image.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.largeTitle))
            image.isAccessibilityElement = false
            image.accessibilityElementsHidden = true
            content.addArrangedSubview(image)
        }
        let texts = UIStackView(arrangedSubviews: [UKStateTitleLabel(title)] + (subtitle.map { [UKStateSubtitleLabel($0)] } ?? []))
        texts.axis = .vertical
        texts.spacing = Self.spacing
        content.addArrangedSubview(texts)
        actions.forEach(content.addArrangedSubview)
        switch reading {
        case .separate:
            content.accessibilityContainerType = .semanticGroup
            content.accessibilityIdentifier = identifier
        case .combined:
            texts.isAccessibilityElement = true
            texts.accessibilityLabel = FestivalEmptyStateCopy.accessibilityLabel(title: title, subtitle: subtitle)
            texts.accessibilityTraits = .staticText
            texts.accessibilityIdentifier = identifier
        }
        switch placement {
        case .fill:
            let fill = UKCentredFillView(padding: Self.fillPadding)
            fill.contentContainer.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: fill.contentContainer.leadingAnchor),
                content.trailingAnchor.constraint(equalTo: fill.contentContainer.trailingAnchor),
                content.topAnchor.constraint(equalTo: fill.contentContainer.topAnchor),
                content.bottomAnchor.constraint(equalTo: fill.contentContainer.bottomAnchor),
            ])
            addSubview(fill)
            NSLayoutConstraint.activate([
                fill.leadingAnchor.constraint(equalTo: leadingAnchor), fill.trailingAnchor.constraint(equalTo: trailingAnchor),
                fill.topAnchor.constraint(equalTo: topAnchor), fill.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            self.fill = fill
        case .inline:
            addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.fillPadding),
                content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.fillPadding),
                content.topAnchor.constraint(equalTo: topAnchor, constant: Self.inlineVerticalPadding),
                content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.inlineVerticalPadding),
            ])
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Bold, centred state title (``FestivalStateTitle``).
final class UKStateTitleLabel: UILabel {
    /// Creates the title.
    init(_ text: String) {
        super.init(frame: .zero)
        self.text = text
        font = UKFont.font(.title2, weight: .bold)
        adjustsFontForContentSizeCategory = true
        textColor = BrandUIColors.textPrimary
        textAlignment = .center
        numberOfLines = 0
        accessibilityTraits.insert(.header)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// Centred body state subtitle (``FestivalStateSubtitle``).
final class UKStateSubtitleLabel: UILabel {
    /// Creates the subtitle.
    init(_ text: String) {
        super.init(frame: .zero)
        self.text = text
        font = UKFont.font(.body)
        adjustsFontForContentSizeCategory = true
        textColor = BrandUIColors.textPrimary
        textAlignment = .center
        numberOfLines = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Loading view

/// The white arc spinner (``FestivalLoadingView``, ``FestivalArcProgressStyle``): a 10%
/// white track (25% under increased contrast) and a quarter-circle white arc turning once
/// per 0.8 s. With a `status` it sits beside a white label (small control size); without
/// one it is spoken as "Loading" (or `accessibilityLabel`).
final class UKLoadingView: UIView {
    /// Spinner size (SwiftUI control size).
    enum Size {
        case small, medium, large

        var metrics: FestivalArcMetrics.Size {
            switch self {
            case .small: FestivalArcMetrics.small
            case .medium: FestivalArcMetrics.medium
            case .large: FestivalArcMetrics.large
            }
        }
    }

    /// Where a loading view sits (``FestivalLoadingView/Placement``).
    typealias Placement = FestivalLoadingView.Placement

    private let arc: UKArcView
    private let placement: Placement
    private let usesPageRegion: Bool
    /// Hinge provider for `fill` placement.
    var hingeProvider: (() -> CGRect?)?

    /// Creates a loading view.
    ///
    /// - Parameters:
    ///   - accessibilityLabel: Spoken label of the bare spinner.
    ///   - placement: `inline` or centred `fill` (large spinner, fold-aware).
    ///   - status: Optional text beside the spinner.
    ///   - identifier: Accessibility identifier of the named busy indicator.
    ///   - size: An explicit arc size, or nil for the size implied by placement and status.
    ///   - usesPageRegion: Intersect the host with its safe area and active fold. False
    ///     preserves a result viewer that has already supplied the exact region.
    init(
        accessibilityLabel: String = "Loading", placement: Placement = .inline,
        status: String? = nil, identifier: String? = nil, size: Size? = nil,
        usesPageRegion: Bool = true
    ) {
        self.placement = placement
        self.usesPageRegion = usesPageRegion
        arc = UKArcView(size: size ?? (placement == .fill ? .large : (status == nil ? .medium : .small)))
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        if let status {
            let label = UKLabel(status)
            let stack = UIStackView(arrangedSubviews: [arc, label])
            stack.axis = .horizontal
            stack.spacing = 12
            stack.alignment = .center
            stack.translatesAutoresizingMaskIntoConstraints = false
            addSubview(stack)
            pin(stack)
            arc.isAccessibilityElement = false
            stack.isAccessibilityElement = true
            stack.accessibilityLabel = status
            stack.accessibilityIdentifier = identifier
            stack.accessibilityTraits = .updatesFrequently
        } else {
            addSubview(arc)
            arc.exposeAsActivityIndicator(label: accessibilityLabel, identifier: identifier)
            if placement == .inline {
                pin(arc)
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func pin(_ view: UIView) {
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard placement == .fill, arc.superview === self else { return }
        let viewport = window == nil
            ? CGRect(origin: .zero, size: bounds.size)
            : convert(bounds, to: nil)
        let region: CGRect
        if usesPageRegion {
            let usable = window == nil
                ? viewport
                : convert(safeAreaLayoutGuide.layoutFrame, to: nil)
            region = LoadingRegionPolicy.region(
                viewport: viewport, usable: usable, fold: resolvedHinge()
            )
        } else {
            region = FoldAvoidingPlacement.region(container: viewport, fold: hingeProvider?())
        }
        arc.center = CGPoint(x: region.midX, y: region.midY)
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        setNeedsLayout()
    }

    private func resolvedHinge() -> CGRect? {
        if let hingeProvider { return hingeProvider() }
        var responder: UIResponder? = self
        while let current = responder?.next {
            if let controller = current as? UIViewController { return controller.ukLayout.splitHinge }
            responder = current
        }
        return nil
    }
}

/// The spinning arc.
final class UKArcView: UIView {
    private let track = CAShapeLayer()
    private let arc = CAShapeLayer()
    private let metrics: FestivalArcMetrics.Size

    /// Creates an arc of a size.
    init(size: UKLoadingView.Size) {
        metrics = size.metrics
        super.init(frame: CGRect(x: 0, y: 0, width: metrics.diameter, height: metrics.diameter))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: metrics.diameter), heightAnchor.constraint(equalToConstant: metrics.diameter),
        ])
        let inset = metrics.lineWidth / 2
        let rect = CGRect(x: 0, y: 0, width: metrics.diameter, height: metrics.diameter).insetBy(dx: inset, dy: inset)
        let circle = UIBezierPath(ovalIn: rect)
        for shape in [track, arc] {
            shape.fillColor = nil
            shape.lineWidth = metrics.lineWidth
            shape.frame = bounds
            layer.addSublayer(shape)
        }
        track.path = circle.cgPath
        arc.path = circle.cgPath
        arc.strokeStart = 0
        arc.strokeEnd = CGFloat(FestivalArcMetrics.sweep)
        arc.strokeColor = UIColor.white.cgColor
        arc.lineCap = .butt
        registerForTraitChanges([UITraitAccessibilityContrast.self]) { (self: UKArcView, _) in self.applyTrack() }
        applyTrack()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Speaks the arc as a busy indicator named `label`. XCUITest types an element by its
    /// class, and only a `UIActivityIndicatorView` is an `activityIndicator` (SwiftUI's
    /// `ProgressView` is one), so an invisible one carries the label over the drawn arc.
    ///
    /// - Parameters:
    ///   - label: The spoken name ("Loading text path").
    ///   - identifier: Accessibility identifier of the named busy indicator.
    func exposeAsActivityIndicator(label: String, identifier: String? = nil) {
        isAccessibilityElement = false
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.color = .clear
        indicator.hidesWhenStopped = false
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.isAccessibilityElement = true
        indicator.accessibilityLabel = label
        indicator.accessibilityIdentifier = identifier
        indicator.accessibilityTraits = .updatesFrequently
        addSubview(indicator)
        NSLayoutConstraint.activate([
            indicator.leadingAnchor.constraint(equalTo: leadingAnchor), indicator.trailingAnchor.constraint(equalTo: trailingAnchor),
            indicator.topAnchor.constraint(equalTo: topAnchor), indicator.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        if !DebugAnimationOverride.stillBackground { indicator.startAnimating() }
    }

    private func applyTrack() {
        let opacity = FestivalArcMetrics.trackOpacity(increasedContrast: UKAccessibility.systemIncreasedContrast(traitCollection))
        track.strokeColor = UIColor.white.withAlphaComponent(CGFloat(opacity)).cgColor
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        arc.removeAnimation(forKey: "spin")
        guard window != nil, !DebugAnimationOverride.stillBackground else { return }
        let start = -135.0 * .pi / 180
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = start
        spin.toValue = start + 2 * .pi
        spin.duration = FestivalArcMetrics.period
        spin.timingFunction = CAMediaTimingFunction(name: .linear)
        // Anchor the layer timeline to the phase used by SwiftUI's wall clock.
        let fraction = FestivalArcMetrics.angle(at: Date.timeIntervalSinceReferenceDate) / 360
        spin.beginTime = arc.convertTime(CACurrentMediaTime(), from: nil) - fraction * spin.duration
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        arc.add(spin, forKey: "spin")
    }
}

// MARK: - Service status

/// The full-page service status (``ServiceStatusView``): symbol, heading, message, a
/// monospaced-digit countdown when the issue retries by itself and a Retry / Retry Now
/// button (44 pt minimum). Counts down through ``ServiceRetryScheduler`` (announcements
/// and backoff are the shared ones) and calls `retry` when it reaches zero.
final class UKServiceStatusView: UIView {
    private let issue: ServiceIssue
    private let scope: String
    private let retry: () -> Void
    private let fallbackTitle: String
    private let countdownLabel = UKLabel(style: .body, monospacedDigit: true, lines: 0, alignment: .center)
    private let retryButton = UIButton(type: .system)
    private let scroll = UIScrollView()
    private var task: Task<Void, Never>?
    private var remaining: Int?
    /// Clock the countdown sleeps on (a test clock in tests).
    var clock: any Clock<Duration> = ContinuousClock()

    /// Creates the status view.
    ///
    /// - Parameters:
    ///   - issue: The service issue.
    ///   - title: Heading when the issue has none.
    ///   - scope: Backoff scope (defaults to the title).
    ///   - systemImage: Symbol override.
    ///   - retry: Called by the button and when the countdown ends.
    init(_ issue: ServiceIssue, title: String, scope: String? = nil, systemImage: String? = nil, retry: @escaping () -> Void) {
        self.issue = issue
        self.scope = scope ?? title
        self.retry = retry
        self.fallbackTitle = title
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let heading = issue.title ?? title
        let symbol = UIImageView(image: UIImage(systemName: systemImage ?? ServiceStatusView.symbolName(for: issue)))
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(font: UKFont.font(.largeTitle))
        symbol.tintColor = issue.retriesAutomatically ? BrandUIColors.gold : BrandUIColors.textPrimary
        symbol.contentMode = .scaleAspectFit
        symbol.isAccessibilityElement = false
        if issue.retriesAutomatically && !UKAccessibility.reduceMotion && !DebugAnimationOverride.stillBackground {
            symbol.addSymbolEffect(.pulse, options: .repeating)
        }
        let titleLabel = UKLabel(heading, style: .title2, weight: .bold, alignment: .center).asHeader()
        titleLabel.accessibilityIdentifier = "fst.service-status.title"
        let message = UKLabel(issue.message, style: .body, alignment: .center)
        countdownLabel.accessibilityIdentifier = "fst.service-status.countdown"
        countdownLabel.isHidden = true
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = BrandUIColors.textPrimary
        configuration.background.backgroundColor = BrandUIColors.cardBackground
        configuration.background.cornerRadius = 10
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
        configureRetryButton(&configuration)
        let stack = UIStackView(arrangedSubviews: [symbol, titleLabel, message, countdownLabel, retryButton])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = false
        addSubview(scroll)
        scroll.addSubview(stack)
        let holder = UILayoutGuide()
        scroll.addLayoutGuide(holder)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(greaterThanOrEqualTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: scroll.contentLayoutGuide.centerYAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48),
            scroll.contentLayoutGuide.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor),
        ])
        retryButton.configuration = configuration
        updateRetryTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func configureRetryButton(_ configuration: inout UIButton.Configuration) {
        retryButton.accessibilityIdentifier = "fst.service-status.retry"
        retryButton.addAction(UIAction { [weak self] _ in self?.retry() }, for: .primaryActionTriggered)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            retryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
    }

    private func updateRetryTitle() {
        var configuration = retryButton.configuration ?? .plain()
        var title = AttributedString(remaining == nil ? "Retry" : "Retry Now")
        title.font = UKFont.font(.body)
        configuration.attributedTitle = title
        retryButton.configuration = configuration
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        task?.cancel()
        guard window != nil else { return }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            await ServiceRetryScheduler.countdown(
                issue: self.issue, scope: self.scope, announcing: self.issue.title ?? self.fallbackTitle, clock: self.clock,
                update: { [weak self] in self?.setRemaining($0) }, retry: { [weak self] in self?.retry() }
            )
        }
    }

    private func setRemaining(_ seconds: Int?) {
        let changed = (remaining == nil) != (seconds == nil)
        remaining = seconds
        if let seconds {
            let apply = { [self] in
                countdownLabel.text = "Trying again in \(ServiceStatusView.clock(seconds))"
                countdownLabel.accessibilityLabel = "Trying again automatically in \(seconds) seconds"
            }
            if UKAccessibility.reduceMotion || countdownLabel.isHidden {
                apply()
            } else {
                UIView.transition(with: countdownLabel, duration: 0.25, options: .transitionCrossDissolve, animations: apply)
            }
        }
        countdownLabel.isHidden = seconds == nil
        if changed { updateRetryTitle() }
    }
}

/// The compact service status for inside a page or card (``ServiceStatusInline``): a
/// gold symbol, a footnote title (stacked on accessibility sizes), the countdown and an
/// optional 44 pt Retry button.
final class UKServiceStatusInlineView: UIView {
    private let issue: ServiceIssue
    private let scope: String
    private let retry: () -> Void
    private let titleText: String
    private let countdown = UKLabel(style: .footnote, monospacedDigit: true)
    private let retryButton = UIButton(type: .system)
    private let showsRetryButton: Bool
    private var task: Task<Void, Never>?
    private var remaining: Int?
    private var horizontalConstraints: [NSLayoutConstraint] = []
    private var stackedConstraints: [NSLayoutConstraint] = []
    private var activeConstraints: [NSLayoutConstraint] = []
    private var firstLineAlignment: NSLayoutConstraint?
    /// Clock the countdown sleeps on (a test clock in tests).
    var clock: any Clock<Duration> = ContinuousClock()

    /// Creates the inline status.
    ///
    /// - Parameters:
    ///   - issue: The issue.
    ///   - scope: Backoff scope.
    ///   - showsRetryButton: Show the Retry button.
    ///   - fallbackTitle: Text when the issue has no title.
    ///   - retry: Called by the button and when the countdown ends.
    init(_ issue: ServiceIssue, scope: String, showsRetryButton: Bool = true, fallbackTitle: String? = nil, retry: @escaping () -> Void) {
        self.issue = issue
        self.scope = scope
        self.retry = retry
        self.showsRetryButton = showsRetryButton
        titleText = issue.title ?? fallbackTitle ?? issue.message
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        accessibilityContainerType = .semanticGroup
        accessibilityIdentifier = "fst.service-status.inline"
        let symbol = UIImageView(image: UIImage(systemName: ServiceStatusView.symbolName(for: issue)))
        symbol.tintColor = BrandUIColors.gold
        symbol.setContentHuggingPriority(.required, for: .horizontal)
        symbol.setContentCompressionResistancePriority(.required, for: .horizontal)
        symbol.isAccessibilityElement = false
        let title = UKLabel(titleText, style: .footnote)
        countdown.isHidden = true
        let texts = UIStackView(arrangedSubviews: [title, countdown])
        texts.axis = .vertical
        texts.spacing = 2
        let lead = UIStackView(arrangedSubviews: [symbol, texts])
        lead.axis = .horizontal
        lead.alignment = .firstBaseline
        lead.spacing = 10
        lead.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lead)
        lead.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
        if showsRetryButton {
            retryButton.accessibilityIdentifier = "fst.service-status.retry"
            retryButton.addAction(UIAction { [weak self] _ in self?.retry() }, for: .primaryActionTriggered)
            retryButton.translatesAutoresizingMaskIntoConstraints = false
            retryButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
            retryButton.setContentCompressionResistancePriority(.required, for: .horizontal)
            retryButton.setContentCompressionResistancePriority(.required, for: .vertical)
            addSubview(retryButton)
            accessibilityElements = [title, countdown, retryButton]
            NSLayoutConstraint.activate([
                retryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
                retryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            ])
            let firstLine = retryButton.centerYAnchor.constraint(equalTo: title.topAnchor)
            firstLineAlignment = firstLine
            horizontalConstraints = [
                retryButton.trailingAnchor.constraint(equalTo: trailingAnchor),
                lead.trailingAnchor.constraint(lessThanOrEqualTo: retryButton.leadingAnchor, constant: -28),
                firstLine,
            ]
            // A first-line-aligned button and multiline message can each overhang the other.
            for view in [lead, retryButton] as [UIView] {
                horizontalConstraints += [
                    view.topAnchor.constraint(greaterThanOrEqualTo: topAnchor),
                    view.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor),
                ]
                let top = view.topAnchor.constraint(equalTo: topAnchor)
                let bottom = view.bottomAnchor.constraint(equalTo: bottomAnchor)
                top.priority = .defaultLow
                bottom.priority = .defaultLow
                horizontalConstraints += [top, bottom]
            }
            stackedConstraints = [
                lead.trailingAnchor.constraint(equalTo: trailingAnchor),
                lead.topAnchor.constraint(equalTo: topAnchor),
                retryButton.leadingAnchor.constraint(equalTo: leadingAnchor),
                retryButton.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
                retryButton.topAnchor.constraint(equalTo: lead.bottomAnchor, constant: 4),
                retryButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            ]
            updateRetryTitle()
        } else {
            isAccessibilityElement = true
            accessibilityTraits = .staticText
            accessibilityLabel = titleText
            NSLayoutConstraint.activate([
                lead.trailingAnchor.constraint(equalTo: trailingAnchor),
                lead.topAnchor.constraint(equalTo: topAnchor),
                lead.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
        applyAxis(lead, symbol: symbol)
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: UKServiceStatusInlineView, _) in
            if self.showsRetryButton { self.updateRetryTitle() }
            self.applyAxis(lead, symbol: symbol)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func applyAxis(_ lead: UIStackView, symbol: UIImageView) {
        let stacked = UKFont.isAccessibilitySize(traitCollection)
        lead.alignment = stacked ? .top : .firstBaseline
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            font: UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        )
        NSLayoutConstraint.deactivate(activeConstraints)
        firstLineAlignment?.constant =
            UIFont.preferredFont(forTextStyle: .footnote, compatibleWith: traitCollection).lineHeight / 2
        activeConstraints = stacked ? stackedConstraints : horizontalConstraints
        NSLayoutConstraint.activate(activeConstraints)
    }

    private func updateRetryTitle() {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = .zero
        configuration.baseForegroundColor = BrandUIColors.accentBlue
        var title = AttributedString(remaining == nil ? "Retry" : "Retry Now")
        title.font = UKFont.font(.footnote, weight: .semibold)
        configuration.attributedTitle = title
        retryButton.configuration = configuration
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        task?.cancel()
        guard window != nil else { return }
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            await ServiceRetryScheduler.countdown(
                issue: self.issue, scope: self.scope, announcing: nil, clock: self.clock,
                update: { [weak self] in self?.setRemaining($0) }, retry: { [weak self] in self?.retry() }
            )
        }
    }

    private func setRemaining(_ seconds: Int?) {
        let changed = (remaining == nil) != (seconds == nil)
        remaining = seconds
        countdown.isHidden = seconds == nil
        if let seconds {
            countdown.text = "Trying again in \(ServiceStatusView.clock(seconds))"
            countdown.accessibilityLabel = "Trying again automatically in \(seconds) seconds"
        }
        if showsRetryButton {
            if changed { updateRetryTitle() }
        } else {
            accessibilityLabel = seconds.map { "\(titleText). Trying again automatically in \($0) seconds." } ?? titleText
        }
    }
}

// MARK: - Disclosures

/// A gold notice on a `cardBackground` plate (``FreshnessDisclosure``), spoken as its
/// message.
final class UKFreshnessDisclosureView: UIView {
    /// Creates the notice.
    ///
    /// - Parameters:
    ///   - message: Text.
    ///   - symbol: SF Symbol name.
    init(message: String, symbol: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = BrandUIColors.cardBackground
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = BrandUIColors.gold
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .body)
        icon.adjustsImageSizeForAccessibilityContentSizeCategory = true
        icon.translatesAutoresizingMaskIntoConstraints = false
        // Keep the decorative glyph from claiming the wrapping message's width during fitting.
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        let label = UKLabel(message, style: .body, color: BrandUIColors.gold)
        func updateLeading(_ label: UKLabel) {
            let traits = label.traitCollection
            // At accessibility sizes the preferred line metrics already provide SwiftUI's pitch.
            let paragraph = UKFont.isAccessibilitySize(traits)
                ? NSParagraphStyle.default : UKFont.swiftUILeading(.body, traits: traits)
            label.attributedText = NSAttributedString(string: message, attributes: [.paragraphStyle: paragraph])
        }
        updateLeading(label)
        label.registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (label: UKLabel, _) in
            updateLeading(label)
        }
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 20), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
        ])
        isAccessibilityElement = true
        accessibilityLabel = message
        accessibilityTraits = .staticText
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The "Update failed" line (``RefreshErrorBanner``): a gold warning symbol and message,
/// identifier `fst.songs.refresh-error`.
final class UKRefreshErrorBanner: UIView {
    /// Creates the banner.
    ///
    /// - Parameter message: The failure reason.
    init(message: String) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        let icon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle"))
        icon.tintColor = BrandUIColors.gold
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = UKLabel("Update failed: \(message)", color: BrandUIColors.gold)
        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.spacing = 6
        stack.alignment = .firstBaseline
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isAccessibilityElement = true
        accessibilityLabel = "Update failed: \(message)"
        accessibilityIdentifier = "fst.songs.refresh-error"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
#endif
