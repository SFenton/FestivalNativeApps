import SwiftUI
import FestivalDesign

// MARK: - Empty state

/// The one empty state for every page, region and pane (issue #377,
/// `.agents/patterns/empty-error-states.md` R2/R5/R8): the web `EmptyState`'s optional
/// icon, bold title and subtitle, centred horizontally and vertically, on no card and
/// with no Reset or Retry button.
///
/// Built from scalable text rather than `ContentUnavailableView` (which failed iOS 26.5
/// Dynamic Type audits, see ``ServiceStatusView``), so the copy wraps at every text size
/// and, filling its region, scrolls when it cannot fit. On a partially folded iPhone Duo
/// it centres beside the fold, never on it (``FoldAvoidingPlacement``).
///
/// The subtitle names the next step (HIG Writing: "Provide clear next steps on any blank
/// screens"). The only action an empty state may carry is a prerequisite such as Choose
/// Profile; filters are changed from the page's own Filter control. Loading and failures
/// keep ``FestivalLoadingView`` and ``ServiceStatusView`` (R1).
struct FestivalEmptyState<Actions: View>: View {
    /// Where the state sits in its container (web `EmptyState` `fullPage`).
    enum Placement: Sendable {
        /// Fill the proposed region and centre in it, scrolling at large text sizes.
        /// For a page, a list region or a pane with a bounded height.
        case fill
        /// Content height with the web's 48-point vertical padding, centred
        /// horizontally. For a region inside an existing scroll view.
        case inline
    }

    /// How VoiceOver reads the title and subtitle.
    enum Reading: Sendable {
        /// The title as a heading, then the subtitle (the default).
        case separate
        /// One static element, "title. subtitle" (Global Search, issue #299).
        case combined
    }

    private let title: String
    private let systemImage: String?
    private let subtitle: String?
    private let placement: Placement
    private let reading: Reading
    private let identifier: String?
    private let actions: Actions
    @Environment(\.deviceLayout) private var layout

    /// Create an empty state.
    ///
    /// - Parameters:
    ///   - title: Short headline naming what is empty.
    ///   - systemImage: Optional decorative SF Symbol above the title.
    ///   - subtitle: Optional sentence with the next step.
    ///   - placement: Fill the region (default) or sit inline in a scroll view.
    ///   - reading: Separate heading and subtitle (default) or one combined element.
    ///   - accessibilityIdentifier: Test ID: on the combined element, else the container.
    ///   - actions: A prerequisite action only (Choose Profile), never Reset or Retry.
    init(
        _ title: String, systemImage: String? = nil, subtitle: String? = nil,
        placement: Placement = .fill, reading: Reading = .separate,
        accessibilityIdentifier: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
        self.placement = placement
        self.reading = reading
        self.identifier = accessibilityIdentifier
        self.actions = actions()
    }

