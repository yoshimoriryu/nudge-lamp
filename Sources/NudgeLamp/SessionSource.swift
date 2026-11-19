import Foundation
import NudgeLampCore

/// Keeps an up-to-date session list without running `claude agents --json` every second.
///
/// Each poll only reads file modification times in `~/.claude/sessions`, which costs almost
/// nothing. The command runs when one of those times changes, and at least once a minute.
@MainActor
final class SessionSource {
    private(set) var records: [SessionRecord] = []
    private(set) var claude: URL?
    private(set) var problem: String?
    var onUpdate: () -> Void = {}

    private var lastDates: [Int32: Date]?
    private var lastRun = Date.distantPast
    private var running = false
    static let safetyInterval: TimeInterval = 60

    func poll(now: Date = Date()) {
        guard !running else { return }
        let dates = SessionFolder.modificationDates()
        guard dates != lastDates || now.timeIntervalSince(lastRun) > Self.safetyInterval else { return }

        lastDates = dates
        lastRun = now
        running = true
        let known = claude
        Task.detached {
            let found = known ?? ClaudeAgents.locate()
            let result = Result<[SessionRecord], Error> {
                guard let found else { throw ClaudeAgents.Failure.claudeNotFound }
                return try ClaudeAgents.parse(ClaudeAgents.run(claude: found), changedAt: dates)
            }
            await self.finish(claude: found, result: result)
        }
    }

    private func finish(claude found: URL?, result: Result<[SessionRecord], Error>) {
        running = false
        claude = found
        switch result {
        case .success(let fresh):
            records = fresh
            problem = nil
        case .failure(ClaudeAgents.Failure.claudeNotFound):
            records = []
            problem = "Claude Code CLI not found"
        case .failure(let error):
            // Keep the last good list; one failed run should not blank the menu.
            problem = "claude agents --json failed: \(error)"
        }
        onUpdate()
    }
}
