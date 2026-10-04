import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Empty state

/// Global search's empty state (issue #99): a magnifier, a title, a subtitle and, when
/// players were searched, Retry, centred horizontally and vertically below the scope
/// bar like the Songs page's own empty state and the web's centred search hint.
///
/// Built from scalable text in a scroll view rather than `ContentUnavailableView`
/// (which failed iOS 26.5 Dynamic Type audits, see ``ServiceStatusView``), so the copy
/// wraps at every text size and scrolls when it cannot fit. VoiceOver reads it as one
/// element, "title. subtitle Retry", whose activation retries (HIG Writing: "Provide
/// clear next steps on any blank screens, with a button or link if possible").
/// On a partially folded iPhone Duo it centres beside the fold, never on it.
struct GlobalSearchEmptyStateView: View {
    let state: GlobalSearch.EmptyState
    /// Searches again; shown only when ``GlobalSearch/EmptyState/offersRetry``.
    let retry: () -> Void
    @Environment(\.deviceLayout) private var layout

    var body: some View {
        GeometryReader { proxy in
            let region = FoldAvoidingPlacement.region(
                container: proxy.frame(in: .global), fold: layout.foldFrame
            )
            ScrollView {
                content
                    .padding(24)
                    .frame(width: region.width)
                    .frame(minHeight: region.height)
                    .padding(.leading, region.minX)
                    .padding(.top, region.minY)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private var content: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.largeTitle)
                .foregroundStyle(FestivalText.primary)
                .accessibilityHidden(true)
            Text(state.title)
                .font(.title2.bold())
                .foregroundStyle(BrandTokens.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(state.subtitle)
                .font(.body)
                .foregroundStyle(FestivalText.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if state.offersRetry {
                Button(action: retry) {
                    Text("Retry")
                        .font(.body)
                        .foregroundStyle(BrandTokens.textPrimary)
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.horizontal, 12)
                        .background(BrandTokens.cardBackground, in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
        .modifier(EmptyStateRetryAction(offersRetry: state.offersRetry, retry: retry))
    }
}

/// Accessibility traits, action and identifier for the combined empty-state element:
/// a button that retries when players were searched, otherwise static text.
private struct EmptyStateRetryAction: ViewModifier {
    let offersRetry: Bool
    let retry: () -> Void

    func body(content: Content) -> some View {
        if offersRetry {
            content
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { retry() }
                .accessibilityInputLabels([Text("Retry")])
                .accessibilityIdentifier("fst.global-search.retry")
        } else {
            content
                .accessibilityAddTraits(.isStaticText)
                .accessibilityIdentifier("fst.global-search.hint")
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
    ///   - fold: The active fold division in window coordinates, or nil.
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
