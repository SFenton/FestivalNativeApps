import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - LicensesScreen

/// `/settings/licenses` — the native form of `LicensesPage.tsx:27-77`.
///
/// Lists this app's actual third-party software rather than importing the web's npm/NuGet
/// manifest (see `LicenseManifest.swift`); no bundled-asset section (operator batch 6). One
/// card of rows, each with a chevron and a pressed highlight so it reads as tappable; a
/// tapped row opens its full license text in a sheet with a centred **Close**, and
/// dismissing the sheet returns focus to that row, matching the web's modal.
struct LicensesScreen: View {
    let session: FestivalSession
    let entries: [SoftwareLicense]
    @State private var selected: SoftwareLicense?
    @Environment(\.deviceLayout) private var layout

    /// Create the screen.
    ///
    /// - Parameters:
    ///   - session: Shared app session (used only for the animated backdrop).
    ///   - entries: Rows to list; the app's real manifest by default (hosted tests inject).
    init(session: FestivalSession, entries: [SoftwareLicense] = LicenseManifest.thirdPartySoftware) {
        self.session = session
        self.entries = entries
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                FestivalGlassSection(
                    "Third-Party Software",
                    subtitle: "Open source packages bundled in this build."
                ) {
                    if entries.isEmpty {
                        FestivalFootnote(
                            "This build has no external Swift package dependencies — "
                                + "every module (FestivalCore, FestivalDesign, FestivalUI) "
                                + "is first-party. This list updates the day one is added."
                        )
                        .accessibilityIdentifier("fst.licenses.empty")
                    } else {
                        ForEach(entries) { entry in
                            licenseRow(entry)
                        }
                    }
                }
                .festivalFadeIn(isLoaded: true, index: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
            // Same readable, centred column as Settings on wide windows.
            .modifier(ReadableWidthContainer(isRegularWidth: layout.widthClass == .regular))
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
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(FestivalText.primary)
                    Text(entry.versionOrRole)
                        .font(.footnote)
                        .foregroundStyle(FestivalText.primary)
                }
                Spacer(minLength: 8)
                Text(entry.licenseType)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FestivalText.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(BrandTokens.surfaceFrosted, in: Capsule())
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(FestivalText.primary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(LicenseRowButtonStyle())
        .accessibilityLabel("\(entry.name), \(entry.versionOrRole), \(entry.licenseType)")
        .accessibilityHint("Shows the full license text")
        .accessibilityIdentifier("fst.licenses.\(entry.id)")
    }
}

// MARK: - Row style

/// A pressed highlight behind a license row, so it visibly responds to touch.
struct LicenseRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.12 : 0))
                    .padding(-6)
            }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - License detail

/// Full license text for one entry, presented as a dismissible sheet with the shared
/// ``FestivalModal``'s system Close top-right (issue #23).
struct LicenseDetailSheet: View {
    let entry: SoftwareLicense

    var body: some View {
        FestivalModal(
            "\(entry.name) · \(entry.licenseType)", closeIdentifier: "fst.licenses.close"
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let url = entry.url {
                        Link(url.absoluteString, destination: url)
                            .font(.footnote)
                    }
                    Text(entry.licenseText)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(FestivalText.primary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        }
        .festivalSheet(.large)
    }
}
