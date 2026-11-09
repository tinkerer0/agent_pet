import AppKit

struct SpriteMetadata: Decodable {
    let width: Int
    let height: Int
    let durations: [Int]
}

struct SpriteLoop {
    let width: Int
    let height: Int
    let frames: [CGImage]
    let durations: [TimeInterval]
    /// Per-frame hit mask, rows from the top; true where alpha > 0.1.
    private let opaque: [[Bool]]

    init(name: String, resources: URL, colors: PetColors = .standard) throws {
        let metadata = try JSONDecoder().decode(SpriteMetadata.self,
            from: Data(contentsOf: resources.appendingPathComponent(name + ".json")))
        guard let atlas = NSImage(contentsOf: resources.appendingPathComponent(name + "-atlas.png")),
              let original = atlas.cgImage(forProposedRect: nil, context: nil, hints: nil),
              !metadata.durations.isEmpty, metadata.width == Int(PetAppearance.canvasSize.width),
              metadata.height == Int(PetAppearance.canvasSize.height),
              original.width == metadata.width * metadata.durations.count, original.height == metadata.height,
              metadata.durations.allSatisfy({ $0 > 0 }) else { throw ProbeError.command("Invalid sprite: \(name)") }
        let cg = try colors.recolor(original)
        frames = try metadata.durations.indices.map { index in
            guard let cropped = cg.cropping(to: CGRect(x: index * metadata.width, y: 0,
                                                    width: metadata.width, height: metadata.height)) else {
                throw ProbeError.command("Invalid frame: \(name)")
            }
            return name == "rush" ? try RushEmbers.render(on: cropped, frame: index, colors: colors) : cropped
        }
        opaque = try frames.map(Self.opaquePixels)
        width = metadata.width
        height = metadata.height
        durations = metadata.durations.map { Double($0) / 1000 }
    }

    func isOpaque(frame: Int, x: Int, y: Int) -> Bool {
        (0..<width).contains(x) && (0..<height).contains(y) && opaque[frame][y * width + x]
    }

    private static func opaquePixels(_ image: CGImage) throws -> [Bool] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw ProbeError.command("Alpha context unavailable")
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        // 25/255 < 0.1 < 26/255: same cut as the previous NSColor.alphaComponent > 0.1 test.
        return Swift.stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] > 25 }
    }
}

/// Small sparks rise through the space above the flame; the source atlas stays intact.
enum RushEmbers {
    static func render(on frameImage: CGImage, frame: Int, colors: PetColors) throws -> CGImage {
        let width = frameImage.width, height = frameImage.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: frameImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ProbeError.command("Ember context unavailable")
        }
        context.draw(frameImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.setShouldAntialias(false)
        let light = PetRGB(colors.replacements[0x6dc9ff]!)
        let core = PetRGB(colors.replacements[0xd9fbff]!)
        for (x, offset, drift) in [(17, 0, -2), (23, 5, 1), (29, 10, 2), (21, 15, -1)] {
            let age = (frame + 21 - offset) % 21
            guard age < 9 else { continue }
            let column = x + Int((Double(age * drift) / 8).rounded())
            let top = 9 - age
            let alpha: CGFloat = age < 5 ? 0.95 : CGFloat(9 - age) / 5
            context.setFillColor((age < 3 ? core : light).color.withAlphaComponent(alpha).cgColor)
            context.fill(CGRect(x: column, y: height - top - 1, width: 1, height: 1))
            if age < 3 {
                context.setFillColor(colors.fire.color.withAlphaComponent(0.4).cgColor)
                context.fill(CGRect(x: column, y: height - top - 2, width: 1, height: 1))
            }
        }
        guard let result = context.makeImage() else { throw ProbeError.command("Ember image unavailable") }
        return result
    }
}

final class PetView: NSView {
    var menuProvider: (() -> NSMenu)?
    var onMoveEnded: (() -> Void)?
    private var loops: [PetStage: SpriteLoop]
    private let resources: URL
    private var colors: PetColors
    private var stage: PetStage = .idle
    private var frameIndex = 0
    private var animationTimer: Timer?
    private var pointerTimer: Timer?
    private var suspended = false
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var inMenu = false
    private var activeLoop: SpriteLoop? { loops[stage] }

    init(resources: URL, frame: NSRect, colors: PetColors = .standard) throws {
        self.resources = resources
        self.colors = colors
        loops = try Self.loadLoops(resources: resources, colors: colors)
        super.init(frame: frame)
        // Frames go straight to the layer and the compositor scales them with
        // nearest-neighbour filtering, so no frame is redrawn on the CPU.
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layerContentsPlacement = .scaleAxesIndependently
        layer?.magnificationFilter = .nearest
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("AgentPet")
        setSuspended(false)
    }
    required init?(coder: NSCoder) { nil }

    private static func loadLoops(resources: URL, colors: PetColors) throws -> [PetStage: SpriteLoop] {
        var loops: [PetStage: SpriteLoop] = [:]
        for stage in PetStage.allCases {
            loops[stage] = try SpriteLoop(name: stage.asset, resources: resources, colors: colors)
        }
        return loops
    }

    func setColors(_ next: PetColors) throws {
        guard next != colors else { return }
        loops = try Self.loadLoops(resources: resources, colors: next)
        colors = next
        needsDisplay = true
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
        pointerTimer?.invalidate()
        pointerTimer = nil
        if !value {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.updateMousePassThrough() }
            timer.tolerance = 0.02
            RunLoop.main.add(timer, forMode: .common)
            pointerTimer = timer
        }
        scheduleFrame()
    }

    private func scheduleFrame() {
        animationTimer?.invalidate()
        guard !suspended,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let loop = activeLoop, loop.frames.count > 1 else { return }
        let timer = Timer(timeInterval: loop.durations[frameIndex], repeats: false) { [weak self] _ in
            guard let self, let loop = self.activeLoop else { return }
            self.frameIndex = (self.frameIndex + 1) % loop.frames.count
            self.needsDisplay = true
            self.scheduleFrame()
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    var currentFrame: CGImage? { activeLoop?.frames[frameIndex] }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() { layer?.contents = currentFrame }

    private func updateMousePassThrough() {
        guard let window, dragStart == nil, !inMenu, let loop = activeLoop else { return }
        let point = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let x = Int(floor((point.x - bounds.minX) * CGFloat(loop.width) / bounds.width))
        let y = Int(floor((bounds.maxY - point.y) * CGFloat(loop.height) / bounds.height))
        let ignore = !loop.isOpaque(frame: frameIndex, x: x, y: y)
        if window.ignoresMouseEvents != ignore { window.ignoresMouseEvents = ignore }
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
