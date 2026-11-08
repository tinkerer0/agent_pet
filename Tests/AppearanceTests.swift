import AppKit

@main struct AppearanceTests {
    static func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: image.colorSpace!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    static func checkColors(resources: URL) throws {
        let suite = "AgentPet.ColorTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(PetColors.load(from: defaults) == .standard)
        let blackLime = PetColors(body: PetRGB(0), eyes: PetRGB(0xb9ff27), fire: PetRGB(0xff572d))
        blackLime.save(to: defaults)
        precondition(PetColors.load(from: defaults) == blackLime)
        defaults.set("invalid", forKey: PetColorPart.body.key)
        let recovered = PetColors.load(from: defaults)
        precondition(recovered.body == PetColors.standard.body && recovered.eyes == blackLime.eyes)
        PetColors.standard.save(to: defaults)
        precondition(PetColors.load(from: defaults) == .standard)
        precondition(PetRGB("#12ABef")?.hex == "#12abef" && PetRGB("#123456\n") == nil)
        let wide = NSColor(colorSpace: .extendedSRGB, components: [1.2, -0.1, 0.5, 1], count: 4)
        precondition(PetRGB(wide)?.hex == "#ff0080")

        let whiteBlue = PetColors(body: PetRGB(0xffffff), eyes: PetRGB(0x303f80), fire: PetRGB(0x00adff))
        for stage in PetStage.allCases {
            let source = NSImage(contentsOf: resources.appendingPathComponent(stage.asset + "-atlas.png"))!
                .cgImage(forProposedRect: nil, context: nil, hints: nil)!
            let original = rgba(source)
            let unchanged = try PetColors.standard.recolor(source)
            precondition(rgba(unchanged) == original)
            for (colors, expectedBody, expectedShadow) in [(blackLime, 0x1f1f1f, 0x000000), (whiteBlue, 0xffffff, 0xc7c7c7)] {
                let changed = rgba(try colors.recolor(source))
                var body = 0, eyes = 0, flames = 0
                for offset in stride(from: 0, to: original.count, by: 4) {
                    precondition(original[offset + 3] == changed[offset + 3], "Alpha changed: \(stage)")
                    let before = Int(original[offset]) << 16 | Int(original[offset + 1]) << 8 | Int(original[offset + 2])
                    let after = Int(changed[offset]) << 16 | Int(changed[offset + 1]) << 8 | Int(changed[offset + 2])
                    if original[offset + 3] < 255 {
                        precondition(before == after, "Transparent decoration changed: \(stage)")
                        continue
                    }
                    switch before {
                    case 0xd87656: precondition(after == expectedBody); body += 1
                    case 0xbe684d: precondition(after == expectedShadow)
                    case 0x000000: precondition(after == colors.eyes.value); eyes += 1
                    case 0x397bff: precondition(after == colors.fire.value); flames += 1
                    case 0x6dc9ff, 0xd9fbff: precondition(after != before)
                    default: precondition(before == after, "Unrelated pixel changed: \(stage)")
                    }
                }
                precondition(body > 0 && eyes > 0)
                if stage == .heated || stage == .rush { precondition(flames > 0) }
                let loop = try SpriteLoop(name: stage.asset, resources: resources, colors: colors)
                precondition(loop.images.count > 1)
            }
        }
        let view = try PetView(resources: resources, frame: NSRect(x: 0, y: 0, width: 144, height: 126))
        for colors in [blackLime, whiteBlue, .standard] {
            try view.setColors(colors)
            view.setStage(.rush)
            let image = NSImage(size: view.frame.size)
            image.lockFocus(); view.draw(view.bounds); image.unlockFocus()
            precondition(image.tiffRepresentation != nil)
        }
        print("PASS: body/eyes/fire recolor across all 6 states; black/white shading, alpha, unrelated pixels, persistence/reset")
    }

    static func main() throws {
        let resources = URL(fileURLWithPath: CommandLine.arguments[1])
        var loops = 0
        for appearance in PetAppearance.allCases {
            let small = appearance.size(forPreset: 4)
            let normal = appearance.size(forPreset: 5)
            precondition(small.width == appearance.canvasSize.width * 2)
            precondition(normal.width == appearance.canvasSize.width * 3)
            let view = try PetView(resources: resources, frame: NSRect(origin: .zero, size: small))
            view.setPetAppearance(appearance)
            for stage in PetStage.allCases {
                let loop = try SpriteLoop(name: appearance.assetPrefix + stage.asset, resources: resources)
                precondition(loop.images.count > 1)
                precondition(loop.images.count == loop.durations.count)
                precondition(loop.durations.allSatisfy { $0 > 0 })
                view.setStage(stage)
                let image = NSImage(size: small)
                image.lockFocus()
                view.draw(view.bounds)
                image.unlockFocus()
                precondition(image.tiffRepresentation != nil)
                loops += 1
            }
        }
        print("PASS: \(loops) sprite loops decoded and rendered; \(PetAppearance.allCases.count) appearances; small/normal sizes")
        try checkColors(resources: resources)
    }
}
