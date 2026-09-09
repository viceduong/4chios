import ChanCore
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A transport-agnostic HTTP request. Kept minimal so tests can fake it.
public struct ChanHTTPRequest: Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?

    public init(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

public struct ChanHTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public var isSuccess: Bool { (200..<300).contains(statusCode) }
    public var isNotModified: Bool { statusCode == 304 }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// Anything that can perform a `ChanHTTPRequest`.
public protocol ChanTransport: Sendable {
    func send(_ request: ChanHTTPRequest) async throws -> ChanHTTPResponse
}

/// The production transport. A desktop-class user agent is required: 4chan's CDN
/// rejects unknown clients, and the posting endpoints are Cloudflare-protected.
public struct URLSessionTransport: ChanTransport, @unchecked Sendable {
    public static let defaultUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 15_6 like Mac OS X) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/15.6 Mobile/15E148 Safari/604.1"

    private let session: URLSession
    private let userAgent: String

    public init(session: URLSession = .shared, userAgent: String = URLSessionTransport.defaultUserAgent) {
        self.session = session
        self.userAgent = userAgent
    }

    public func send(_ request: ChanHTTPRequest) async throws -> ChanHTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = 30
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw ChanError.transport("Non-HTTP response")
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                headers[String(describing: key)] = String(describing: value)
            }
            return ChanHTTPResponse(statusCode: http.statusCode, headers: headers, body: data)
        } catch let error as ChanError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw ChanError.cancelled
        } catch {
            throw ChanError.transport(error.localizedDescription)
        }
    }
}
