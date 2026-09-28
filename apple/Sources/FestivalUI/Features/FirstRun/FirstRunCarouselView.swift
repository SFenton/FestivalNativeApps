import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Carousel

/// The native first-run carousel: a paged, dark Liquid Glass sheet with Skip/Next/Done controls,
/// ported from the web's `FirstRunCarousel` (`components/firstRun/FirstRunCarousel.tsx`).
///
/// Used both for a page's own onboarding (`.firstRun(page:session:)`) and for a Settings
/// "view again" replay — both simply supply a different `slides` array and `onFinish` closure.
struct FirstRunCarouselView: View {
    let page: FirstRunPageKey
    let slides: [FirstRunSlide]
    /// Called once, when the user dismisses via Skip, Done, or the close button. The caller is
    /// responsible for marking `slides` seen and closing the presentation.
    let onFinish: () -> Void

    @State private var index = 0
    @AccessibilityFocusState private var focusedSlide: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            closeRow
            TabView(selection: $index) {
                ForEach(Array(slides.enumerated()), id: \.element.id) { position, slide in
                    FirstRunSlideView(
                        page: page, slide: slide, index: position, total: slides.count
                    )
                    .accessibilityFocused($focusedSlide, equals: position)
                    .tag(position)
                }
            }
            .modifier(FirstRunPageTabStyle())
            controls
        }
        .festivalSheet(.large)
        .onChange(of: index) { _, newValue in
            focusedSlide = newValue
        }
        .onAppear { focusedSlide = index }
    }

    private var closeRow: some View {
        HStack {
            Spacer()
            Button(action: onFinish) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(BrandTokens.textSecondary)
            }
            .accessibilityLabel("Close")
            .accessibilityIdentifier("fst.first-run.close")
        }
        .padding(.top, 16)
        .padding(.trailing, 16)
    }

    private var isLastSlide: Bool { index >= slides.count - 1 }

    private var controls: some View {
        HStack {
            Button("Skip", action: onFinish)
                .foregroundStyle(BrandTokens.textSecondary)
                .opacity(isLastSlide ? 0 : 1)
                .disabled(isLastSlide)
                .accessibilityHidden(isLastSlide)
                .accessibilityIdentifier("fst.first-run.skip")
            Spacer()
            Button(isLastSlide ? "Done" : "Next") {
                if isLastSlide {
                    onFinish()
                } else {
                    withAnimation(reduceMotion ? nil : .easeInOut) { index += 1 }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(BrandTokens.accentBlue)
            .accessibilityIdentifier(isLastSlide ? "fst.first-run.done" : "fst.first-run.next")
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 24)
    }
}

// MARK: - Platform tab style

/// `.page(indexDisplayMode:)` is iOS/tvOS/watchOS-only; this app also compiles for macOS
/// (`Package.swift` lists `.macOS(.v14)` so `swift test` can run on the host Mac), where the
/// default `TabView` style is used instead. macOS never actually presents this carousel today
/// (Apple execution order ports iPhone first), so this is purely a compile-time accommodation.
private struct FirstRunPageTabStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
        content.tabViewStyle(.page(indexDisplayMode: .always))
        #else
        content
        #endif
    }
}

// MARK: - One slide

/// One slide's demo, title and description, with a combined VoiceOver announcement of
/// "Slide x of y" matching the requirement to announce position on every page change.
private struct FirstRunSlideView: View {
    let page: FirstRunPageKey
    let slide: FirstRunSlide
    let index: Int
    let total: Int

    var body: some View {
        VStack(spacing: 20) {
            // Demos vary (a 5-row leaderboard is ~260 pt); give them room below the close
            // button and clip so nothing ever draws over the sheet chrome.
            FirstRunDemoContent(page: page, slide: slide)
                .frame(maxWidth: .infinity, minHeight: 190, idealHeight: 260, maxHeight: 320)
                .clipped()
                .padding(.horizontal, 20)
            VStack(spacing: 8) {
                Text(slide.title)
                    .font(.title2.bold())
                    .foregroundStyle(BrandTokens.textPrimary)
                    .multilineTextAlignment(.center)
                Text(slide.description)
                    .font(.subheadline)
                    .foregroundStyle(BrandTokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)
            Spacer(minLength: 0)
        }
        .padding(.top, 52)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slide.title). \(slide.description)")
        .accessibilityValue("Slide \(index + 1) of \(total)")
    }
}
