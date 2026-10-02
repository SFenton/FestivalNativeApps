import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Carousel

/// The native first-run carousel: a paged, dark Liquid Glass sheet ported from the web's
/// `FirstRunCarousel` (`components/firstRun/FirstRunCarousel.tsx`).
///
/// Operator batch 6 (item 6.7) / batch 7: the primary **Next/Done** comes first (a
/// full-width glass-prominent button, the HIG onboarding pattern) with glass **Back** (once
/// there is a page to go back to) and **Skip** (while pages remain) beneath it; a one-page
/// guide shows only Done; no arrows; white page dots; a native toolbar **Close** top-right
/// (the same `.confirmationAction` button as the Profile search sheet, issue #4). Close,
/// swiping down and tapping outside the sheet all dismiss, and only the pages actually
/// shown are recorded in `viewing` (see ``FirstRunViewing``).
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
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $index) {
                    ForEach(Array(slides.enumerated()), id: \.element.id) { position, slide in
                        FirstRunSlideView(page: page, slide: slide)
                            // Every page is mounted; only the visible one rotates its demo.
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            #endif
            .toolbar {
                // Same native control as the Profile search sheet (issue #4): a trailing
                // `.confirmationAction` "Close", the blue glass button on iOS 26.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close", action: onFinish)
                        .accessibilityIdentifier("fst.first-run.close")
                }
            }
        }
        .modifier(FirstRunSheetStyle())
        .onChange(of: index) { _, newValue in
            viewing.view(newValue, of: slides)
            focusedSlide = newValue
        }
        .onAppear {
            viewing.view(index, of: slides)
            focusedSlide = index
        }
    }

    private var pageAnimation: Animation? { reduceMotion ? nil : .easeInOut }

    private var controls: some View {
        let state = FirstRunControls.forPage(index, of: slides.count)
        return VStack(spacing: 10) {
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
                    .padding(.vertical, 4)
            }
            .modifier(FirstRunGlassButton(prominent: true))
            .accessibilityIdentifier(state.primaryFinishes ? "fst.first-run.done" : "fst.first-run.next")
            if slides.count > 1 {
                // Back and Skip sit beneath the primary action; the row keeps its height so
                // Next never jumps, and an absent button is not drawn or exposed.
                HStack {
                    if state.showsBack {
                        Button("Back") {
                            withAnimation(pageAnimation) { index = max(0, index - 1) }
                        }
                        .modifier(FirstRunGlassButton(prominent: false))
                        .accessibilityIdentifier("fst.first-run.back")
                    }
                    Spacer(minLength: 0)
                    if state.showsSkip {
                        Button("Skip", action: onFinish)
                            .modifier(FirstRunGlassButton(prominent: false))
                            .accessibilityIdentifier("fst.first-run.skip")
                    }
                }
                .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }
}

// MARK: - Glass buttons

/// Native Liquid Glass buttons on iOS 26 (`.glassProminent` in the brand blue for the
/// primary action, `.glass` for Back/Skip); bordered equivalents before it.
private struct FirstRunGlassButton: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent).tint(BrandTokens.accentBlue)
            } else {
                content.buttonStyle(.glass).foregroundStyle(FestivalText.primary)
                    .font(.body.weight(.semibold))
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent).tint(BrandTokens.accentBlue)
        } else {
            content.buttonStyle(.bordered).foregroundStyle(FestivalText.primary)
                .font(.body.weight(.semibold))
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
                Text(slide.description)
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
        .accessibilityLabel("\(slide.title). \(slide.description)")
    }
}
