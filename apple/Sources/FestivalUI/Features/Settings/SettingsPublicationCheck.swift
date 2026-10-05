import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Summary

/// Publication checks must disclose whether the associated Songs read was stale or unpinned.
enum SettingsServiceSummary {
    /// Present a validated bootstrap without inventing response provenance.
    ///
    /// - Parameter payload: Typed Songs result from the same publication check.
    /// - Returns: Visible success, stale-memory, or unverified-live explanation.
    static func message(for payload: CatalogPayload) -> String {
        let prefix = "Publication \(payload.observedPublicationId)"
        if payload.isStale {
            return payload.publicationId == nil
                ? "\(prefix); songs offline - last seen (publication unverified)"
                : "\(prefix); songs offline - showing verified cached data"
        }
        return payload.publicationId == nil
            ? "\(prefix); songs live (publication unverified)"
            : prefix
    }
}

// MARK: - Check

/// Forces a publication + catalogue re-read and describes the outcome.
///
/// The web Settings page has no such control, so it is **not** shown to people (operator
/// batch 6, item 6.15). It survives only as a fixture-test helper: Songs journeys use it to
/// make the app observe a fixture server's publication change on demand (see
/// ``SettingsFixtureTools``).
enum SettingsPublicationCheck {
    /// Show publication state, or an explicit failure, without a privileged key.
    ///
    /// - Parameter session: Shared session whose publication and catalogue are refreshed.
    /// - Returns: Status text, or nil when the check was cancelled.
    @MainActor
    static func run(session: FestivalSession) async -> String? {
        do {
            let publication = try await session.refreshPublication()
            do {
                let catalog = try await session.catalog()
                try Task.checkCancellation()
                return SettingsServiceSummary.message(for: catalog)
            } catch is CancellationError {
                return nil
            } catch let error as URLError where error.code == .cancelled {
                return nil
            } catch {
                return "Publication \(publication.publicationId); songs update failed: "
                    + error.localizedDescription
            }
        } catch is CancellationError {
            return nil
        } catch let error as URLError where error.code == .cancelled {
            return nil
        } catch {
            return "Publication unavailable: \(error.localizedDescription)"
        }
    }
}

// MARK: - Fixture tools

/// Debug-only Settings rows that exist solely for fixture-backed UI tests.
///
/// They render only in Debug builds **and** only when `FST_API_BASE_URL` selects a loopback
/// fixture server, so neither Release nor a Debug build on the live service ever shows them.
enum SettingsFixtureTools {
    /// Whether fixture-only rows should render for this launch.
    ///
    /// - Parameter environment: Launch environment (injectable for tests).
    /// - Returns: True in Debug when the service origin is a loopback fixture server.
    static func isEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        #if DEBUG
        guard let raw = environment["FST_API_BASE_URL"], let host = URL(string: raw)?.host else {
            return false
        }
        return ["localhost", "127.0.0.1", "::1"].contains(host)
        #else
        false
        #endif
    }
}

/// The fixture-only "Check Publication" card (label and status identifier unchanged so the
/// existing Songs journeys keep working).
struct SettingsFixtureToolsSection: View {
    let session: FestivalSession
    @State private var status: String?

    var body: some View {
        FestivalGlassSection("Fixture Tools", subtitle: "Debug fixture runs only.") {
            VStack(alignment: .leading, spacing: 4) {
                Button("Check Publication") {
                    Task { status = await SettingsPublicationCheck.run(session: session) ?? status }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // The accent tint rendered 3.6:1 as text on the card (iPad audit).
                .tint(AccentText.blue)
                if let status {
                    Text(status)
                        .font(.subheadline)
                        .foregroundStyle(FestivalText.primary)
                        .accessibilityIdentifier("fst.settings.publication-status")
                }
            }
        }
    }
}
