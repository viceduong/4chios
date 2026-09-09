import BackgroundTasks
import ChanAPI
import ChanCore
import ChanDB
import Foundation
import UserNotifications
import UIKit

/// Best-effort background refresh for watched threads.
///
/// iOS decides when (and whether) to run `BGAppRefreshTask`, so this is an
/// opportunistic check rather than a guarantee. The foreground poll in
/// `ThreadScreen` is the primary mechanism; this catches replies to threads the
/// user is not currently looking at.
public enum BackgroundRefresher {
    public static let taskIdentifier = "com.viceduong.ch4ios.refresh"

    /// Set once at launch by `ChanAppDelegate`.
    static var client: ChanClient?
    static var database: ChanDatabase?

    private static let minimumInterval: TimeInterval = 15 * 60
    private static let maximumThreadsPerRun = 4

    /// Must be called before the app finishes launching.
    public static func register(client: ChanClient, database: ChanDatabase) {
        self.client = client
        self.database = database

        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    /// Asks iOS for the next opportunity to refresh.
    public static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Requests notification permission the first time the user watches a thread.
    public static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private static func handle(_ task: BGAppRefreshTask) {
        schedule()
        let work = Task {
            let success = await checkWatchedThreads()
            task.setTaskCompleted(success: success)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    /// Returns true when the run completed without being cancelled.
    @discardableResult
    static func checkWatchedThreads() async -> Bool {
        guard let client, let database else { return true }
        let watched = (try? database.watchedThreads()) ?? []
        guard !watched.isEmpty else { return true }

        let pending = watched.filter(\.notify).prefix(maximumThreadsPerRun)

        for watch in pending {
            if Task.isCancelled { return false }
            do {
                let posts = try await client.thread(watch.board, op: watch.op)
                guard let opPost = posts.first(where: { $0.isOP }) else { continue }
                try? database.saveThread(board: watch.board, op: watch.op, posts: posts)

                let replies = opPost.replies ?? 0
                let newReplies = replies - watch.lastSeenReply
                guard newReplies > 0 else { continue }

                notify(
                    board: watch.board,
                    op: watch.op,
                    title: threadTitle(from: opPost),
                    newReplies: newReplies
                )
                try? database.updateWatchProgress(board: watch.board, op: watch.op, replies: replies)
            } catch {
                // Archived or deleted threads simply stop notifying.
                continue
            }
        }

        return true
    }

    private static func threadTitle(from post: Post) -> String {
        if let subject = post.subject, !subject.isEmpty { return subject }
        let body = PostHTMLParser.parse(post.commentHTML ?? "").plainText
        if !body.isEmpty { return String(body.prefix(90)) }
        return "Thread #\(post.no.value)"
    }

    private static func notify(board: BoardID, op: PostNumber, title: String, newReplies: Int) {
        let content = UNMutableNotificationContent()
        content.title = "/\(board.rawValue)/ · \(newReplies) new \(newReplies == 1 ? "reply" : "replies")"
        content.body = title
        content.sound = .default
        content.userInfo = ["board": board.rawValue, "op": op.value]
        content.threadIdentifier = "\(board.rawValue)/\(op.value)"

        let request = UNNotificationRequest(
            identifier: "\(board.rawValue)/\(op.value)/\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}

/// Wires background task registration into the SwiftUI app lifecycle.
public final class ChanAppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let environment = AppEnvironment.shared
        BackgroundRefresher.register(client: environment.client, database: environment.database)
        BackgroundRefresher.schedule()
        return true
    }
}
