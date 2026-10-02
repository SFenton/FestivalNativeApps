import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Carousel

/// The native first-run carousel: a paged, dark Liquid Glass sheet ported from the web's
/// `FirstRunCarousel` (`components/firstRun/FirstRunCarousel.tsx`).
///
/// Controls follow Apple's onboarding layout (issue #25, which reworked operator batches 6–7):
/// **Back** at the leading edge of the navigation bar from the second page on, the page
/// title, and the system toolbar **Close** at the trailing edge from the shared
/// ``FestivalModal`` (issue #23). The title names the page the guide explains (issue #24,
/// ``FirstRunPageKey/guideTitle``), and VoiceOver reads it first when the sheet opens. At the
/// bottom there is one large glass-prominent **Next/Done** with a quiet full-width **Skip**
/// beneath it while pages remain. A one-page guide shows only Done. There are no arrows, and
/// the page dots are white. Every control's hit region is at least 44×44 pt. Close, swiping
/// down and tapping outside the sheet all dismiss, and only the pages actually shown are
/// recorded in `viewing` (see ``FirstRunViewing``).
///
/// Used both for a page's own onboarding (`.firstRun(page:session:)`) and for a Settings
/// replay — both supply a different `slides` array and `onFinish` closure.
struct FirstRunCarouselView: View {
    let page: FirstRunPageKey
    let slides: [FirstRunSlide]
    /// Pages shown so far; the presenter marks only these seen when the sheet closes.
    @Binding var viewing: FirstRunViewing
    /// Called once, when the user closes via Done or the close button. The caller closes the
    /// presentation; marking seen happens in the presenter's `onDismiss`, so a swipe or an
    /// outside tap is handled identically.
    let onFinish: () -> Void

    @State private var index = 0
    @AccessibilityFocusState private var focusedSlide: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // The shared modal: an inline page title (issue #24) and the system Close top-right
        // (issue #23), not a text button.
        FestivalModal(page.guideTitle, closeIdentifier: "fst.first-run.close", onClose: onFinish) {
            VStack(spacing: 0) {
                TabView(selection: $index) {
                    ForEach(Array(slides.enumerated()), id: \.element.id) { position, slide in
                        FirstRunSlideView(page: page, slide: slide)
                            // Every page is mounted; only the visible one pulses (#28) and
                            // rotates its demo.
                            .environment(\.firstRunSlideActive, position == index)
                            .environment(\.firstRunDemoActive, position == index && scenePhase == .active)
                            .accessibilityFocused($focusedSlide, equals: position)
                            .tag(position)
                    }
                }
                .modifier(FirstRunPageTabStyle())
                if slides.count > 1 {
                    FirstRunPageDots(count: slides.count, index: $index, animation: pageAnimation)
                        .padding(.top, 8)
                }
                controls
            }
            .toolbar { backItem }
            #if os(iOS)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
        }
        .modifier(FirstRunSheetStyle())
        .onChange(of: index) { _, newValue in
            viewing.view(newValue, of: slides)
            focusedSlide = newValue
        }
        .onAppear {
            // VoiceOver focus is left to the system on open so the navigation title is
            // announced first (HIG VoiceOver); it follows the slide only on a page change.
            viewing.view(index, of: slides)
        }
    }

    private var pageAnimation: Animation? { reduceMotion ? nil : .easeInOut }

    private var state: FirstRunControls { FirstRunControls.forPage(index, of: slides.count) }

    private func goBack() {
        withAnimation(pageAnimation) { index = max(0, index - 1) }
    }

    /// Back in the guide's navigation bar, before the page title (issue #25; HIG Toolbars:
    /// "Leading: back/previous-document and sidebar controls, then the view title"). Absent
    /// on the first page rather than shown disabled.
    @ToolbarContentBuilder
    private var backItem: some ToolbarContent {
        if state.showsBack {
            ToolbarItem(placement: Self.backPlacement) {
                Button(action: goBack) {
                    Label("Back", systemImage: "chevron.backward")
                }
                .accessibilityIdentifier("fst.first-run.back")
            }
        }
    }

    private static var backPlacement: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    /// The bottom actions, Apple's onboarding layout (issue #25): one large prominent
    /// Next/Done (the large control size is about 50 pt tall), then a quiet full-width Skip
    /// beneath it while pages remain, at least 48 pt tall. Both hit regions stay at least
    /// 44 pt even though iOS 26 draws the partial-height sheet slightly scaled down.
    private var controls: some View {
        let state = state
        return VStack(spacing: 4) {
            Button {
                if state.primaryFinishes {
                    onFinish()
                } else {
                    withAnimation(pageAnimation) { index += 1 }
                }
            } label: {
                Text(state.primaryTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .modifier(FirstRunPrimaryButton())
            .accessibilityIdentifier(state.primaryFinishes ? "fst.first-run.done" : "fst.first-run.next")
            if state.reservesSkipRow {
                // The row keeps its height on the last page so Done never jumps; an absent
                // Skip is neither drawn nor exposed.
                ZStack {
                    if state.showsSkip {
                        Button(action: onFinish) {
                            Text("Skip")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(FestivalText.primary)
                                .frame(maxWidth: .infinity, minHeight: FirstRunControls.minimumHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("fst.first-run.skip")
                    }
                }
                .frame(minHeight: FirstRunControls.minimumHeight)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
    }
}

// MARK: - Primary button

/// The native Liquid Glass prominent button on iOS 26 in the brand blue; bordered
/// prominent before it.
private struct FirstRunPrimaryButton: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            content.buttonStyle(.glassProminent).tint(BrandTokens.accentBlue)
        } else {
            content.buttonStyle(.borderedProminent).tint(BrandTokens.accentBlue)
        }
    }
}

// MARK: - Page dots

/// White page dots (operator batch 6): the current page solid white, others translucent
/// white. One adjustable VoiceOver element announcing "Page x of y"; tapping a dot jumps to
/// that page.
private struct FirstRunPageDots: View {
    let count: Int
    @Binding var index: Int
    let animation: Animation?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { position in
                Circle()
                    .fill(Color.white.opacity(position == index ? 1 : 0.35))
                    .frame(width: 8, height: 8)
                    .frame(width: 20, height: 24)
                    .contentShape(Rectangle())
                    .onTapGesture { withAnimation(animation) { index = position } }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page")
        .accessibilityValue("\(index + 1) of \(count)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: index = min(count - 1, index + 1)
            case .decrement: index = max(0, index - 1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("fst.first-run.dots")
    }
}

// MARK: - Sheet style

/// A shorter-than-full sheet so there is dimmed page above it to tap: tapping outside or
/// swiping down dismisses (operator batch 6), like the web's overlay click. Dark glass on
/// iOS 26, frosted navy before it, opaque navy for accessibility overrides — the same
/// surfaces as `festivalSheet`.
private struct FirstRunSheetStyle: ViewModifier {
    /// Fraction of the screen height the carousel covers.
    static let heightFraction: CGFloat = 0.86

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("fst.accessibility.lessTransparency") private var lessTransparency = false
    @AppStorage("fst.accessibility.moreContrast") private var moreContrast = false

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .presentationDetents([.fraction(Self.heightFraction)])
            .presentationDragIndicator(.visible)
            .modifier(background)
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue)
            .pausesFestivalBackdrop()
    }

    private var background: FirstRunSheetBackground {
        FirstRunSheetBackground(opaque: reduceTransparency || lessTransparency || moreContrast)
    }
}

private struct FirstRunSheetBackground: ViewModifier {
    let opaque: Bool

    func body(content: Content) -> some View {
        if opaque {
            content.presentationBackground(BrandTokens.cardBackground)
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content
        } else {
            content.presentationBackground {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    BrandTokens.cardBackground.opacity(0.62)
                }
            }
        }
    }
}

// MARK: - Platform tab style

/// `.page(indexDisplayMode:)` is iOS/tvOS/watchOS-only; this app also compiles for macOS
/// (`Package.swift` lists `.macOS(.v14)` so `swift test` can run on the host Mac), where the
/// default `TabView` style is used instead. The system index dots are hidden: the carousel
/// draws its own white ``FirstRunPageDots``.
private struct FirstRunPageTabStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.tabViewStyle(.page(indexDisplayMode: .never))
        #else
        content
        #endif
    }
}

