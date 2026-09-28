import Foundation

extension URLError {
    /// A connectivity outage can reuse warm process memory; cancellation cannot.
    var canUseOfflineCache: Bool {
        isOffline
    }

    /// Whether this failure means the device could not reach the service at all.
    ///
    /// Cancellation, TLS and malformed-response errors are not offline states.
    var isOffline: Bool {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost,
             .cannotFindHost, .cannotConnectToHost, .timedOut:
            true
        default:
            false
        }
    }
}
