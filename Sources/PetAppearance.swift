import AppKit

/// The Clawd character: 48×42 frames drawn at whole-pixel scales.
enum PetAppearance {
    static let title = "Clawd"
    static let canvasSize = NSSize(width: 48, height: 42)

    static func size(forPreset preset: Int) -> NSSize {
        // Keep saved menu choices; normal now matches the previous small size.
        let pixels = CGFloat(max(1, preset - 2))
        return NSSize(width: canvasSize.width * pixels, height: canvasSize.height * pixels)
    }
}
