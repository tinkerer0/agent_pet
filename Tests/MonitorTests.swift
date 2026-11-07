import Foundation

@main struct MonitorTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("rollout-test.jsonl")
        func event(_ type: String) -> String { "{\"type\":\"event_msg\",\"payload\":{\"type\":\"\(type)\"}}\n" }
        func write(_ text: String) throws { try Data(text.utf8).write(to: file) }
        let reader = CodexLogReader()
        func expect(_ expected: TurnState) throws {
            let actual = try reader.state(at: file)
            assert(actual == expected)
        }
        try write(event("task_started"))
        try expect(.active)
        func append(_ text: String) throws {
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        }
        try append("{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_comp")
        try expect(.active)
        try append("lete\"}}\n")
        try expect(.idle)
        try append(event("task_started"))
        try expect(.active)
        // Multi-megabyte tool output must not hide the turn's actual lifecycle.
        let tool = "{\"type\":\"response_item\",\"payload\":{\"text\":\"" + String(repeating: "x", count: 3_000_000) + "task_complete\"}}\n"
        try write(event("task_started") + tool)
        try expect(.active)
        try write(event("task_started") + tool + event("task_complete"))
        try expect(.idle)
        try write(event("task_started") + event("turn_aborted"))
        try expect(.idle)
        // Log truncation and incomplete writes are common during process exits.
        try write(event("task_started") + "{\"type\":\"event_msg\",\"payload\":")
        try expect(.active)
        try write("")
        try expect(.unknown)
        assert(CodexLogReader.lifecycle(Data("{\"type\":\"response_item\",\"payload\":{\"type\":\"task_started\"}}".utf8)) == nil)
        let path = "/Users/example/.codex/sessions/2026/11/07/rollout-test.jsonl"
        assert(AgentMonitor.openRollouts("p1\nn\(path)\np2\nn\(path)\nn/tmp/unrelated.jsonl") == [path])
        for (status, expected) in [("busy",true),("shell",true),("idle",false),("waiting",false)] {
            let data = Data("{\"pid\":12,\"sessionId\":\"a\",\"status\":\"\(status)\"}".utf8)
            assert((AgentMonitor.workingClaude(data, livePIDs: [12]) != nil) == expected)
            assert(AgentMonitor.workingClaude(data, livePIDs: []) == nil)
        }
        var gate = StageGate()
        assert(gate.update(count: 10, now: 0) == .rush)
        assert(gate.update(count: 3, now: 1) == .rush)
        assert(gate.update(count: 10, now: 2) == .rush)
        assert(gate.update(count: 3, now: 3) == .rush)
        assert(gate.update(count: 3, now: 7) == .steady)
        assert(gate.update(count: 7, now: 8) == .heated)
        print("PASS: lifecycle, long tool output, partial/truncated logs, deduplication, live Claude state, stage stability")
    }
}
