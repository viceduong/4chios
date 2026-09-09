import ChanCore
import Foundation

/// A file to upload with a post.
public struct ChanPostAttachment: Sendable {
    public var filename: String
    public var mimeType: String
    public var data: Data

    public init(filename: String, mimeType: String, data: Data) {
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }
}

/// Everything needed to submit a reply or a new thread.
public struct ChanPostRequest: Sendable {
    public var board: BoardID
    /// nil creates a new thread.
    public var thread: PostNumber?
    public var name: String
    public var email: String
    public var subject: String
    public var comment: String
    public var password: String
    public var flag: String?
    public var isSpoiler: Bool
    public var fileTag: String?
    public var attachment: ChanPostAttachment?
    public var challenge: String?
    public var response: String?

    public init(
        board: BoardID,
        thread: PostNumber? = nil,
        name: String = "",
        email: String = "",
        subject: String = "",
        comment: String = "",
        password: String = "",
        flag: String? = nil,
        isSpoiler: Bool = false,
        fileTag: String? = nil,
        attachment: ChanPostAttachment? = nil,
        challenge: String? = nil,
        response: String? = nil
    ) {
        self.board = board
        self.thread = thread
        self.name = name
        self.email = email
        self.subject = subject
        self.comment = comment
        self.password = password
        self.flag = flag
        self.isSpoiler = isSpoiler
        self.fileTag = fileTag
        self.attachment = attachment
        self.challenge = challenge
        self.response = response
    }
}

public enum ChanPostResult: Sendable, Equatable {
    case success(thread: PostNumber, post: PostNumber)
    case failure(message: String)
}

/// A captcha the user must solve.
public struct ChanCaptcha: Sendable, Equatable {
    public let challenge: String
    public let ttl: Int
    /// The characters, drawn on a transparent background.
    public let imagePNG: Data
    /// The background the characters belong on.
    public let backgroundPNG: Data
}

public enum ChanCaptchaResult: Sendable {
    case challenge(ChanCaptcha)
    /// The server asked us to wait; re-request after `seconds`.
    case cooldown(seconds: Int)
    case failure(message: String)
}

/// Submits posts and manages the captcha / Pass handshake.
///
/// Posting is unofficial and Cloudflare-protected, so every failure is surfaced
/// as a human-readable message rather than thrown away.
public struct ChanPoster: Sendable {
    private let transport: ChanTransport
    private let rateLimiter: ChanRateLimiter

    public init(transport: ChanTransport = URLSessionTransport(), rateLimiter: ChanRateLimiter) {
        self.transport = transport
        self.rateLimiter = rateLimiter
    }

    // MARK: - Captcha

    public func requestCaptcha(board: BoardID, thread: PostNumber?) async throws -> ChanCaptchaResult {
        await rateLimiter.acquire(.userInitiated)

        var components = URLComponents(
            url: URL(string: "/captcha", relativeTo: ChanHost.captcha.url)!,
            resolvingAgainstBaseURL: false
        )!
        var items = [URLQueryItem(name: "board", value: board.rawValue)]
        if let thread {
            items.append(URLQueryItem(name: "thread_id", value: String(thread.value)))
        }
        components.queryItems = items

        let request = ChanHTTPRequest(
            url: components.url!,
            headers: [
                "Accept": "application/json",
                "Referer": "https://boards.4chan.org/\(board.rawValue)/",
            ]
        )
        let response = try await transport.send(request)

        guard response.isSuccess else {
            return .failure(message: "Captcha request failed (\(response.statusCode)).")
        }

        let decoded: CaptchaResponse
        do {
            decoded = try JSONDecoder().decode(CaptchaResponse.self, from: response.body)
        } catch {
            return .failure(message: "Could not read the captcha response.")
        }

        if let seconds = decoded.pcd, seconds > 0 {
            return .cooldown(seconds: seconds)
        }
        if let message = decoded.error {
            return .failure(message)
        }
        guard let challenge = decoded.challenge,
              let image = decoded.img.flatMap({ Data(base64Encoded: $0) }),
              let background = decoded.bg.flatMap({ Data(base64Encoded: $0) }) else {
            return .failure(message: "The captcha response was incomplete.")
        }

        return .challenge(
            ChanCaptcha(
                challenge: challenge,
                ttl: decoded.ttl ?? 120,
                imagePNG: image,
                backgroundPNG: background
            )
        )
    }

