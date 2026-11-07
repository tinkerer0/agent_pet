import AppKit

if CommandLine.arguments.contains("--status") {
    let snapshot = AgentMonitor().snapshot()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(snapshot) { print(String(decoding: data, as: UTF8.self)) }
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
