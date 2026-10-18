import Foundation
import CoreGraphics

/// Pixel dimensions refer to the displayed image after its orientation transform.
enum ClipCanvas: String, CaseIterable, Identifiable {
    case source, landscape, portrait, square, standard, tall, social
    var id: String { rawValue }
    var label: String {
        switch self {
        case .source: return "原视频"
        case .landscape: return "横屏 16:9 · 1920 × 1080"
        case .portrait: return "竖屏 9:16 · 1080 × 1920"
        case .square: return "方形 1:1 · 1080 × 1080"
        case .standard: return "横屏 4:3 · 1440 × 1080"
        case .tall: return "竖屏 3:4 · 1080 × 1440"
        case .social: return "竖屏 4:5 · 1080 × 1350"
        }
    }
    func size(for source: ClipGeometry) -> CGSize {
        switch self {
        case .source: return source.displaySize
        case .landscape: return CGSize(width: 1920, height: 1080)
        case .portrait: return CGSize(width: 1080, height: 1920)
        case .square: return CGSize(width: 1080, height: 1080)
        case .standard: return CGSize(width: 1440, height: 1080)
        case .tall: return CGSize(width: 1080, height: 1440)
        case .social: return CGSize(width: 1080, height: 1350)
        }
    }
}

struct ClipGeometry {
    let naturalSize: CGSize
    let preferredTransform: CGAffineTransform
    var displayBounds: CGRect { CGRect(origin: .zero, size: naturalSize).applying(preferredTransform).standardized }
    var displaySize: CGSize { displayBounds.size }
    var isValid: Bool { displaySize.width.isFinite && displaySize.height.isFinite && displaySize.width > 0 && displaySize.height > 0 }
    static func fit(size: CGSize, inside bounds: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = max(0, min(bounds.width / size.width, bounds.height / size.height))
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
    func fitTransform(in canvas: CGSize) -> CGAffineTransform {
        let fitted = Self.fit(size: displaySize, inside: canvas)
        let scale = fitted.width / displaySize.width
        return preferredTransform
            .concatenating(CGAffineTransform(translationX: -displayBounds.minX, y: -displayBounds.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: (canvas.width - fitted.width) / 2, y: (canvas.height - fitted.height) / 2))
    }
}