    // MARK: - Pass

    /// Authenticates a 4chan Pass. The resulting cookies live in the shared
    /// `URLSession` cookie store, so subsequent posts skip the captcha.
    @discardableResult
    public func authenticatePass(id: String, pin: String, longLogin: Bool = true) async throws -> Bool {
        await rateLimiter.acquire(.userInitiated)

        var form = MultipartFormData()
        form.fields.append(("id", id))
        form.fields.append(("pin", pin))
        if longLogin { form.fields.append(("long_login", "1")) }

        let request = ChanHTTPRequest(
            url: URL(string: "/auth", relativeTo: ChanHost.captcha.url)!.absoluteURL,
            method: "POST",
            headers: [
                "Accept": "application/json",
                "Content-Type": form.contentType,
                "Referer": "https://www.4chan.org/pass",
            ],
            body: form.encoded()
        )
        let response = try await transport.send(request)
        return response.isSuccess
    }

    // MARK: - Posting

    public func post(_ post: ChanPostRequest) async throws -> ChanPostResult {
        await rateLimiter.acquire(.userInitiated)

        var form = MultipartFormData()
        form.fields.append(("mode", "regist"))
        form.fields.append(("resto", post.thread.map { String($0.value) } ?? "0"))
        if !post.name.isEmpty { form.fields.append(("name", post.name)) }
        if !post.email.isEmpty { form.fields.append(("email", post.email)) }
        if !post.subject.isEmpty { form.fields.append(("sub", post.subject)) }
        if !post.comment.isEmpty { form.fields.append(("com", post.comment)) }
        if !post.password.isEmpty { form.fields.append(("pwd", post.password)) }
        if let flag = post.flag, !flag.isEmpty { form.fields.append(("flag", flag)) }
        if post.isSpoiler { form.fields.append(("spoiler", "on")) }
        if let fileTag = post.fileTag, !fileTag.isEmpty { form.fields.append(("filetag", fileTag)) }
        if let challenge = post.challenge { form.fields.append(("t-challenge", challenge)) }
        if let response = post.response { form.fields.append(("t-response", response)) }
        if let attachment = post.attachment {
            form.files.append(
                (
                    name: "upfile",
                    filename: attachment.filename,
                    mimeType: attachment.mimeType,
                    data: attachment.data
                )
            )
        }

        let url = URL(string: "/\(post.board.rawValue)/post", relativeTo: ChanHost.posting.url)!.absoluteURL
        let request = ChanHTTPRequest(
            url: url,
            method: "POST",
            headers: [
                "Accept": "application/json",
                "Content-Type": form.contentType,
                "Origin": "https://boards.4chan.org",
                "Referer": "https://boards.4chan.org/\(post.board.rawValue)/",
            ],
            body: form.encoded()
        )

        let response = try await transport.send(request)
        guard response.isSuccess else {
            return .failure(message: "The server rejected the post (\(response.statusCode)).")
        }

        if let decoded = try? JSONDecoder().decode(PostResponse.self, from: response.body) {
            if let message = decoded.error {
                return .failure(message)
            }
            let thread = decoded.tid ?? decoded.thread
            let number = decoded.pid ?? decoded.post
            if let thread, let number {
                return .success(thread: PostNumber(thread), post: PostNumber(number))
            }
        }

        let snippet = String(decoding: response.body.prefix(280), as: UTF8.self)
        return .failure(message: snippet.isEmpty ? "The server returned an unexpected response." : snippet)
    }
}

// MARK: - Wire types

private struct CaptchaResponse: Decodable {
    let challenge: String?
    let ttl: Int?
    let cd: Int?
    let img: String?
    let bg: String?
    let pcd: Int?
    let ticket: String?
    let error: String?
}

private struct PostResponse: Decodable {
    let tid: Int?
    let pid: Int?
    let thread: Int?
    let post: Int?
    let error: String?
}

// MARK: - Multipart

struct MultipartFormData {
    let boundary = "ch4ios-\(UUID().uuidString)"
    var fields: [(name: String, value: String)] = []
    var files: [(name: String, filename: String, mimeType: String, data: Data)] = []

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    func encoded() -> Data {
        var body = Data()

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        for field in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n")
            append("\(field.value)\r\n")
        }

        for file in files {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.filename)\"\r\n")
            append("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            append("\r\n")
        }

        append("--\(boundary)--\r\n")
        return body
    }
}
