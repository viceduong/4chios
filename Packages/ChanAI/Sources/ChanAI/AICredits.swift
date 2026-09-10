import ChanAPI
import Foundation

/// Account credit for a provider that exposes it.
public struct AICredits: Sendable, Equatable {
    public let granted: Double
    public let used: Double

    public init(granted: Double, used: Double) {
        self.granted = granted
        self.used = used
    }

    public var remaining: Double { granted - used }

    /// True once the balance has been spent. Providers commonly keep serving
    /// into a small negative balance rather than stopping exactly at zero.
    public var isOverdrawn: Bool { remaining <= 0 }

    public var formattedRemaining: String { Self.format(remaining) }
    public var formattedGranted: String { Self.format(granted) }
    public var formattedUsed: String { Self.format(used) }

    public static func format(_ amount: Double) -> String {
        let sign = amount < 0 ? "-" : ""
        let magnitude = abs(amount)
        if magnitude < 0.01, magnitude > 0 { return "\(sign)$\(String(format: "%.4f", magnitude))" }
        return "\(sign)$\(String(format: "%.2f", magnitude))"
    }
}

/// Reads a provider's credit balance.
///
/// OpenRouter exposes `GET /api/v1/credits`, returning granted and used totals.
/// General Compute has no equivalent endpoint, which is why its balance can only
/// be read from the dashboard.
public struct AICreditsClient: Sendable {
    private let transport: ChanTransport

    public init(transport: ChanTransport = URLSessionTransport()) {
        self.transport = transport
    }

    public func credits(baseURL: URL, apiKey: String) async throws -> AICredits {
        guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw AIChatError.notConfigured
        }

        let request = ChanHTTPRequest(
            url: baseURL.appendingPathComponent("credits"),
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Accept": "application/json",
            ]
        )

        let response: ChanHTTPResponse
        do {
            response = try await transport.send(request)
        } catch let error as ChanError {
            if case .cancelled = error { throw AIChatError.cancelled }
            throw AIChatError.transport(error.errorDescription ?? "Request failed.")
        }

        guard response.isSuccess else {
            throw AIChatError.http(
                status: response.statusCode,
                message: String(decoding: response.body.prefix(200), as: UTF8.self)
            )
        }

        do {
            let decoded = try JSONDecoder().decode(CreditsResponse.self, from: response.body)
            guard let data = decoded.data else {
                throw AIChatError.decoding("The credits response had no data.")
            }
            return AICredits(granted: data.totalCredits, used: data.totalUsage)
        } catch let error as AIChatError {
            throw error
        } catch {
            throw AIChatError.decoding(String(describing: error))
        }
    }
}

private struct CreditsResponse: Decodable {
    struct Payload: Decodable {
        let totalCredits: Double
        let totalUsage: Double

        enum CodingKeys: String, CodingKey {
            case totalCredits = "total_credits"
            case totalUsage = "total_usage"
        }
    }

    let data: Payload?
}
