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

        let motion = MotionSettingsPanel()
        var applied: StageThresholds?
        motion.onApply = { applied = $0 }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let controls = descendants(motion.contentView!)
        let fields = controls.compactMap { $0 as? NSTextField }.filter(\.isEditable).sorted { $0.tag < $1.tag }
        let apply = controls.compactMap { $0 as? NSButton }.first { $0.title == "적용" }!
        let presets = controls.compactMap { $0 as? NSPopUpButton }.first!
        precondition(fields.count == 4)
        func submit() {
            precondition(app.sendAction(apply.action!, to: apply.target, from: apply))
        }
        presets.selectItem(at: 0)
        precondition(app.sendAction(presets.action!, to: presets.target, from: presets))
        submit()
        precondition(applied == StageThresholds.presets[0])
        applied = nil
        fields[0].stringValue = "2.5"
        submit()
        precondition(applied == nil)
        fields[0].stringValue = "5"
        submit()
        precondition(applied == nil)
        motion.configure(.standard)
        submit()
        precondition(applied == .standard)
        motion.contentView!.layoutSubtreeIfNeeded()
        for field in fields {
            precondition(!field.hasAmbiguousLayout && field.frame.width > 0 && field.frame.height > 0)
            precondition(motion.contentView!.bounds.contains(field.convert(field.bounds, to: motion.contentView)))
        }
        let applyRect = apply.convert(apply.bounds, to: motion.contentView)
        precondition(motion.contentView!.bounds.contains(applyRect))
        print("PASS: motion settings preset/apply actions, invalid input rejection and control layout")
    }
}
