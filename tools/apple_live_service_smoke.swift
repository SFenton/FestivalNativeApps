import Darwin
import Foundation
import FestivalCore

/// Bounded, keyless production reads through the same Swift client as the native apps.
@main
struct LiveServiceSmoke {
    /// Validate one publication, the Songs catalogue and one Lead chart without logging content.
    static func main() async {
        guard Array(CommandLine.arguments.dropFirst()) == ["--read-public-live"] else {
            fputs("Usage: apple_live_service_smoke --read-public-live\n", stderr)
            exit(2)
        }
        do {
            let client = try FestivalAPI()
            let publication = try await client.publication()
            let songs = try await client.catalog()
            guard let firstLead = songs.catalog.songs.first(where: { $0.supports(.lead) }) else {
                throw FestivalAPIError.invalidCatalogue
            }
            let chart = try await client.leaderboard(
                songId: firstLead.songId, instrument: .lead, page: 1
            )
            print("Public publication validated: contract \(publication.contractVersion)")
            print("Decoded live songs: \(songs.catalog.count)")
            print("Decoded live Lead rows: \(chart.leaderboard.entries.count)")
            print("Songs response provenance verified: \(songs.publicationId != nil)")
            print("Score response provenance verified: \(chart.publicationId != nil)")
        } catch {
            fputs("Public Swift client smoke failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
