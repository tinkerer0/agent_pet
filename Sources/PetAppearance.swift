import AppKit

enum PetAppearance: String, CaseIterable {
    case claude, codex, grok, together

    var title: String {
        switch self {
        case .claude: return "Clawd · Claude"
        case .codex: return "Cody · Codex"
        case .grok: return "Grok · 보라"
        case .together: return "함께 · 한 책상에서"
        }
    }

    var canvasSize: NSSize {
        self == .together ? NSSize(width: 96, height: 48) : NSSize(width: 48, height: 42)
    }

    var assetPrefix: String {
        switch self {
        case .claude: return ""
        case .codex: return "codex-"
        case .grok: return "grok-"
        case .together: return "together-"
        }
    }

    func size(forPreset preset: Int) -> NSSize {
        // Keep saved menu choices; normal now matches the previous small size.
        let pixels = CGFloat(max(1, preset - 2))
        return NSSize(width: canvasSize.width * pixels, height: canvasSize.height * pixels)
    }

}
