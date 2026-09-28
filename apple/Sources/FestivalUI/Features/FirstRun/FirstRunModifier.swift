import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Page application

/// Shows a page's first-run carousel automatically, the single seam every page needs so its
/// onboarding "just works" without any per-screen FRE code — ported from the web calling
/// `useRegisterFirstRun` + `useFirstRun` inside each page component.
///
/// Apply once per page, at the tab-root or pushed-route level (`AppRouteDestination` and
/// `FestivalRootView` wrap their screens with this; see `.agents/controls/first-run/ios.md`).
struct FirstRunPageModifier: ViewModifier {
    let page: FirstRunPageKey
    let session: FestivalSession

    @AppStorage("fst.settings.hideShop") private var hideShop = false
    @AppStorage("fst.settings.disableShopHighlighting") private var disableShopHighlighting = false
    @AppStorage("fst.settings.experimentalRanks") private var experimentalRanks = false
    /// The presented carousel, carried as one value so the sheet never renders with a stale,
    /// empty slide list. `.sheet(isPresented:)` plus a separate `@State` array raced when a
    /// non-default tab was the launch tab (the sheet showed "page 1 of 0").
    @State private var presentation: FirstRunPresentation?
    /// Slides shown by the current/last presentation, marked seen on dismiss.
    @State private var shownSlides: [FirstRunSlide] = []

    func body(content: Content) -> some View {
        content
            .onAppear(perform: evaluate)
            .onChange(of: session.selectedPlayer) { _, _ in evaluate() }
            .onChange(of: hideShop) { _, _ in evaluate() }
            .onChange(of: disableShopHighlighting) { _, _ in evaluate() }
            .onChange(of: experimentalRanks) { _, _ in evaluate() }
            .onDisappear { center.release(page.rawValue) }
            .sheet(item: $presentation, onDismiss: finish) { shown in
                FirstRunCarouselView(page: page, slides: shown.slides) { presentation = nil }
            }
    }

    private var center: FirstRunCenter { session.firstRunCenter }

    /// Current gate facts. `ready` is always true: this app resolves the selected-player
    /// identity synchronously from storage at session start (`FestivalSession.init`), so there
    /// is no async gap during which gates could be evaluated against stale data.
    private var context: FirstRunGateContext {
        FirstRunGateContext(
            hasPlayer: session.selectedPlayer != nil,
            shopHighlightEnabled: !hideShop && !disableShopHighlighting,
            experimentalRanksEnabled: experimentalRanks,
            ready: true,
            alwaysShow: center.debugMode == .force
        )
    }

    /// Recompute which slides (if any) should show, and claim the shared "one carousel at a
    /// time" slot if so.
    private func evaluate() {
        guard center.debugMode != .off, presentation == nil else { return }
        let catalog = FirstRunCatalog.slides(for: page)
        let ctx = context
        let slides = ctx.alwaysShow
            ? FirstRunSlideEvaluator.gatePassingSlides(catalog, context: ctx)
            : FirstRunSlideEvaluator.unseenSlides(
                catalog, context: ctx, seen: center.store.load()
            )
        guard !slides.isEmpty, center.claim(page.rawValue) else { return }
        shownSlides = slides
        presentation = FirstRunPresentation(slides: slides)
    }

    /// The displayed slides are marked seen and the shared slot released exactly once, whether
    /// the sheet closed via Skip/Done or a swipe-to-dismiss.
    private func finish() {
        guard !shownSlides.isEmpty else { return }
        center.store.markSeen(shownSlides)
        center.release(page.rawValue)
        shownSlides = []
    }
}

/// One carousel presentation; a fresh identity per presentation.
struct FirstRunPresentation: Identifiable {
    let id = UUID()
    let slides: [FirstRunSlide]
}

extension View {
    /// Show `page`'s first-run carousel automatically when it has unseen, gate-passing slides.
    ///
    /// - Parameters:
    ///   - page: The page whose slide catalog to evaluate.
    ///   - session: Shared app session (selected player + first-run coordinator).
    /// - Returns: The content, with automatic first-run presentation attached.
    func firstRun(_ page: FirstRunPageKey, session: FestivalSession) -> some View {
        modifier(FirstRunPageModifier(page: page, session: session))
    }
}