// MARK: - One slide

/// One slide's demo, title and description as a single VoiceOver element; position is
/// announced by the page-dots element.
private struct FirstRunSlideView: View {
    let page: FirstRunPageKey
    let slide: FirstRunSlide

    var body: some View {
        VStack(spacing: 20) {
            // Demos vary (a 5-row leaderboard is ~260 pt); give them room below the
            // toolbar's Close and clip so nothing ever draws over the sheet chrome.
            FirstRunDemoContent(page: page, slide: slide)
                .frame(maxWidth: .infinity, minHeight: 170, idealHeight: 260, maxHeight: 320)
                .clipped()
                .padding(.horizontal, 20)
            VStack(spacing: 8) {
                Text(slide.title)
                    .font(.title2.bold())
                    .foregroundStyle(FestivalText.primary)
                    .multilineTextAlignment(.center)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(FestivalText.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 0)
        }
        .padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slide.title). \(description)")
    }

    /// The slide's description in this platform's words (``FirstRunCopy``).
    private var description: String {
        #if os(macOS)
        FirstRunCopy.mac(slide.description)
        #else
        slide.description
        #endif
    }
}

// MARK: - Platform copy

/// First-run copy comes from the web catalogue, written for touch. On the Mac it says
/// "click" and names the sidebar (HIG Writing: "make sure you describe gestures
/// correctly ("tap", not "click", on iPhone or iPad)").
enum FirstRunCopy {
    /// The Mac wording of a slide description.
    ///
    /// - Parameter text: Catalogue text.
    /// - Returns: "Tap"/"tap" as "Click"/"click", and the bottom tabs as the sidebar.
    static func mac(_ text: String) -> String {
        text
            .replacingOccurrences(of: "Use the bottom tabs", with: "Use the sidebar")
            .replacingOccurrences(of: "Tap ", with: "Click ")
            .replacingOccurrences(of: " tap ", with: " click ")
    }
}
