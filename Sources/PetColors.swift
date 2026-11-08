import AppKit

struct PetRGB: Equatable {
    let value: Int

    init(_ value: Int) { self.value = value & 0xffffff }
    init?(_ text: String) {
        guard text.range(of: "\\A#[0-9a-fA-F]{6}\\z", options: .regularExpression) != nil,
              let value = Int(text.dropFirst(), radix: 16) else { return nil }
        self.init(value)
    }
    init?(_ color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        func channel(_ value: CGFloat) -> Int { Int((min(1, max(0, value)) * 255).rounded()) }
        self.init((channel(rgb.redComponent) << 16) | (channel(rgb.greenComponent) << 8) | channel(rgb.blueComponent))
    }
    var hex: String { String(format: "#%06x", value) }
    var color: NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
            green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
    func blend(toward target: PetRGB, amount: Double) -> PetRGB {
        var result = 0
        for shift in [16, 8, 0] {
            let from = Double((value >> shift) & 255), to = Double((target.value >> shift) & 255)
            result |= Int((from + (to - from) * amount).rounded()) << shift
        }
        return PetRGB(result)
    }
    var brightness: Int { max((value >> 16) & 255, (value >> 8) & 255, value & 255) }
}

enum PetColorPart: Int, CaseIterable {
    case body, eyes, fire
    var title: String {
        switch self {
        case .body: return "몸체"
        case .eyes: return "눈"
        case .fire: return "불꽃"
        }
    }
    var key: String {
        switch self {
        case .body: return "petBodyColor"
        case .eyes: return "petEyeColor"
        case .fire: return "petFireColor"
        }
    }
}

struct PetColors: Equatable {
    var body = PetRGB(0xd87656)
    var eyes = PetRGB(0x000000)
    var fire = PetRGB(0x397bff)
    static let standard = PetColors()

    subscript(part: PetColorPart) -> PetRGB {
        get {
            switch part {
            case .body: return body
            case .eyes: return eyes
            case .fire: return fire
            }
        }
        set {
            switch part {
            case .body: body = newValue
            case .eyes: eyes = newValue
            case .fire: fire = newValue
            }
        }
    }
    static func load(from defaults: UserDefaults = .standard) -> PetColors {
        var colors = standard
        for part in PetColorPart.allCases {
            if let text = defaults.string(forKey: part.key), let value = PetRGB(text) { colors[part] = value }
        }
        return colors
    }
    func save(to defaults: UserDefaults = .standard) {
        for part in PetColorPart.allCases { defaults.set(self[part].hex, forKey: part.key) }
    }
    var replacements: [Int: Int] {
        let light = body.brightness < 38 ? body.blend(toward: PetRGB(0xffffff), amount: 0.12) : body
        let shadow = body == Self.standard.body ? PetRGB(0xbe684d)
            : body.brightness < 38 ? body : body.blend(toward: PetRGB(0), amount: 0.22)
        let flame = fire == Self.standard.fire ? [fire, PetRGB(0x6dc9ff), PetRGB(0xd9fbff), PetRGB(0xffffff)]
            : [fire, fire.blend(toward: PetRGB(0xffffff), amount: 0.3),
               fire.blend(toward: PetRGB(0xffffff), amount: 0.82), PetRGB(0xffffff)]
        return [0xd87656: light.value, 0xbe684d: shadow.value, 0x000000: eyes.value,
                0x397bff: flame[0].value, 0x6dc9ff: flame[1].value,
                0xd9fbff: flame[2].value, 0xffffff: flame[3].value]
    }

    func recolor(_ original: CGImage) throws -> CGImage {
        if self == Self.standard { return original }
        let width = original.width, height = original.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let mapping = replacements
        return try bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: original.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else {
                throw ProbeError.command("Color context unavailable")
            }
            context.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height))
            let pixels = buffer.bindMemory(to: UInt8.self)
            for offset in stride(from: 0, to: pixels.count, by: 4) where pixels[offset + 3] == 255 {
                let key = Int(pixels[offset]) << 16 | Int(pixels[offset + 1]) << 8 | Int(pixels[offset + 2])
                guard let replacement = mapping[key] else { continue }
                pixels[offset] = UInt8((replacement >> 16) & 255)
                pixels[offset + 1] = UInt8((replacement >> 8) & 255)
                pixels[offset + 2] = UInt8(replacement & 255)
            }
            guard let image = context.makeImage() else { throw ProbeError.command("Color image unavailable") }
            return image
        }
    }
}
