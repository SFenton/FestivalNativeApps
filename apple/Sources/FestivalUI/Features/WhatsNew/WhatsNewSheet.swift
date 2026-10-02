import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Sheet

/// The native "What's New" changelog, ported from the web's `ChangelogModal`
/// (`components/modals/ChangelogModal.tsx`): a titled, scrolling list of sections with bullet
/// items and a full-width Dismiss button.
///
/// Presentation (operator, 2026-09-28): the launch presentation is a full-height cover on
/// iPhone (`whatsNewPresentation(isPresented:)`), so no rounded sheet corner exposes the page
/// behind it, and the background is opaque. Dismiss sits in an opaque bottom bar
/// (`safeAreaInset(.bottom)` over `cardBackground` with a hairline), so the list scrolls
/// **above** it and never shows beneath it. Close is the shared ``FestivalModal``'s system Close, top-right (issue #23).
/// A full-screen cover has no system swipe-to-dismiss, so pulling the list down past its top
/// and letting go dismisses it too (operator batch 6, item 6.14; iOS 18+).
struct WhatsNewSheet: View {
    /// App version shown after the title, like the web's `What's New · 0.1.133`.
    let version: String
    /// Entries to render (already filtered by `Changelog.displayEntries`).
    let entries: [ChangelogEntry]
    /// Called once when the user closes the sheet via Dismiss or Close.
    let onDismiss: () -> Void

    var body: some View {
        FestivalModal(
            Self.title(version: version), closeIdentifier: "fst.whats-new.close", onClose: onDismiss
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        ForEach(entry.sections) { section in
                            WhatsNewSectionView(section: section)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .modifier(PullDownToDismiss(action: onDismiss))
            .safeAreaInset(edge: .bottom, spacing: 0) { dismissBar }
            .background(BrandTokens.cardBackground)
            #if os(iOS)
            .toolbarBackground(BrandTokens.cardBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            #endif
        }
        .festivalSheet(.large)
        // Opaque, so neither the page behind nor a rounded sheet corner shows through.
        .presentationBackground(BrandTokens.cardBackground)
    }

    /// Opaque bottom bar holding Dismiss; the scroll view ends above it.
    private var dismissBar: some View {
        Button(action: onDismiss) {
            Text("Dismiss")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(BrandTokens.accentBlue)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            BrandTokens.cardBackground
                .overlay(alignment: .top) {
                    Rectangle().fill(BrandTokens.glassBorder).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
        .accessibilityIdentifier("fst.whats-new.dismiss")
    }

    /// Sheet title, e.g. "What's New · 1.0".
    ///
    /// - Parameter version: App version; omitted when empty.
    /// - Returns: Title text.
    static func title(version: String) -> String {
        version.isEmpty ? "What's New" : "What's New · \(version)"
    }
}

// MARK: - Pull down to dismiss

/// Dismiss when a scroll view is pulled down past its top by ``threshold`` points and
/// released, standing in for the swipe-down a sheet gets for free.
///
/// Uses iOS/macOS 18 scroll geometry and phase observation; a no-op before that, where Close
/// and Dismiss remain.
struct PullDownToDismiss: ViewModifier {
    /// Overscroll distance that counts as a deliberate pull.
    static let threshold: CGFloat = 80

    let action: () -> Void
    @State private var maxPull: CGFloat = 0
    @State private var fired = false

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    -(geometry.contentOffset.y + geometry.contentInsets.top)
                } action: { _, pull in
                    maxPull = max(maxPull, pull)
                }
                .onScrollPhaseChange { oldPhase, newPhase in
                    if newPhase == .interacting {
                        maxPull = 0
                    } else if oldPhase == .interacting {
                        if Self.shouldDismiss(pull: maxPull), !fired {
                            fired = true
                            action()
                        }
                        maxPull = 0
                    }
                }
        } else {
            content
        }
    }

    /// Whether a released pull dismisses.
    ///
    /// - Parameter pull: Largest overscroll above the top during the drag, in points.
    /// - Returns: True at or past ``threshold``.
    static func shouldDismiss(pull: CGFloat) -> Bool {
        pull >= threshold
    }
}

// MARK: - Section

/// One Title Case heading with its bullet list.
private struct WhatsNewSectionView: View {
    let section: ChangelogSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.displayTitle)
                .font(.headline)
                .foregroundStyle(FestivalText.primary)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                        .foregroundStyle(FestivalText.primary)
                        .accessibilityHidden(true)
                    Text(item)
                        .font(.subheadline)
                        .foregroundStyle(FestivalText.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

// MARK: - Presentation

extension View {
    /// Present What's New full height: a cover on iPhone (no rounded sheet corners over
    /// the page), a large sheet elsewhere.
    ///
    /// - Parameters:
    ///   - isPresented: Presentation binding.
    ///   - onDismiss: Runs after the presentation closes.
    ///   - content: The `WhatsNewSheet`.
    /// - Returns: The view with the presentation attached.
    func whatsNewPresentation<Content: View>(
        isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #else
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #endif
    }
}
