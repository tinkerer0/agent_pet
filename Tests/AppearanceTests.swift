import AppKit

@main struct AppearanceTests {
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
    }
}