    var body: some View {
        switch placement {
        case .fill:
            GeometryReader { proxy in
                let region = FoldAvoidingPlacement.region(
                    container: proxy.frame(in: .global), fold: layout.splitHinge
                )
                ScrollView {
                    content
                        .padding(Self.fillPadding)
                        .frame(width: region.width)
                        .frame(minHeight: region.height)
                        .padding(.leading, region.minX)
                        .padding(.top, region.minY)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.immediately)
            }
        case .inline:
            content
                .padding(.vertical, Self.inlineVerticalPadding)
                .padding(.horizontal, Self.fillPadding)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Metrics

    /// Padding around a filling state's content.
    static var fillPadding: CGFloat { 24 }
    /// Web `EmptyState` vertical padding (`padding(48, Gap.xl)`).
    static var inlineVerticalPadding: CGFloat { 48 }
    /// Web `EmptyState` `gap: Gap.md` between icon, title and subtitle.
    static var spacing: CGFloat { 12 }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: Self.spacing) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.largeTitle)
                    .foregroundStyle(FestivalText.primary)
                    .accessibilityHidden(true)
            }
            switch reading {
            case .separate:
                texts
            case .combined:
                texts
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        FestivalEmptyStateCopy.accessibilityLabel(title: title, subtitle: subtitle)
                    )
                    .accessibilityAddTraits(.isStaticText)
                    .emptyStateIdentifier(identifier)
            }
            actions
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .emptyStateIdentifier(reading == .separate ? identifier : nil)
    }

    private var texts: some View {
        VStack(spacing: Self.spacing) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(BrandTokens.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(FestivalText.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

extension FestivalEmptyState where Actions == EmptyView {
    /// Create an empty state with no action (the usual case).
    ///
    /// - Parameters:
    ///   - title: Short headline naming what is empty.
    ///   - systemImage: Optional decorative SF Symbol above the title.
    ///   - subtitle: Optional sentence with the next step.
    ///   - placement: Fill the region (default) or sit inline in a scroll view.
    ///   - reading: Separate heading and subtitle (default) or one combined element.
    ///   - accessibilityIdentifier: Test ID: on the combined element, else the container.
    init(
        _ title: String, systemImage: String? = nil, subtitle: String? = nil,
        placement: Placement = .fill, reading: Reading = .separate,
        accessibilityIdentifier: String? = nil
    ) {
        self.init(
            title, systemImage: systemImage, subtitle: subtitle, placement: placement,
            reading: reading, accessibilityIdentifier: accessibilityIdentifier
        ) { EmptyView() }
    }
}

// MARK: - Copy

/// Text rules shared by every ``FestivalEmptyState``.
enum FestivalEmptyStateCopy {
    /// One VoiceOver label for a combined state: the title, then the subtitle.
    ///
    /// - Parameters:
    ///   - title: The state's headline.
    ///   - subtitle: The optional next-step sentence.
    /// - Returns: "title. subtitle", or the title alone when there is no subtitle.
    static func accessibilityLabel(title: String, subtitle: String?) -> String {
        guard let subtitle, !subtitle.isEmpty else { return title }
        return "\(title). \(subtitle)"
    }
}

// MARK: - Identifier

private extension View {
    /// Apply a test identifier only when one is given, so a nil never blanks the
    /// identifiers SwiftUI would otherwise expose.
    @ViewBuilder
    func emptyStateIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

// MARK: - Fold-avoiding placement

/// Where a centred message sits so nothing lands on an iPhone Duo fold
/// (`.agents/design/apple/duo.md`: custom overlays "stay out of `foldFrame`"; HIG
/// Designing for iPhone Duo: "use reserved-region APIs to keep important elements
/// clear of the center").
enum FoldAvoidingPlacement {
    /// Smallest side of the fold worth centring in; a narrower side keeps the whole
    /// container (moving only what's necessary).
    static let minimumRegion: CGFloat = 160

    /// The rectangle, in the container's own coordinates, to centre content in.
    ///
    /// - Parameters:
    ///   - container: The container's frame in window coordinates.
    ///   - fold: The book-pose hinge (``DeviceLayout/splitHinge``) in window coordinates, or nil.
    /// - Returns: The whole container when there is no fold crossing it; otherwise the
    ///   larger side of the fold (leading or top on a tie), unless that side is
    ///   smaller than ``minimumRegion``.
    static func region(container: CGRect, fold: CGRect?) -> CGRect {
        let whole = CGRect(origin: .zero, size: container.size)
        guard let fold else { return whole }
        if fold.height > fold.width {
            // Vertical fold (book pose): pick the wider side.
            let leading = fold.minX - container.minX
            let trailing = container.maxX - fold.maxX
            guard leading > 0, trailing > 0,
                  fold.maxY > container.minY, fold.minY < container.maxY else { return whole }
            let width = max(leading, trailing)
            guard width >= minimumRegion else { return whole }
            let x = leading >= trailing ? 0 : container.width - trailing
            return CGRect(x: x, y: 0, width: width, height: container.height)
        } else {
            // Horizontal fold (laptop pose): pick the taller side.
            let above = fold.minY - container.minY
            let below = container.maxY - fold.maxY
            guard above > 0, below > 0,
                  fold.maxX > container.minX, fold.minX < container.maxX else { return whole }
            let height = max(above, below)
            guard height >= minimumRegion else { return whole }
            let y = above >= below ? 0 : container.height - below
            return CGRect(x: 0, y: y, width: container.width, height: height)
        }
    }
}
