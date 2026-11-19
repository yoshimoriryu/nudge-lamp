import Darwin
import Foundation

/// Reads live sessions from `claude agents --json`, which the Claude Code docs name as
/// "the supported way to read session state from outside Claude Code, for example from a status bar".
/// The command reads local state only. It makes no network requests and uses no tokens.
public enum ClaudeAgents {
    public enum Failure: Error, Equatable {
        case claudeNotFound
        case exitStatus(Int32)
    }

    /// One entry of the command's JSON array, with the fields the docs list.
    private struct Entry: Decodable {
        var pid: Int32?
        var sessionId: String?
        var cwd: String?
        var name: String?
        var kind: String?
        var status: String?
        var waitingFor: String?
        var startedAt: Double?
    }

    /// Turns the command output into records. `pid` and `status` are present only while the
    /// session's process is alive, so finished background sessions drop out here.
    /// - Parameter changedAt: when each session last changed, keyed by PID (see `SessionFolder`).
    public static func parse(_ data: Data, changedAt: [Int32: Date] = [:]) throws -> [SessionRecord] {
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        return entries.compactMap { entry -> SessionRecord? in
            guard let pid = entry.pid, let status = entry.status else { return nil }
            let record = SessionRecord(
                pid: pid,
                sessionId: entry.sessionId ?? "pid-\(pid)",
                cwd: entry.cwd ?? "",
                name: entry.name,
                kind: entry.kind,
                status: status,
                waitingFor: entry.waitingFor,
                startedAt: entry.startedAt,
                statusUpdatedAt: changedAt[pid].map { $0.timeIntervalSince1970 * 1000 }
            )
            return record.isUserFacing ? record : nil
        }
    }

    /// Runs `claude agents --json` and returns its output. Blocks for about 0.2 s,
    /// so call it off the main thread.
    public static func run(claude: URL) throws -> Data {
        let process = Process()
        process.executableURL = claude
        process.arguments = ["agents", "--json"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.exitStatus(process.terminationStatus) }
        return data
    }

    /// Finds the `claude` executable. Apps opened from Finder do not inherit the shell's PATH,
    /// so this checks the usual install locations first, then asks a login shell.
    public static func locate() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        if let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) {
            return URL(fileURLWithPath: path)
        }
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-lc", "command -v claude"]
        let output = Pipe()
        shell.standardOutput = output
        shell.standardError = FileHandle.nullDevice
        shell.standardInput = FileHandle.nullDevice
        guard (try? shell.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        shell.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard shell.terminationStatus == 0, path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path)
    }
}

/// Tells when sessions change, without reading the session files.
///
/// The Claude Code docs say `~/.claude/sessions` "holds one small file per running session".
/// Nudge Lamp only looks at each file's modification time. A change means a session changed,
/// which is the cue to run `claude agents --json` again.
public enum SessionFolder {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions", isDirectory: true)
    }

    /// Modification time of each `<pid>.json` file, keyed by PID.
    public static func modificationDates(in directory: URL = defaultURL) -> [Int32: Date] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [:] }
        var dates: [Int32: Date] = [:]
        for name in names where name.hasSuffix(".json") {
            guard
                let pid = Int32(name.dropLast(5)),
                let attributes = try? fm.attributesOfItem(atPath: directory.appendingPathComponent(name).path),
                let date = attributes[.modificationDate] as? Date
            else { continue }
            dates[pid] = date
        }
        return dates
    }
}

public enum ProcessLookup {
    /// The controlling terminal of a process, for example "/dev/ttys003".
    public static func tty(of pid: Int32) -> String? {
        guard let info = kinfo(pid) else { return nil }
        let dev = info.kp_eproc.e_tdev
        guard dev != -1, let name = devname(dev, mode_t(S_IFCHR)) else { return nil }
        return "/dev/" + String(cString: name)
    }

    /// The parent process ID, or nil when the process is gone.
    public static func parent(of pid: Int32) -> Int32? {
        kinfo(pid)?.kp_eproc.e_ppid
    }

    private static func kinfo(_ pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }
}
