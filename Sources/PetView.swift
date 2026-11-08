import AppKit

struct SpriteMetadata: Decodable {
    let width: Int
    let height: Int
    let durations: [Int]
}

struct SpriteLoop {
    let width: Int
    let height: Int
    let images: [NSImage]
    let bitmaps: [NSBitmapImageRep]
    let durations: [TimeInterval]

    init(name: String, resources: URL, colors: PetColors = .standard) throws {
        let metadata = try JSONDecoder().decode(SpriteMetadata.self,
            from: Data(contentsOf: resources.appendingPathComponent(name + ".json")))
        let expected = name.hasPrefix("together-") ? NSSize(width: 96, height: 48) : NSSize(width: 48, height: 42)
        guard let atlas = NSImage(contentsOf: resources.appendingPathComponent(name + "-atlas.png")),
              let original = atlas.cgImage(forProposedRect: nil, context: nil, hints: nil),
              !metadata.durations.isEmpty, metadata.width == Int(expected.width), metadata.height == Int(expected.height),
              original.width == metadata.width * metadata.durations.count, original.height == metadata.height,
              metadata.durations.allSatisfy({ $0 > 0 }) else { throw ProbeError.command("Invalid sprite: \(name)") }
        let cg = try colors.recolor(original)
        var images: [NSImage] = []
        var bitmaps: [NSBitmapImageRep] = []
        for index in metadata.durations.indices {
            guard let frame = cg.cropping(to: CGRect(x: index * metadata.width, y: 0,
                                                    width: metadata.width, height: metadata.height)) else {
                throw ProbeError.command("Invalid frame: \(name)")
            }
            images.append(NSImage(cgImage: frame, size: NSSize(width: metadata.width, height: metadata.height)))
            bitmaps.append(NSBitmapImageRep(cgImage: frame))
        }
        self.images = images
        self.bitmaps = bitmaps
        width = metadata.width
        height = metadata.height
        durations = metadata.durations.map { Double($0) / 1000 }
    }
}

final class PetView: NSView {
    var menuProvider: (() -> NSMenu)?
    var onMoveEnded: (() -> Void)?
    private var loops: [String: SpriteLoop] = [:]
    private let resources: URL
    private var colors: PetColors = .standard
    private var stage: PetStage = .idle
    private var petAppearance: PetAppearance = .claude
    private var frameIndex = 0
    private var animationTimer: Timer?
    private var pointerTimer: Timer?
    private var suspended = false
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var inMenu = false
    private var activeLoop: SpriteLoop? { loops[petAppearance.assetPrefix + stage.asset] }

    init(resources: URL, frame: NSRect) throws {
        self.resources = resources
        super.init(frame: frame)
        for prefix in PetAppearance.allCases.map(\.assetPrefix) {
            for name in ["idle", "calm", "steady", "busy", "heated", "rush"] {
                loops[prefix + name] = try SpriteLoop(name: prefix + name, resources: resources)
            }
        }
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("AgentPet")
        pointerTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.updateMousePassThrough() }
        RunLoop.main.add(pointerTimer!, forMode: .common)
    }
    required init?(coder: NSCoder) { nil }

    func setColors(_ next: PetColors) throws {
        guard next != colors else { return }
        var updated: [String: SpriteLoop] = [:]
        for stage in PetStage.allCases {
            updated[stage.asset] = try SpriteLoop(name: stage.asset, resources: resources, colors: next)
        }
        loops = updated
        colors = next
        needsDisplay = true
    }

    func setPetAppearance(_ next: PetAppearance) {
        petAppearance = next
        frameIndex = 0
        needsDisplay = true
        scheduleFrame()
    }

    func setStage(_ next: PetStage) {
        guard next != stage else { return }
        stage = next
        frameIndex = 0
        needsDisplay = true
        scheduleFrame()
    }

    func setSuspended(_ value: Bool) {
        suspended = value
        scheduleFrame()
    }

    private func scheduleFrame() {
        animationTimer?.invalidate()
        guard !suspended,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let loop = activeLoop, loop.images.count > 1 else { return }
        let timer = Timer(timeInterval: loop.durations[frameIndex], repeats: false) { [weak self] _ in
            guard let self, let loop = self.activeLoop else { return }
            self.frameIndex = (self.frameIndex + 1) % loop.images.count
            self.needsDisplay = true
            self.scheduleFrame()
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.imageInterpolation = .none
        activeLoop?.images[frameIndex].draw(in: bounds, from: .zero,
                operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
    }

    private func updateMousePassThrough() {
        guard let window, dragStart == nil, !inMenu else { return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        guard let loop = activeLoop else { return }
        let x = Int(floor((point.x - bounds.minX) * CGFloat(loop.width) / bounds.width))
        let y = Int(floor((bounds.maxY - point.y) * CGFloat(loop.height) / bounds.height))
        let opaque = (0..<loop.width).contains(x) && (0..<loop.height).contains(y)
            && (loop.bitmaps[frameIndex].colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1
        window.ignoresMouseEvents = !opaque
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event); return }
        dragStart = (NSEvent.mouseLocation, window.frame.origin)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let start = dragStart else { return }
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x,
                                      y: start.origin.y + mouse.y - start.mouse.y))
    }
    override func mouseUp(with event: NSEvent) {
        dragStart = nil
        onMoveEnded?()
    }
    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        inMenu = true
        NSMenu.popUpContextMenu(menu, with: event, for: self)
        inMenu = false
    }
}
