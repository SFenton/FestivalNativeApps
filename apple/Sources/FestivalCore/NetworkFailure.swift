import Foundation

extension URLError {
    /// A connectivity outage can reuse warm process memory; cancellation cannot.
    var canUseOfflineCache: Bool {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost,
             .cannotFindHost, .cannotConnectToHost, .timedOut:
            true
        default:
            false
        }
    }
}
