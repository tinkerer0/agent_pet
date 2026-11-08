import Foundation
import Darwin
import CryptoKit

struct ProcessIdentity: Equatable {
    let pid: Int32
    let parent: Int32
    let started: UInt64
    let executable: String

    static func read(_ pid: Int32) -> ProcessIdentity? {
        guard pid > 1 else { return nil }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_status != SZOMB else { return nil }
        // PROC_PIDPATHINFO_MAXSIZE is a C macro Swift cannot import.
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        return ProcessIdentity(pid: pid, parent: Int32(info.pbi_ppid),
            started: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec,
            executable: String(cString: path))
    }

    static func hookOwner(provider: String) -> ProcessIdentity? {
        var pid = getppid()
        var runtime: ProcessIdentity?
        for _ in 0..<16 {
            guard let process = read(pid) else { break }
            let name = URL(fileURLWithPath: process.executable).lastPathComponent.lowercased()
            let matches: Bool
            switch provider {
            case "grok": matches = name == "grok" || name.hasPrefix("grok-")
            case "cursor": matches = name == "cursor-agent" || process.executable.contains("/cursor-agent/") || process.executable.contains("/Cursor.app/")
            case "cline": matches = name == "cline" || name == "cline-core"
            case "gemini": matches = name == "gemini"
            case "opencode": matches = name == "opencode"
            default: matches = false
            }
            if matches { return process }
            if runtime == nil, ["node", "bun"].contains(name), provider != "grok" { runtime = process }
            guard process.parent != pid else { break }
            pid = process.parent
        }
        return runtime
    }
}

struct SessionSignal: Codable {
    let version: Int
    let provider: String
    let sessionKey: String
    let pid: Int32
    let processStarted: UInt64
    let updatedAt: TimeInterval
}

struct HookSignal: Equatable {
    let session: String
    let busy: Bool

    static func parse(provider: String, data: Data) -> HookSignal? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var session = object["session_id"] as? String ?? object["sessionId"] as? String
            ?? object["conversation_id"] as? String ?? object["taskId"] as? String
        let rawEvent = object["hook_event_name"] as? String ?? object["hookEventName"] as? String
            ?? object["hookName"] as? String ?? ""
        let event = rawEvent.lowercased().filter { $0.isLetter }
        let busy: Bool
        switch provider {
        case "grok":
            // A child's stop must never clear its parent's state.
            guard object["subagentType"] == nil, object["subagent_type"] == nil else { return nil }
            switch event {
            case "userpromptsubmit", "pretooluse", "posttooluse", "posttoolusefailure": busy = true
            case "stop", "stopfailure", "stopcancelled", "sessionend": busy = false
            default: return nil
            }
        case "cursor":
            switch event {
            case "beforesubmitprompt", "pretooluse", "posttooluse", "afteragentthought": busy = true
            case "stop", "sessionend": busy = false
            default: return nil
            }
        case "cline":
            switch event {
            case "taskstart", "taskresume", "userpromptsubmit", "pretooluse", "posttooluse",
                 "agentstart", "agentresume", "promptsubmit", "toolcall", "toolresult": busy = true
            case "taskcomplete", "taskcancel", "taskerror", "sessionshutdown", "agentend", "agentabort", "agenterror": busy = false
            default: return nil
            }
        case "gemini":
            switch event {
            case "beforeagent", "beforetool": busy = true
            case "afteragent", "sessionend": busy = false
            default: return nil
            }
        case "opencode":
            guard let properties = object["properties"] as? [String: Any],
                  let type = object["type"] as? String else { return nil }
            session = properties["sessionID"] as? String
            switch type {
            case "session.status":
                guard let status = properties["status"] as? [String: Any], let type = status["type"] as? String,
                      ["busy", "retry", "idle"].contains(type) else { return nil }
                busy = type != "idle"
            case "session.idle", "session.error": busy = false
            case "session.deleted":
                session = (properties["info"] as? [String: Any])?["id"] as? String
                busy = false
            default: return nil
            }
        default: return nil
        }
        guard let session, !session.isEmpty, session.utf8.count <= 1024 else { return nil }
        return HookSignal(session: session, busy: busy)
    }
}

