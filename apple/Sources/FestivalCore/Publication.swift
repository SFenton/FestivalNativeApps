import Foundation

/// A public data surface that has not yet reached the published generation.
public struct UnreadySurface: Decodable, Sendable, Equatable {
    public let surface: String
    public let reasons: [String]
}

/// The service generation that makes public reads mutually consistent.
public struct Publication: Decodable, Sendable, Equatable {
    public let contractVersion: Int
    public let publicationId: Int
    public let publishedScrapeId: Int
    public let readyForPinning: Bool
    public let pinningEnabled: Bool
    public let unreadySurfaces: [UnreadySurface]

    /// Validates the required fields before the generation is used for requests.
    ///
    /// - Throws: `FestivalAPIError.invalidPublication` for a malformed generation.
    public func validate() throws {
        guard contractVersion > 0, publicationId > 0, publishedScrapeId > 0 else {
            throw FestivalAPIError.invalidPublication
        }
    }
}

/// Distinct transport and consistency failures surfaced to the user interface.
public enum FestivalAPIError: LocalizedError, Equatable, Sendable {
    case insecureBaseURL
    case invalidPublication
    case invalidResponse
    case invalidResource
    case invalidCatalogue
    case invalidLeaderboard
    case invalidArtwork
    case invalidShop
    case invalidSongFilter
    case invalidPathData
    case invalidPathImage
    case invalidProfileSearchQuery
    case invalidProfileSearchLimit
    case invalidProfileSearch
    case invalidPlayerProfile
    case invalidSelectedProfile
    case invalidBandProfile
    case httpStatus(Int)
    case unexpectedNotModified
    case unavailable(retryAfter: String?)

    /// Explain service failures without exposing Swift enum names or server text.
    ///
    /// - Returns: A localized-description fallback for visible retry and error states.
    public var errorDescription: String? {
        switch self {
        case .insecureBaseURL:
            "A secure service connection is required."
        case .invalidPublication:
            "The current scores could not be verified. Try again."
        case .invalidResponse, .invalidCatalogue, .invalidLeaderboard:
            "The service returned data we could not read. Try again."
        case .invalidResource:
            "That song or chart is unavailable."
        case .invalidArtwork:
            "Album artwork could not be displayed."
        case .invalidShop:
            "The Item Shop data could not be read. Try again."
        case .invalidSongFilter:
            "The saved song filters could not be read. Reset them to continue."
        case .invalidPathData:
            "The path data could not be read. Try another chart or difficulty."
        case .invalidPathImage:
            "The path image could not be displayed. Try another chart or difficulty."
        case .invalidProfileSearchQuery:
            "Enter 2 to 200 characters to search players."
        case .invalidProfileSearchLimit:
            "Player search can request up to ten results."
        case .invalidProfileSearch:
            "Player search returned unreadable data. Try again."
        case .invalidPlayerProfile:
            "The selected player's scores could not be read. Try again."
        case .invalidSelectedProfile:
            "The saved profile could not be read. Choose a profile again."
        case .invalidBandProfile:
            "That band could not be read. Try again."
        case let .httpStatus(status):
            if status == 404 {
                "That song or chart is no longer available."
            } else if status == 429 {
                "Too many requests. Try again shortly."
            } else if (500...599).contains(status) {
                "The service is temporarily unavailable. Try again."
            } else {
                "The service could not load this content (HTTP \(status))."
            }
        case .unexpectedNotModified:
            "The service returned an incomplete update. Try again."
        case let .unavailable(retryAfter):
            if let retryAfter, let seconds = Int(retryAfter), (1...86_400).contains(seconds) {
                "The service is temporarily unavailable. Try again in \(seconds) seconds."
            } else {
                "The service is temporarily unavailable. Try again."
            }
        }
    }
}
