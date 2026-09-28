import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - LicensesScreen

/// `/settings/licenses` — the native form of `LicensesPage.tsx:27-77`.
///
/// Lists this app's actual dependencies rather than importing the web's npm/NuGet
/// manifest (see `LicenseManifest.swift`). A tapped row opens its full license text in a
/// sheet; dismissing the sheet returns focus to that row, matching the web's modal.
struct LicensesScreen: View {
    let session: FestivalSession
    @State private var selected: SoftwareLicense?

    /// Create the screen.
    ///
    /// - Parameter session: Shared app session (used only for the animated backdrop).
    init(session: FestivalSession) {
        self.session = session
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                FestivalGlassSection(
                    "Third-Party Software",
                    subtitle: "Open source packages bundled in this build."
                ) {
                    if LicenseManifest.thirdPartySoftware.isEmpty {
                        FestivalFootnote(
                            "This build has no external Swift package dependencies — "
                                + "every module (FestivalCore, FestivalDesign, FestivalUI) "
                                + "is first-party. This list updates the day one is added."
                        )
                    } else {
                        ForEach(LicenseManifest.thirdPartySoftware) { entry in
                            licenseRow(entry)
                        }
                    }
                }
                FestivalGlassSection(
                    "Bundled Assets",
                    subtitle: "Non-code resources shipped with this app."
                ) {
                    ForEach(LicenseManifest.bundledAssets) { entry in
                        licenseRow(entry)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .festivalBackground(.carousel, session: session)
        .navigationTitle("Licenses")
        .sheet(item: $selected) { entry in
            LicenseDetailSheet(entry: entry)
        }
    }

    private func licenseRow(_ entry: SoftwareLicense) -> some View {
        Button {
            selected = entry
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .foregroundStyle(BrandTokens.textPrimary)
                    Text(entry.versionOrRole)
                        .font(.footnote)
                        .foregroundStyle(BrandTokens.textSecondary)
                }
                Spacer(minLength: 8)
                Text(entry.licenseType)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrandTokens.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(BrandTokens.surfaceFrosted, in: Capsule())
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BrandTokens.textMuted)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.name), \(entry.versionOrRole), \(entry.licenseType)")
        .accessibilityIdentifier("fst.licenses.\(entry.id)")
    }
}

// MARK: - License detail

/// Full license text for one entry, presented as a dismissible sheet.
private struct LicenseDetailSheet: View {
    let entry: SoftwareLicense
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let url = entry.url {
                        Link(url.absoluteString, destination: url)
                            .font(.footnote)
                    }
                    Text(entry.licenseText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(BrandTokens.textSecondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .navigationTitle("\(entry.name) · \(entry.licenseType)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .festivalSheet(.large)
    }
}