struct SessionSignalStore {
    let directory: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, directory: URL? = nil) {
        self.directory = directory ?? ProcessInfo.processInfo.environment["AGENT_PET_STATE_DIR"].map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent("Library/Application Support/AgentPet/sessions", isDirectory: true)
    }

    static func validProvider(_ provider: String) -> Bool {
        provider.range(of: "\\A[a-z][a-z0-9-]{0,31}\\z", options: .regularExpression) != nil
            && !["codex", "claude"].contains(provider)
    }

    func record(provider: String, session: String, busy: Bool, owner: ProcessIdentity) throws {
        guard Self.validProvider(provider), !session.isEmpty, session.utf8.count <= 1024,
              let live = ProcessIdentity.read(owner.pid), live.started == owner.started else {
            throw ProbeError.command("Invalid session signal")
        }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw ProbeError.command("Invalid state directory")
        }
        let lock = open(directory.appendingPathComponent(".lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw ProbeError.command("State lock unavailable") }
        defer { close(lock) }
        let deadline = ProcessInfo.processInfo.systemUptime + 0.2
        while flock(lock, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK, ProcessInfo.processInfo.systemUptime < deadline else {
                throw ProbeError.command("State store busy")
            }
            usleep(5_000)
        }
        defer { flock(lock, LOCK_UN) }
        let key = SHA256.hash(data: Data((provider + "\u{0}" + session).utf8)).map { String(format: "%02x", $0) }.joined()
        let file = directory.appendingPathComponent(key + ".json")
        guard (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw ProbeError.command("Invalid state file")
        }
        if !busy {
            // An old process finishing after a resume cannot erase the new owner.
            if let data = try? Data(contentsOf: file), let previous = try? JSONDecoder().decode(SessionSignal.self, from: data),
               previous.pid == owner.pid, previous.processStarted == owner.started {
                try manager.removeItem(at: file)
            }
            return
        }
        let signal = SessionSignal(version: 1, provider: provider, sessionKey: key, pid: owner.pid,
            processStarted: owner.started, updatedAt: Date().timeIntervalSince1970)
        try JSONEncoder().encode(signal).write(to: file, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    func counts(identity: (Int32) -> ProcessIdentity? = ProcessIdentity.read) -> (agents: [String: Int], warnings: [String]) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return ([:], []) }
        guard (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            return ([:], ["추가 에이전트 상태 경로 미확인"])
        }
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]) else {
            return ([:], ["추가 에이전트 상태 읽기 실패"])
        }
        var sessions: [String: Set<String>] = [:]
        var invalid = false
        for file in files where file.pathExtension == "json" {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? 0) <= 16_384,
                  let data = try? Data(contentsOf: file),
                  let signal = try? JSONDecoder().decode(SessionSignal.self, from: data),
                  signal.version == 1, Self.validProvider(signal.provider),
                  signal.sessionKey.count == 64, file.lastPathComponent == signal.sessionKey + ".json" else {
                invalid = true
                continue
            }
            guard let live = identity(signal.pid), live.started == signal.processStarted else { continue }
            sessions[signal.provider, default: []].insert(signal.sessionKey)
        }
        return (sessions.mapValues(\.count), invalid ? ["추가 에이전트 상태 형식 미확인"] : [])
    }
}

