import AppKit

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: PetPanel!
    private var pet: PetView!
    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?
    private let monitor = AgentMonitor()
    private let queue = DispatchQueue(label: "AgentPet.monitor", qos: .utility)
    private var polling = false
    private var snapshot: AgentSnapshot?
    private var gate = StageGate()
    private var preview: Int?
    private var sleeping = false
    private var scale = 5
    private let appearance: PetAppearance = .claude
    private var colors = PetColors.load()
    private var colorWindow: NSPanel?
    private var colorWells: [PetColorPart: NSColorWell] = [:]
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if others.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        let savedScale = UserDefaults.standard.integer(forKey: "pixelScale")
        if (3...8).contains(savedScale) { scale = savedScale }
        let size = appearance.size(forPreset: scale)
        do {
            pet = try PetView(resources: Bundle.main.resourceURL!, frame: NSRect(origin: .zero, size: size))
            try pet.setColors(colors)
        } catch {
            let alert = NSAlert()
            alert.messageText = "AgentPet 에셋을 열지 못했어요"
            alert.informativeText = "빌드 스크립트로 앱을 다시 만들어 주세요."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        panel = PetPanel(contentRect: NSRect(origin: initialOrigin(size: size), size: size),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "AgentPet"
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = pet
        pet.setPetAppearance(appearance)
        pet.menuProvider = { [weak self] in self?.makeMenu() ?? NSMenu() }
        pet.onMoveEnded = { [weak self] in self?.keepOnScreen(); self?.savePosition() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "terminal.fill", accessibilityDescription: "AgentPet")
        statusItem.button?.title = " …"
        statusItem.button?.imagePosition = .imageLeading
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        keepOnScreen()
        panel.orderFrontRegardless()
        watchScreenState()
        poll()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func poll() {
        guard !polling, !sleeping else { return }
        polling = true
        queue.async { [weak self] in
            guard let self else { return }
            let next = self.monitor.snapshot()
            DispatchQueue.main.async {
                self.polling = false
                self.snapshot = next
                self.updateAppearance()
            }
        }
    }

    private func updateAppearance() {
        guard let snapshot else { return }
        let count = preview ?? snapshot.total
        let stage = preview == nil ? gate.update(count: count, now: ProcessInfo.processInfo.systemUptime) : PetStage.forCount(count)
        pet.setStage(stage)
        let incomplete = !snapshot.warnings.isEmpty
        statusItem.button?.title = preview.map { " \($0) · 미리보기" }
            ?? (incomplete ? " ≥\(count)" : " \(count)")
        let summary = preview.map { "동작 미리보기: \($0)개" }
            ?? "작업 중 \(snapshot.total)개 · \(snapshot.summary)"
        pet.toolTip = summary + "\n드래그로 이동 · 우클릭으로 설정"
        pet.setAccessibilityLabel(appearance.title + " · " + summary)
        statusItem.button?.toolTip = summary + (incomplete ? "\n" + snapshot.warnings.joined(separator: " · ") : "")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let fresh = makeMenu()
        for item in fresh.items { fresh.removeItem(item); menu.addItem(item) }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        func label(_ text: String) { let item = NSMenuItem(title: text, action: nil, keyEquivalent: ""); item.isEnabled = false; menu.addItem(item) }
        label(snapshot.map { "작업 중 \($0.total)개 · \($0.summary)" } ?? "에이전트 상태 확인 중…")
        for warning in snapshot?.warnings ?? [] { label(warning) }
        menu.addItem(.separator())
        let automatic = NSMenuItem(title: "자동 · 실제 작업 수", action: #selector(useAutomatic), keyEquivalent: "")
        automatic.target = self
        automatic.state = preview == nil ? .on : .off
        menu.addItem(automatic)
        let demo = NSMenuItem(title: "동작 미리보기", action: nil, keyEquivalent: "")
        let demos = NSMenu()
        for (count, title) in [(0,"0개 · 휴식 zzz"),(1,"1개 · 여유"),(3,"3개 · 집중"),(5,"5개 · 머리에서 연기"),(7,"7~9개 · 불꽃"),(10,"10개 이상 · 폭주")] {
            let item = NSMenuItem(title: title, action: #selector(showPreview(_:)), keyEquivalent: "")
            item.tag = count
            item.target = self
            item.state = preview == count ? .on : .off
            demos.addItem(item)
        }
        demo.submenu = demos
        menu.addItem(demo)
        let editColors = NSMenuItem(title: "색상…", action: #selector(showColors), keyEquivalent: "")
        editColors.target = self
        menu.addItem(editColors)
        let sizes = NSMenuItem(title: "크기", action: nil, keyEquivalent: "")
        let sizeMenu = NSMenu()
        for (value, title) in [(4,"작게"),(5,"보통"),(6,"크게"),(8,"아주 크게")] {
            let item = NSMenuItem(title: title, action: #selector(resize(_:)), keyEquivalent: "")
            item.tag = value
            item.target = self
            item.state = scale == value ? .on : .off
            sizeMenu.addItem(item)
        }
        sizes.submenu = sizeMenu
        menu.addItem(sizes)
        let reset = NSMenuItem(title: "화면 오른쪽 아래로", action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "AgentPet 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    @objc private func useAutomatic() { preview = nil; gate = StageGate(); updateAppearance() }
    @objc private func showPreview(_ item: NSMenuItem) { preview = item.tag; updateAppearance() }
    @objc private func resize(_ item: NSMenuItem) {
        scale = item.tag
        UserDefaults.standard.set(scale, forKey: "pixelScale")
        resizePanel()
    }
    @objc private func showColors() {
        if colorWindow == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 270, height: 215),
                styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            window.title = "캐릭터 색상"
            window.isReleasedWhenClosed = false
            window.level = .floating
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 14
            stack.translatesAutoresizingMaskIntoConstraints = false
            for part in PetColorPart.allCases {
                let label = NSTextField(labelWithString: part.title)
                label.widthAnchor.constraint(equalToConstant: 140).isActive = true
                let well = NSColorWell(frame: .zero)
                well.tag = part.rawValue
                well.color = colors[part].color
                well.target = self
                well.action = #selector(changePetColor(_:))
                well.setAccessibilityLabel(part.title + " 색상")
                well.widthAnchor.constraint(equalToConstant: 70).isActive = true
                well.heightAnchor.constraint(equalToConstant: 28).isActive = true
                colorWells[part] = well
                let row = NSStackView(views: [label, well])
                row.spacing = 12
                row.alignment = .centerY
                stack.addArrangedSubview(row)
            }
            let reset = NSButton(title: "기본색으로 복원", target: self, action: #selector(resetColors))
            reset.bezelStyle = .rounded
            stack.addArrangedSubview(reset)
            window.contentView!.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20),
                stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20)
            ])
            window.center()
            colorWindow = window
        }
        NSColorPanel.shared.showsAlpha = false
        NSColorPanel.shared.isContinuous = true
        NSApp.activate(ignoringOtherApps: true)
        colorWindow?.makeKeyAndOrderFront(nil)
    }
    @objc private func changePetColor(_ sender: Any?) {
        guard let well = sender as? NSColorWell,
              let part = PetColorPart(rawValue: well.tag), let value = PetRGB(well.color) else { return }
        var next = colors
        next[part] = value
        applyColors(next)
    }
    @objc private func resetColors() {
        colorWells.values.forEach { $0.deactivate() }
        NSColorPanel.shared.orderOut(nil)
        applyColors(.standard)
    }
    private func applyColors(_ next: PetColors) {
        do {
            try pet.setColors(next)
            colors = next
            colors.save()
        } catch {
            NSSound.beep()
        }
        for (part, well) in colorWells { well.color = colors[part].color }
    }
    private func resizePanel() {
        let old = panel.frame
        let size = appearance.size(forPreset: scale)
        panel.setFrame(NSRect(x: old.midX - size.width / 2, y: old.minY, width: size.width, height: size.height), display: true)
        pet.frame = NSRect(origin: .zero, size: size)
        keepOnScreen()
        savePosition()
    }
    @objc private func resetPosition() {
        guard let screen = NSScreen.main else { return }
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - panel.frame.width - 24,
                                      y: screen.visibleFrame.minY + 24))
        savePosition()
    }
    private func initialOrigin(size: NSSize) -> NSPoint {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "originX") != nil {
            return NSPoint(x: defaults.double(forKey: "originX"), y: defaults.double(forKey: "originY"))
        }
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        return NSPoint(x: screen.maxX - size.width - 24, y: screen.minY + 24)
    }
    private func keepOnScreen() {
        guard let screen = NSScreen.screens.max(by: {
            $0.visibleFrame.intersection(panel.frame).area < $1.visibleFrame.intersection(panel.frame).area
        }) else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: max(visible.minX, min(panel.frame.minX, visible.maxX - panel.frame.width)),
                                      y: max(visible.minY, min(panel.frame.minY, visible.maxY - panel.frame.height))))
    }
    private func savePosition() {
        UserDefaults.standard.set(panel.frame.minX, forKey: "originX")
        UserDefaults.standard.set(panel.frame.minY, forKey: "originY")
    }
    private func watchScreenState() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.sleeping = true; self?.pet.setSuspended(true)
            })
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.sleeping = false; self?.pet.setSuspended(false); self?.poll()
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }; self.pet.setSuspended(self.sleeping)
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.keepOnScreen()
        })
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
