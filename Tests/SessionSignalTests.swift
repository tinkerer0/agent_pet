import Foundation
import Darwin

@main struct SessionSignalTests {
    static func main() throws {
        func check(_ condition: Bool) { precondition(condition) }
        func signal(_ provider: String, _ payload: [String: Any]) throws -> HookSignal? {
            HookSignal.parse(provider: provider, data: try JSONSerialization.data(withJSONObject: payload))
        }
        let session = "fixture-session"
        for (provider, field, begin, end) in [
            ("grok", "hookEventName", "user_prompt_submit", "stop_cancelled"),
            ("cursor", "hook_event_name", "beforeSubmitPrompt", "stop"),
            ("cline", "hookName", "agent_start", "agent_abort"),
            ("gemini", "hook_event_name", "BeforeAgent", "AfterAgent")
        ] {
            let idKey = provider == "cursor" ? "conversation_id" : provider == "cline" ? "taskId" : "session_id"
            check(try signal(provider, [field: begin, idKey: session]) == HookSignal(session: session, busy: true))
            check(try signal(provider, [field: end, idKey: session]) == HookSignal(session: session, busy: false))
            check(try signal(provider, [field: "unknown", idKey: session]) == nil)
        }
        check(try signal("grok", ["sessionId": session, "hook_event_name": "Stop", "subagentType": "worker"]) == nil)
        check(try signal("grok", ["sessionId": session, "prompt": "UserPromptSubmit"]) == nil)
        for status in ["busy", "retry", "idle"] {
            let parsed = try signal("opencode", ["type": "session.status", "properties": ["sessionID": session, "status": ["type": status]]])
            precondition(parsed == HookSignal(session: session, busy: status != "idle"))
        }
        check(try signal("opencode", ["type": "session.status", "properties": ["sessionID": session, "status": ["type": "unknown"]]]) == nil)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SessionSignalStore(directory: directory)
        let owner = ProcessIdentity.read(getpid())!
        try store.record(provider: "grok", session: session, busy: true, owner: owner)
        try store.record(provider: "grok", session: session, busy: true, owner: owner)
        try store.record(provider: "my-agent", session: "../../private-prompt\n", busy: true, owner: owner)
        precondition(store.counts().agents == ["grok": 1, "my-agent": 1])
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files where file.pathExtension == "json" {
            let data = try Data(contentsOf: file)
            let text = String(decoding: data, as: UTF8.self)
            precondition(!text.contains(session) && !text.contains("private-prompt"))
            precondition(file.lastPathComponent.count == 69)
            let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
            precondition((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        precondition(store.counts(identity: { _ in nil }).agents.isEmpty)
        precondition(store.counts(identity: { _ in ProcessIdentity(pid: owner.pid, parent: owner.parent, started: owner.started + 1, executable: owner.executable) }).agents.isEmpty)
        try store.record(provider: "grok", session: session, busy: false, owner: owner)
        precondition(store.counts().agents == ["my-agent": 1])
        for invalid in ["codex", "claude", "../escape", "bad\n", "UPPER", ""] {
            precondition(!SessionSignalStore.validProvider(invalid))
        }
        try Data("{}".utf8).write(to: directory.appendingPathComponent("broken.json"))
        precondition(!store.counts().warnings.isEmpty)
        let snapshot = AgentSnapshot(codex: 2, claude: 3, additional: ["grok": 4, "my-agent": 1], warnings: [])
        precondition(snapshot.total == 10 && snapshot.summary.contains("Grok 4"))
        let quotedPath = "/tmp/owner's app/AgentPet"
        for provider in ["grok", "cursor", "gemini"] {
            let config = SessionSignalCLI.hookConfig(provider: provider, executable: quotedPath)!
            check((try JSONSerialization.jsonObject(with: Data(config.utf8))) is [String: Any])
        }
        print("PASS: five provider event formats, custom providers, deduplication, hashed metadata, dead/reused PIDs, idle cleanup, malformed input, total counts")
    }
}
