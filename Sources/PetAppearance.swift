import AppKit

enum PetAppearance: String, CaseIterable {
    case claude

    var title: String {
        "Clawd"
    }

    var canvasSize: NSSize {
        NSSize(width: 48, height: 42)
    }

    var assetPrefix: String {
        ""
    }

    func size(forPreset preset: Int) -> NSSize {
        // Keep saved menu choices; normal now matches the previous small size.
        let pixels = CGFloat(max(1, preset - 2))
        return NSSize(width: canvasSize.width * pixels, height: canvasSize.height * pixels)
    }

}
