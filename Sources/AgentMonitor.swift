import Foundation
import Darwin

enum PetStage: String, CaseIterable {
    case idle, calm, steady, busy, heated, rush

    static func forCount(_ count: Int, thresholds: StageThresholds = .standard) -> PetStage {
        thresholds.stage(for: count)
    }
    var rank: Int { Self.allCases.firstIndex(of: self)! }
    var asset: String { rawValue }
    var title: String {
        switch self {
        case .idle: return "휴식 zzz"
        case .calm: return "여유"
        case .steady: return "집중"
        case .busy: return "연기"
        case .heated: return "불꽃"
        case .rush: return "폭주 · 큰 불꽃"
        }
    }
}

struct StageThresholds: Equatable {
    static let stages: [PetStage] = [.steady, .busy, .heated, .rush]
    static let standard = StageThresholds(starts: [3, 5, 7, 10])!
    static let presets = [StageThresholds(starts: [1, 2, 2, 3])!,
                          StageThresholds(starts: [2, 3, 4, 5])!, standard]
    static let defaultsKey = "petMotionThresholds"
    let starts: [Int]

    init?(starts: [Int]) {
        guard starts.count == Self.stages.count,
              starts.allSatisfy({ (1...99).contains($0) }),
              zip(starts, starts.dropFirst()).allSatisfy({ $0.0 <= $0.1 }) else { return nil }
        self.starts = starts
    }
    func stage(for count: Int) -> PetStage {
        guard count > 0 else { return .idle }
        return zip(Self.stages, starts).reversed().first(where: { count >= $0.1 })?.0 ?? .calm
    }
    static func load(from defaults: UserDefaults = .standard) -> StageThresholds {
        guard let starts = defaults.array(forKey: defaultsKey) as? [Int],
              let value = StageThresholds(starts: starts) else { return .standard }
        return value
    }
    func save(to defaults: UserDefaults = .standard) { defaults.set(starts, forKey: Self.defaultsKey) }
}

/// Rising load takes effect immediately; a lower stage must persist for four seconds.
struct StageGate {
    private(set) var stage: PetStage = .idle
    private var pending: PetStage?
    private var pendingSince: TimeInterval = 0

    mutating func update(count: Int, now: TimeInterval, thresholds: StageThresholds = .standard) -> PetStage {
        let next = PetStage.forCount(count, thresholds: thresholds)
        if next.rank >= stage.rank {
            stage = next
            pending = nil
        } else if pending != next {
            pending = next
            pendingSince = now
        } else if now - pendingSince >= 4 {
            stage = next
            pending = nil
        }
        return stage
    }
}

struct AgentSnapshot: Codable {
    let codex: Int
    let claude: Int
    var additional: [String: Int] = [:]
    let warnings: [String]
    var total: Int { codex + claude + additional.values.reduce(0, +) }
    var summary: String {
        let names = ["grok": "Grok", "cursor": "Cursor", "cline": "Cline", "gemini": "Gemini", "opencode": "OpenCode"]
        return (["Codex \(codex)", "Claude \(claude)"] + additional.keys.sorted().map {
            "\(names[$0] ?? $0) \(additional[$0] ?? 0)"
        }).joined(separator: " · ")
    }
}

enum TurnState { case active, idle, unknown }

final class CodexLogReader {
    private struct Entry {
        let size: UInt64
        let modified: Date
        let inode: UInt64
        let state: TurnState
        let completeOffset: UInt64
        let anchor: Data
    }
    private var cache: [String: Entry] = [:]

    static func lifecycle(_ line: Data) -> TurnState? {
        // Reject ordinary messages before decoding JSON. Quoted event names in
        // user/tool text never count: both envelope and payload types must match.
        guard let text = String(data: line, encoding: .utf8),
              ["task_started", "task_complete", "turn_aborted", "shutdown_complete"].contains(where: text.contains),
              let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              root["type"] as? String == "event_msg",
              let payload = root["payload"] as? [String: Any],
              let type = payload["type"] as? String else { return nil }
        switch type {
        case "task_started": return .active
        case "task_complete", "turn_aborted", "shutdown_complete": return .idle
        default: return nil
        }
    }

    func state(at url: URL) throws -> TurnState {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let modified = attrs[.modificationDate] as? Date ?? .distantPast
        if let entry = cache[url.path], entry.size == size,
           entry.modified == modified, entry.inode == inode { return entry.state }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var previous: Entry?
        if let entry = cache[url.path], entry.inode == inode, size > entry.size {
            try handle.seek(toOffset: entry.size - UInt64(entry.anchor.count))
            if try handle.read(upToCount: entry.anchor.count) == entry.anchor { previous = entry }
        }
        // On subsequent polls inspect only appended data. The last complete
        // newline keeps a half-written event available for the following poll.
        let lowerBound = previous?.completeOffset ?? 0
        var cursor = size
        var completeOffset: UInt64?
        var remainder = Data()
        var skippingLargeLine = false
        var result: TurnState = .unknown
        scan: while cursor > lowerBound {
            let length = Int(min(cursor - lowerBound, 65_536))
            cursor -= UInt64(length)
            try handle.seek(toOffset: cursor)
            var chunk = try handle.read(upToCount: length) ?? Data()
            if completeOffset == nil, let newline = chunk.lastIndex(of: 10) {
                completeOffset = cursor + UInt64(newline) + 1
            }
            if skippingLargeLine {
                guard let newline = chunk.lastIndex(of: 10) else { continue }
                chunk = Data(chunk[..<newline])
                skippingLargeLine = false
            }
            chunk.append(remainder)
            let lines = chunk.split(separator: 10, omittingEmptySubsequences: false)
            for line in lines.dropFirst().reversed() {
                if let state = Self.lifecycle(Data(line)) {
                    result = state
                    break scan
                }
            }
            remainder = lines.first.map { Data($0) } ?? Data()
            // Tool results may be megabytes on one line. Discard them without
            // imposing a time-based expiry on legitimate long-running turns.
            if remainder.count > 1_048_576 {
                remainder.removeAll(keepingCapacity: false)
                skippingLargeLine = true
            }
        }
        if result == .unknown, !skippingLargeLine,
           let state = Self.lifecycle(remainder) { result = state }
        if result == .unknown, let previous { result = previous.state }
        let anchorSize = Int(min(size, 128))
        try handle.seek(toOffset: size - UInt64(anchorSize))
        let anchor = try handle.read(upToCount: anchorSize) ?? Data()
        cache[url.path] = Entry(size: size, modified: modified, inode: inode, state: result,
                                completeOffset: completeOffset ?? lowerBound, anchor: anchor)
        return result
    }

