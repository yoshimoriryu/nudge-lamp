import Darwin
import Foundation

public enum SessionDirectory {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/sessions", isDirectory: true)
    }

    /// Reads every live, user-facing session in `directory`.
    ///
    /// Claude Code leaves a file behind when it crashes, so each record is checked
    /// against the process table before it is returned.
    public static func load(
        from directory: URL = defaultURL,
        isAlive: (SessionRecord) -> Bool = ProcessLookup.isAlive
    ) -> [SessionRecord] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        let decoder = JSONDecoder()
        return names
            .filter { $0.hasSuffix(".json") }
            .compactMap { name -> SessionRecord? in
                guard
                    let data = fm.contents(atPath: directory.appendingPathComponent(name).path),
                    let record = try? decoder.decode(SessionRecord.self, from: data),
                    record.isUserFacing,
                    isAlive(record)
                else { return nil }
                return record
            }
    }
}

public enum ProcessLookup {
    /// True when the PID is running and is the same process that wrote the record.
    public static func isAlive(_ record: SessionRecord) -> Bool {
        guard let start = startTime(of: record.pid) else { return false }
        guard let startedAt = record.startDate else { return true }
        // A recycled PID belongs to a process that started after Claude Code wrote the file.
        return start <= startedAt.addingTimeInterval(5)
    }

    public static func startTime(of pid: Int32) -> Date? {
        guard let info = kinfo(pid) else { return nil }
        let tv = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }

    /// The controlling terminal of a process, for example "/dev/ttys003".
    public static func tty(of pid: Int32) -> String? {
        guard let info = kinfo(pid) else { return nil }
        let dev = info.kp_eproc.e_tdev
        guard dev != -1, let name = devname(dev, mode_t(S_IFCHR)) else { return nil }
        return "/dev/" + String(cString: name)
    }

    private static func kinfo(_ pid: Int32) -> kinfo_proc? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info
    }
}
