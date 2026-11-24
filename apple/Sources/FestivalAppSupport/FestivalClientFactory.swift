import FestivalCore
import Foundation

package enum FestivalClientFactory {
    /// Use the public HTTPS service unless Debug explicitly selects a fixture.
    ///
    /// - Parameter environment: Launch environment containing optional debug fixture choices.
    /// - Returns: One keyless publication-aware client for the selected origin.
    /// - Throws: Invalid service URLs, unsupported fixture scenarios or insecure origins.
    package static func makeClient(environment: [String: String]) throws -> FestivalAPI {
        #if DEBUG
        let address = environment["FST_API_BASE_URL"] ?? "https://festivalscoretracker.com"
        #else
        let address = "https://festivalscoretracker.com"
        #endif
        guard let url = URL(string: address) else {
            throw FestivalAPIError.invalidResource
        }
        #if DEBUG
        let scenario: FixtureScenario?
        if let raw = environment["FST_FIXTURE_SCENARIO"] {
            guard let parsed = FixtureScenario(rawValue: raw) else {
                throw FestivalAPIError.invalidResource
            }
            scenario = parsed
        } else {
            scenario = nil
        }
        // FST_DEBUG_FORCE_FREEZE=1: answer each API path's first read with a
        // synthetic scrape-freeze 503 so the "Scores are updating" state can be captured.
        if environment["FST_DEBUG_FORCE_FREEZE"] == "1" {
            return try FestivalAPI(
                baseURL: url, fixtureScenario: scenario,
                transport: ForcedFreezeTransport(wrapping: URLSessionHTTPTransport())
            )
        }
        return try FestivalAPI(baseURL: url, fixtureScenario: scenario)
        #else
        return try FestivalAPI(baseURL: url)
        #endif
    }
}
