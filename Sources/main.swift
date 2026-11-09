import AppKit

if let code = SessionSignalCLI.handle(Array(CommandLine.arguments.dropFirst())) {
    exit(code)
} else if CommandLine.arguments.contains("--status") {
    let snapshot = AgentMonitor().snapshot()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    if let data = try? encoder.encode(snapshot) { print(String(decoding: data, as: UTF8.self)) }
} else {
    // AppKit only applies the picker mask before the shared panel is created.
    NSColorPanel.setPickerMask([.wheelModeMask, .crayonModeMask])
    NSColorPanel.setPickerMode(.wheel)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
