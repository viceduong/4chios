import Foundation

/// Every failure surfaced by the data layer, in a form the UI can present verbatim.
public enum ChanError: Error, Equatable, Sendable {
    /// The shared rate limiter refused the request; the caller should retry later.
    case rateLimited(retryAfter: TimeInterval)
    /// The server answered `304 Not Modified` — the cached body is still current.
    case notModified
    /// A non-2xx HTTP response.
    case http(status: Int, endpoint: String)
    /// The response body could not be decoded into the expected shape.
    case decoding(String)
    /// The network is unreachable or the request failed at the transport layer.
    case transport(String)
    /// The task was cancelled, usually because the view went away.
    case cancelled
    /// The thread or board no longer exists (404 / archived).
    case gone
}

extension ChanError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .rateLimited(retryAfter):
            return "Slow down — retrying in \(Int(retryAfter.rounded()))s."
        case .notModified:
            return nil
        case let .http(status, endpoint):
            return "Server returned \(status) for \(endpoint)."
        case let .decoding(detail):
            return "Couldn't read the response: \(detail)"
        case let .transport(detail):
            return detail
        case .cancelled:
            return nil
        case .gone:
            return "This thread is gone or archived."
        }
    }
}