    func prune(keeping paths: Set<String>) {
        cache = cache.filter { paths.contains($0.key) }
    }
}

enum ProbeError: Error { case command(String) }

/// Reads process state in-process. Spawning `ps` and `lsof` every poll cost
/// about 0.2 CPU-seconds per poll; these kernel calls take a few milliseconds.
enum ProcessTable {
    /// All live PIDs and the running `codex` processes, from one sysctl call.
    static func scan() -> (live: Set<Int>, codex: [Int32])? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        let stride = MemoryLayout<kinfo_proc>.stride
        for _ in 0..<4 {
            var size = 0
            guard sysctl(&mib, 3, nil, &size, nil, 0) == 0 else { return nil }
            // Leave room for processes started between the two calls.
            var processes = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32)
            size = processes.count * stride
            guard sysctl(&mib, 3, &processes, &size, nil, 0) == 0 else {
                if errno == ENOMEM { continue }
                return nil
            }
            var live = Set<Int>()
            var codex: [Int32] = []
            for process in processes.prefix(size / stride) {
                live.insert(Int(process.kp_proc.p_pid))
                let name = withUnsafeBytes(of: process.kp_proc.p_comm) { Array($0.prefix(while: { $0 != 0 })) }
                if Int32(process.kp_proc.p_stat) != SZOMB, name.elementsEqual("codex".utf8) {
                    codex.append(process.kp_proc.p_pid)
                }
            }
            return (live, codex)
        }
        return nil
    }

    /// Paths of files the process holds open. Empty if it already exited, nil if it could not be read.
    static func openFiles(_ pid: Int32) -> [String]? {
        let stride = MemoryLayout<proc_fdinfo>.stride
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0 else { return kill(pid, 0) == 0 ? nil : [] }
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride + 16)
        let used = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fds, Int32(fds.count * stride))
        guard used > 0 else { return kill(pid, 0) == 0 ? nil : [] }
        let infoSize = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
        return fds.prefix(Int(used) / stride).compactMap { fd in
            guard fd.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) else { return nil }
            var info = vnode_fdinfowithpath()
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, infoSize) == infoSize else { return nil }
            return withUnsafeBytes(of: info.pvip.vip_path) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
        }
    }
}

final class AgentMonitor {
    private let home: URL
    private let logs = CodexLogReader()
    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    static func openRollouts(_ paths: [String]) -> Set<String> {
        Set(paths.filter { path in
            path.hasSuffix(".jsonl") && path.contains("/sessions/")
                && path.split(separator: "/").last?.hasPrefix("rollout-") == true
        })
    }

    static func workingClaude(_ data: Data, livePIDs: Set<Int>) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = object["pid"] as? Int, pid > 0, livePIDs.contains(pid),
              (object["kind"] as? String ?? "interactive") == "interactive",
              ["busy", "shell"].contains(object["status"] as? String ?? "") else { return nil }
        return object["sessionId"] as? String ?? "pid-\(pid)"
    }

    func snapshot() -> AgentSnapshot {
        let signals = SessionSignalStore(home: home).counts()
        var warnings = signals.warnings
        guard let processes = ProcessTable.scan() else {
            return AgentSnapshot(codex: 0, claude: 0, additional: signals.agents,
                warnings: warnings + ["프로세스 상태를 읽지 못함"])
        }
        let live = processes.live
        var files: [String] = []
        for pid in processes.codex {
            if let open = ProcessTable.openFiles(pid) { files += open } else { warnings.append("Codex 프로세스 조회 실패") }
        }
        let paths = Self.openRollouts(files)
        logs.prune(keeping: paths)
        var codex = 0
        for path in paths {
            do {
                let state = try logs.state(at: URL(fileURLWithPath: path))
                if state == .active { codex += 1 }
                if state == .unknown { warnings.append("Codex 상태 미확인") }
            } catch {
                // The session may have ended between listing and reading.
                if FileManager.default.fileExists(atPath: path) { warnings.append("Codex 기록 읽기 실패") }
            }
        }
        var claudeIDs = Set<String>()
        let directory = home.appendingPathComponent(".claude/sessions")
        if FileManager.default.fileExists(atPath: directory.path) {
            do {
                for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    where file.pathExtension == "json" {
                    guard let data = try? Data(contentsOf: file) else { continue }
                    if let id = Self.workingClaude(data, livePIDs: live) { claudeIDs.insert(id) }
                }
            } catch { warnings.append("Claude 상태 읽기 실패") }
        }
        return AgentSnapshot(codex: codex, claude: claudeIDs.count, additional: signals.agents,
            warnings: Array(Set(warnings)).sorted())
    }
}
