import ChanAPI
import ChanCore
import ChanUI
import SwiftUI
import UIKit

/// Drives the composer: fields, attachment, captcha, Pass, and submission.
@MainActor
public final class ComposerStore: ObservableObject {
    public let board: BoardID
    /// nil means "new thread".
    public let thread: PostNumber?

    @Published public var name = ""
    @Published public var email = ""
    @Published public var subject = ""
    @Published public var comment = ""
    @Published public var password = ""
    @Published public var fileTag = ""
    @Published public var isSpoiler = false
    @Published public var attachment: ChanPostAttachment?

    @Published public private(set) var captcha: ChanCaptcha?
    @Published public private(set) var captchaBackground: UIImage?
    @Published public private(set) var captchaForeground: UIImage?
    @Published public var captchaResponse = ""

    @Published public private(set) var isSubmitting = false
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var didPost = false
    @Published public private(set) var postedThread: PostNumber?
    @Published public private(set) var cooldownRemaining = 0

    @Published public var usePass = false
    @Published public var passID = ""
    @Published public var passPIN = ""

    private let environment: AppEnvironment
    private var cooldownTask: Task<Void, Never>?

    public init(board: BoardID, thread: PostNumber?, environment: AppEnvironment) {
        self.board = board
        self.thread = thread
        self.environment = environment
    }

    public var isNewThread: Bool { thread == nil }

    public var canSubmit: Bool {
        guard !isSubmitting, cooldownRemaining == 0 else { return false }
        guard !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || attachment != nil else { return false }
        if usePass { return !passID.isEmpty && !passPIN.isEmpty }
        return captcha != nil && !captchaResponse.isEmpty
    }

    // MARK: - Attachment

    public func attach(data: Data, filename: String, mimeType: String) {
        attachment = ChanPostAttachment(filename: filename, mimeType: mimeType, data: data)
    }

    public func removeAttachment() {
        attachment = nil
    }

    // MARK: - Captcha

    public func loadCaptcha() async {
        guard !usePass else { return }
        statusMessage = nil
        do {
            switch try await environment.poster.requestCaptcha(board: board, thread: thread) {
            case let .challenge(challenge):
                captcha = challenge
                captchaBackground = UIImage(data: challenge.backgroundPNG)
                captchaForeground = UIImage(data: challenge.imagePNG)
                captchaResponse = ""
            case let .cooldown(seconds):
                startCooldown(seconds)
            case let .failure(message):
                statusMessage = message
            }
        } catch let error as ChanError {
            statusMessage = error.errorDescription
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func startCooldown(_ seconds: Int) {
        cooldownTask?.cancel()
        cooldownRemaining = seconds
        cooldownTask = Task { [weak self] in
            var remaining = seconds
            while remaining > 0, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                remaining -= 1
                self?.cooldownRemaining = max(0, remaining)
            }
            guard !Task.isCancelled else { return }
            await self?.loadCaptcha()
        }
    }

    // MARK: - Pass

    public func authenticatePass() async {
        guard !passID.isEmpty, !passPIN.isEmpty else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let ok = try await environment.poster.authenticatePass(id: passID, pin: passPIN)
            statusMessage = ok ? "Pass authenticated. Captcha skipped." : "Pass authentication failed."
            if ok {
                captcha = nil
                captchaForeground = nil
                captchaBackground = nil
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    // MARK: - Submit

    public func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        statusMessage = nil
        defer { isSubmitting = false }

        let request = ChanPostRequest(
            board: board,
            thread: thread,
            name: name,
            email: email,
            subject: isNewThread ? subject : "",
            comment: comment,
            password: password.isEmpty ? randomPassword() : password,
            isSpoiler: isSpoiler,
            fileTag: fileTag,
            attachment: attachment,
            challenge: usePass ? nil : captcha?.challenge,
            response: usePass ? nil : captchaResponse
        )

        do {
            switch try await environment.poster.post(request) {
            case let .success(thread, post):
                postedThread = thread
                didPost = true
                ChanHaptics.success()
                statusMessage = "Posted #\(post.value)"
            case let .failure(message):
                statusMessage = message
                ChanHaptics.error()
                // A fresh captcha is required after every attempt.
                await loadCaptcha()
            }
        } catch let error as ChanError {
            statusMessage = error.errorDescription
            ChanHaptics.error()
        } catch {
            statusMessage = error.localizedDescription
            ChanHaptics.error()
        }
    }

    private func randomPassword() -> String {
        (0..<8).map { _ in "abcdefghijklmnopqrstuvwxyz0123456789".randomElement()! }.map(String.init).joined()
    }
}
