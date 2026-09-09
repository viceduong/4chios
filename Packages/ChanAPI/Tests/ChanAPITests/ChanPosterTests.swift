import ChanCore
import Foundation
import XCTest
@testable import ChanAPI

final class MultipartFormDataTests: XCTestCase {
    func testEncodesFieldsAndFiles() {
        var form = MultipartFormData()
        form.fields.append(("mode", "regist"))
        form.fields.append(("com", "hello"))
        form.files.append((name: "upfile", filename: "cat.jpg", mimeType: "image/jpeg", data: Data([0x01, 0x02])))

        let body = String(decoding: form.encoded(), as: UTF8.self)

        XCTAssertTrue(body.contains("name=\"mode\"\r\n\r\nregist\r\n"))
        XCTAssertTrue(body.contains("name=\"com\"\r\n\r\nhello\r\n"))
        XCTAssertTrue(body.contains("filename=\"cat.jpg\""))
        XCTAssertTrue(body.contains("Content-Type: image/jpeg"))
        XCTAssertTrue(body.hasSuffix("--\(form.boundary)--\r\n"))
        XCTAssertTrue(form.contentType.hasPrefix("multipart/form-data; boundary="))
    }
}

final class ChanPosterTests: XCTestCase {
    private func makePoster(_ responses: [ChanHTTPResponse]) -> (ChanPoster, MockTransport) {
        let transport = MockTransport(responses: responses)
        let poster = ChanPoster(transport: transport, rateLimiter: ChanRateLimiter(minimumInterval: 0))
        return (poster, transport)
    }

    private func json(_ string: String) -> Data { Data(string.utf8) }

    func testReplySuccess() async throws {
        let (poster, transport) = makePoster([ChanHTTPResponse(statusCode: 200, body: json(#"{"tid":123,"pid":456}"#))])
        let result = try await poster.post(
            ChanPostRequest(board: "g", thread: 123, name: "Anonymous", comment: "hi", challenge: "c", response: "abcd")
        )

        XCTAssertEqual(result, .success(thread: PostNumber(123), post: PostNumber(456)))

        let body = String(decoding: transport.requests[0].body ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"resto\"\r\n\r\n123"))
        XCTAssertTrue(body.contains("name=\"t-challenge\"\r\n\r\nc"))
        XCTAssertTrue(body.contains("name=\"t-response\"\r\n\r\nabcd"))
        XCTAssertTrue(body.contains("name=\"mode\"\r\n\r\nregist"))
        XCTAssertEqual(transport.requests[0].url.absoluteString, "https://sys.4channel.org/g/post")
    }

    func testNewThreadSendsZeroRestoAndSubject() async throws {
        let (poster, transport) = makePoster([ChanHTTPResponse(statusCode: 200, body: json(#"{"thread":10,"post":11}"#))])
        let result = try await poster.post(ChanPostRequest(board: "v", subject: "New thread", comment: "op"))
        XCTAssertEqual(result, .success(thread: PostNumber(10), post: PostNumber(11)))

        let body = String(decoding: transport.requests[0].body ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"resto\"\r\n\r\n0"))
        XCTAssertTrue(body.contains("name=\"sub\"\r\n\r\nNew thread"))
    }

    func testServerErrorIsSurfaced() async throws {
        let (poster, _) = makePoster([ChanHTTPResponse(statusCode: 200, body: json(#"{"error":"You must wait longer before posting."}"#))])
        let result = try await poster.post(ChanPostRequest(board: "g", thread: 1, comment: "x"))
        XCTAssertEqual(result, .failure(message: "You must wait longer before posting."))
    }

    func testNonJSONResponseIsSurfaced() async throws {
        let (poster, _) = makePoster([ChanHTTPResponse(statusCode: 200, body: json("<html>cloudflare</html>"))])
        let result = try await poster.post(ChanPostRequest(board: "g", thread: 1, comment: "x"))
        if case let .failure(message) = result {
            XCTAssertTrue(message.contains("cloudflare"))
        } else {
            XCTFail("expected failure")
        }
    }

    func testCaptchaDecoding() async throws {
        let payload = """
        {"challenge":"abc123","ttl":120,"cd":5,
         "img":"\(Data([0x89, 0x50]).base64EncodedString())",
         "bg":"\(Data([0xFF, 0x00]).base64EncodedString())"}
        """
        let (poster, transport) = makePoster([ChanHTTPResponse(statusCode: 200, body: json(payload))])

        let result = try await poster.requestCaptcha(board: "g", thread: PostNumber(99))
        guard case let .challenge(captcha) = result else {
            return XCTFail("expected a challenge, got \(result)")
        }

        XCTAssertEqual(captcha.challenge, "abc123")
        XCTAssertEqual(captcha.ttl, 120)
        XCTAssertEqual(captcha.imagePNG, Data([0x89, 0x50]))
        XCTAssertEqual(captcha.backgroundPNG, Data([0xFF, 0x00]))
        XCTAssertTrue(transport.requests[0].url.absoluteString.contains("board=g"))
        XCTAssertTrue(transport.requests[0].url.absoluteString.contains("thread_id=99"))
    }

    func testCaptchaCooldown() async throws {
        let (poster, _) = makePoster([ChanHTTPResponse(statusCode: 200, body: json(#"{"pcd":7}"#))])
        let result = try await poster.requestCaptcha(board: "g", thread: nil)
        guard case let .cooldown(seconds) = result else {
            return XCTFail("expected cooldown, got \(result)")
        }
        XCTAssertEqual(seconds, 7)
    }

    func testPassAuthentication() async throws {
        let (poster, transport) = makePoster([ChanHTTPResponse(statusCode: 200, body: json(#"{"success":true}"#))])
        let ok = try await poster.authenticatePass(id: "123", pin: "456")
        XCTAssertTrue(ok)

        let body = String(decoding: transport.requests[0].body ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"id\"\r\n\r\n123"))
        XCTAssertTrue(body.contains("name=\"pin\"\r\n\r\n456"))
        XCTAssertEqual(transport.requests[0].url.absoluteString, "https://sys.4chan.org/auth")
    }
}
