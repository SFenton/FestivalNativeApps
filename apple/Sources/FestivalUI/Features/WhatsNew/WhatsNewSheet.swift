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
    /// Entries to render (already filtered by `Changelog.displayEntries`); nil while the install
    /// channel is still being detected, which shows a spinner rather than the wrong notes.
    let entries: [ChangelogEntry]?
    /// Called once when the user closes the sheet via Dismiss or Close.
    let onDismiss: () -> Void
    @Environment(\.deviceLayout) private var layout

    var body: some View {
        FestivalModal(
            Self.title(version: version), closeIdentifier: "fst.whats-new.close", onClose: onDismiss
        ) {
            ScrollView {
                if let entries {
                    VStack(alignment: .leading, spacing: 28) {
                        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                            WhatsNewEntryView(entry: entry)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                        .accessibilityLabel("Getting notes for this install")
                        .accessibilityIdentifier("fst.whats-new.pending")
                }
            }
            .modifier(PullDownToDismiss(action: onDismiss))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // `/duo` M1 (operator, 2026-10-02): with the iPhone Duo vertical bar the
                // sheet's Close sits in its own side bar, so the custom Dismiss bar would
                // be a second close control outside the managed bars; iPhone keeps it.
                if Self.showsDismissBar(layout) { dismissBar }
            }
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
        .tint(AccentText.prominentFill)
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

    /// Whether the bottom Dismiss bar shows (`/duo` M1).
    ///
    /// - Parameter layout: Current `\.deviceLayout`.
    /// - Returns: False while the section chrome is the iPhone Duo vertical bar.
    static func showsDismissBar(_ layout: DeviceLayout) -> Bool {
        !layout.sectionChrome.isVerticalBar
    }

    /// Sheet title, e.g. "What's New · 1.0".
    ///
    /// - Parameter version: App version; omitted when empty.
    /// - Returns: Title text.
    static func title(version: String) -> String {
        version.isEmpty ? "What's New" : "What's New · \(version)"
    }
}

// MARK: - Channel-aware sheet

/// ``WhatsNewSheet`` for this install: tester notes on TestFlight/development installs, release
/// notes on App Store installs, and a spinner while ``AppDistributionResolver`` is still pending
/// (never the App Store notes by default). Used by the launch presentation, Settings' replay
/// and the Mac command; a late StoreKit answer re-renders the list.
struct WhatsNewChannelSheet: View {
    /// App version shown after the title.
    let version: String
    /// Called once when the user closes the sheet.
    let onDismiss: () -> Void

    private var resolver: AppDistributionResolver { .shared }

    var body: some View {
        WhatsNewSheet(
            version: version,
            entries: resolver.channel.map { Changelog.displayEntries(distribution: $0) },
            onDismiss: onDismiss
        )
        .task { _ = await resolver.current() }
    }
}

// MARK: - Entry

/// One version's (or the tester list's) heading followed by its category sections.
private struct WhatsNewEntryView: View {
    let entry: ChangelogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let heading = entry.displayHeading {
                Text(heading)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FestivalText.primary)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(entry.sections) { section in
                WhatsNewSectionView(section: section)
            }
        }
    }
}

// MARK: - Section

/// One Title Case category heading (none for an unheaded list) with its bullet list.
private struct WhatsNewSectionView: View {
    let section: ChangelogSection

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !section.title.isEmpty {
                Text(section.displayTitle)
                    .font(.headline)
                    .foregroundStyle(FestivalText.primary)
                    .accessibilityAddTraits(.isHeader)
            }
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
    /// the page), a large sheet elsewhere. On the iPhone Duo inner display a centered
    /// sheet instead, like the app's other modals there (HIG iPhone Duo: inner sheets
    /// are centered with horizontal bars; a cover stretched the iPhone page over the
    /// whole open display).
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
        festivalModalPresentation(
            isPresented: isPresented, onDismiss: onDismiss,
            coverage: { WhatsNewPresentationStyle.usesSheet($0) ? .sheet : .fullScreen },
            content: content
        )
        #else
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
        #endif
    }
}

/// Which presentation What's New uses on iOS.
enum WhatsNewPresentationStyle {
    /// Whether to use a centered sheet: the iPhone Duo inner display (a hinged pose at
    /// regular width). iPhone, the folded Duo and iPad keep the full-screen cover.
    ///
    /// - Parameter layout: The window's published layout.
    /// - Returns: True on the Duo inner display.
    nonisolated static func usesSheet(_ layout: DeviceLayout) -> Bool {
        layout.pose != .standard && layout.windowWidthClass == .regular
    }
}
