import AppKit

final class MotionSettingsPanel: NSPanel, NSTextFieldDelegate {
    var onApply: ((StageThresholds) -> Void)?
    private let presets = NSPopUpButton(frame: .zero, pullsDown: false)
    private var fields: [NSTextField] = []
    private var steppers: [NSStepper] = []
    private let message = NSTextField(wrappingLabelWithString: "같은 수이면 더 강한 모션을 표시합니다.")

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 350, height: 350),
            styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        title = "모션 기준"
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(NSTextField(labelWithString: "각 모션이 시작되는 작업 수를 정해요."))
        presets.addItems(withTitles: ["3개에서 큰 불꽃", "5개에서 큰 불꽃", "10개에서 큰 불꽃 · 기본", "직접 설정"])
        presets.target = self
        presets.action = #selector(selectPreset(_:))
        presets.setAccessibilityLabel("모션 기준 프리셋")
        stack.addArrangedSubview(presets)
        for (index, stage) in StageThresholds.stages.enumerated() {
            let label = NSTextField(labelWithString: stage.title)
            label.widthAnchor.constraint(equalToConstant: 130).isActive = true
            let field = NSTextField(string: "")
            field.tag = index
            field.alignment = .right
            field.delegate = self
            field.setAccessibilityLabel(stage.title + " 시작 세션 수")
            field.widthAnchor.constraint(equalToConstant: 48).isActive = true
            fields.append(field)
            let stepper = NSStepper()
            stepper.tag = index
            stepper.minValue = 1
            stepper.maxValue = 99
            stepper.increment = 1
            stepper.valueWraps = false
            stepper.target = self
            stepper.action = #selector(step(_:))
            stepper.setAccessibilityLabel(stage.title + " 세션 수 조절")
            steppers.append(stepper)
            let row = NSStackView(views: [label, field, stepper, NSTextField(labelWithString: "개부터")])
            row.alignment = .centerY
            row.spacing = 8
            stack.addArrangedSubview(row)
        }
        message.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        message.textColor = .secondaryLabelColor
        message.widthAnchor.constraint(equalToConstant: 310).isActive = true
        stack.addArrangedSubview(message)
        let idle = NSTextField(labelWithString: "0개일 때는 항상 쉬어요. 변경 후 적용을 누르세요.")
        idle.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        idle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(idle)
        let apply = NSButton(title: "적용", target: self, action: #selector(applySettings))
        apply.bezelStyle = .rounded
        stack.addArrangedSubview(apply)
        contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView!.leadingAnchor, constant: 20),
            stack.topAnchor.constraint(equalTo: contentView!.topAnchor, constant: 20),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: contentView!.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(greaterThanOrEqualTo: contentView!.bottomAnchor, constant: 20)
        ])
        configure(.standard)
        center()
    }
    func configure(_ thresholds: StageThresholds) {
        for (index, value) in thresholds.starts.enumerated() {
            fields[index].integerValue = value
            steppers[index].integerValue = value
        }
        presets.selectItem(at: StageThresholds.presets.firstIndex(of: thresholds) ?? 3)
        message.stringValue = "같은 수이면 더 강한 모션을 표시합니다."
    }
    @objc private func selectPreset(_ sender: NSPopUpButton) {
        guard StageThresholds.presets.indices.contains(sender.indexOfSelectedItem) else { return }
        makeFirstResponder(nil)
        configure(StageThresholds.presets[sender.indexOfSelectedItem])
    }
    @objc private func step(_ sender: NSStepper) {
        makeFirstResponder(nil)
        fields[sender.tag].integerValue = sender.integerValue
        presets.selectItem(at: 3)
        message.stringValue = "같은 수이면 더 강한 모션을 표시합니다."
    }
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              fields.indices.contains(field.tag) else { return }
        if let value = Int(field.stringValue), (1...99).contains(value) { steppers[field.tag].integerValue = value }
        presets.selectItem(at: 3)
    }
    @objc private func applySettings() {
        makeFirstResponder(nil)
        let values = fields.compactMap { Int($0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard values.count == fields.count, values.allSatisfy({ (1...99).contains($0) }) else {
            message.stringValue = "1~99 사이의 정수를 입력해 주세요."
            return
        }
        guard let thresholds = StageThresholds(starts: values) else {
            message.stringValue = "위에서 아래로 같거나 큰 수를 입력해 주세요."
            return
        }
        onApply?(thresholds)
        configure(thresholds)
        message.stringValue = "저장했습니다. 실제 작업 수에 바로 적용됩니다."
    }
}
