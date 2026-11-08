import AppKit

@main struct ColorActionTests {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let delegate = AppDelegate()
        app.delegate = delegate

        // NSColorWell.activate sends the system color panel's default action
        // through the responder chain before the well's own action. It must not
        // reach a handler that expects NSColorWell.tag from an NSColorPanel.
        let panel = NSColorPanel.shared
        let systemAction = NSSelectorFromString("changeColor:")
        precondition(!app.sendAction(systemAction, to: nil, from: panel))
        print("PASS: system color-panel action does not enter the pet color-well handler")

        // Ignore an unexpected sender even when explicitly targeting our action.
        precondition(app.sendAction(NSSelectorFromString("changePetColor:"), to: delegate, from: panel))
        print("PASS: pet color action safely ignores a non-well sender")
    }
}