enum SessionSignalCLI {
    static func handle(_ arguments: [String]) -> Int32? {
        guard let mode = arguments.first, ["--hook", "--signal", "--hook-config", "--help"].contains(mode) else { return nil }
        func argument(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        if mode == "--help" {
            print("""
            AgentPet --status
            AgentPet --hook-config grok|cursor|cline|gemini|opencode
            AgentPet --hook <provider> [--pid <owner-pid>] < event.json
            AgentPet --signal <provider> <session-id> busy|idle --pid <owner-pid>

            --hook-config는 연결 예시만 출력하며 다른 도구의 설정을 수정하지 않습니다.
            추가 도구는 로컬 시작·종료 이벤트를 연결해야 감지합니다.
            """)
            return 0
        }
        guard arguments.count >= 2 else { return mode == "--hook" ? hookFailure() : 1 }
        let provider = arguments[1]
        if mode == "--hook-config" {
            guard let config = hookConfig(provider: provider, executable: URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path) else { return 1 }
            print(config)
            return 0
        }
        do {
            let signal: HookSignal
            if mode == "--hook" {
                var data = Data()
                while let chunk = try FileHandle.standardInput.read(upToCount: 65_536), !chunk.isEmpty {
                    data.append(chunk)
                    guard data.count <= 8_388_608 else { return hookFailure() }
                }
                guard let event = HookSignal.parse(provider: provider, data: data) else { print("{}"); return 0 }
                signal = event
            } else {
                guard arguments.count >= 4, ["busy", "idle"].contains(arguments[3]) else { return 1 }
                signal = HookSignal(session: arguments[2], busy: arguments[3] == "busy")
            }
            let explicitPID = argument(after: "--pid").flatMap(Int32.init)
            if arguments.contains("--pid"), explicitPID == nil { throw ProbeError.command("Invalid PID") }
            guard let owner = explicitPID.flatMap(ProcessIdentity.read) ?? (mode == "--hook" && explicitPID == nil ? ProcessIdentity.hookOwner(provider: provider) : nil) else {
                throw ProbeError.command("Session owner unavailable")
            }
            try SessionSignalStore().record(provider: provider, session: signal.session, busy: signal.busy, owner: owner)
            if mode == "--hook" { print("{}") }
            return 0
        } catch {
            if mode == "--hook" { return hookFailure() }
            FileHandle.standardError.write(Data("AgentPet: 유효한 provider·session·owner PID가 필요합니다.\n".utf8))
            return 1
        }
    }

    private static func hookFailure() -> Int32 {
        // A cosmetic integration must not block or alter the agent's work.
        FileHandle.standardError.write(Data("AgentPet: 세션 신호를 기록하지 못했습니다.\n".utf8))
        print("{}")
        return 0
    }

    static func hookConfig(provider: String, executable: String) -> String? {
        let quoted = "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let command = quoted + " --hook " + provider
        let events: [String]
        switch provider {
        case "grok": events = ["UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "StopFailure", "StopCancelled", "SessionEnd"]
        case "cursor": events = ["beforeSubmitPrompt", "preToolUse", "postToolUse", "afterAgentThought", "stop", "sessionEnd"]
        case "gemini": events = ["BeforeAgent", "BeforeTool", "AfterAgent", "SessionEnd"]
        case "cline": return "#!/bin/sh\nexec " + command + "\n"
        case "opencode":
            guard let encoded = try? JSONEncoder().encode(executable), let binary = String(data: encoded, encoding: .utf8) else { return nil }
            return """
            import { spawn } from 'node:child_process';
            export const AgentPet = async () => ({
              event: async ({ event }) => {
                if (!['session.status', 'session.idle', 'session.error', 'session.deleted'].includes(event.type)) return;
                await new Promise(resolve => {
                  const child = spawn(\(binary), ['--hook', 'opencode', '--pid', String(process.pid)], { stdio: ['pipe', 'ignore', 'ignore'] });
                  const timer = setTimeout(() => { child.kill(); resolve(); }, 1500);
                  const done = () => { clearTimeout(timer); resolve(); };
                  child.on('error', done);
                  child.on('close', done);
                  child.stdin.on('error', () => {});
                  child.stdin.end(JSON.stringify(event));
                });
              }
            });
            """
        default: return nil
        }
        var hooks: [String: Any] = [:]
        for event in events {
            hooks[event] = provider == "cursor" ? [["command": command]]
                : [["hooks": [["type": "command", "command": command]]]]
        }
        var root: [String: Any] = ["hooks": hooks]
        if provider == "cursor" { root["version"] = 1 }
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }
}
