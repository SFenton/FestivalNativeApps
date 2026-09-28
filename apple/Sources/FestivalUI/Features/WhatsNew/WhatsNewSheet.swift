import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Sheet

/// The native "What's New" changelog, ported from the web's `ChangelogModal`
/// (`components/modals/ChangelogModal.tsx`): a titled, scrolling list of sections with bullet
/// items and a full-width Dismiss button.
///
/// Native deviations (HIG over the web card): a system sheet with a drag indicator instead of a
/// centred card, Title Case section headings instead of CSS upper-casing, and a toolbar close
/// button in the standard trailing position.
struct WhatsNewSheet: View {
    /// App version shown after the title, like the web's `What's New · 0.1.133`.
    let version: String
    /// Entries to render (already filtered by `Changelog.displayEntries`).
    let entries: [ChangelogEntry]
    /// Called once when the user closes the sheet via Dismiss or Close.
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
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
            .safeAreaInset(edge: .bottom) { dismissButton }
            .navigationTitle(Self.title(version: version))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                    .accessibilityIdentifier("fst.whats-new.close")
                }
            }
        }
        .festivalSheet(.large)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Text("Dismiss")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(BrandTokens.accentBlue)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
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
