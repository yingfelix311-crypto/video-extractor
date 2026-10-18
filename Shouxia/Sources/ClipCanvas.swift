import Foundation
import CoreGraphics

/// Pixel dimensions refer to the displayed image after its orientation transform.
enum ClipCanvas: String, CaseIterable, Identifiable {
    case source, landscape, ultrawide, standard, photo, square, portrait, tall, verticalPhoto, social, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .source: return "原视频比例"
        case .landscape: return "16:9"
        case .ultrawide: return "21:9"
        case .standard: return "4:3"
        case .photo: return "3:2"
        case .square: return "1:1"
        case .portrait: return "9:16"
        case .tall: return "3:4"
        case .verticalPhoto: return "2:3"
        case .social: return "4:5"
        case .custom: return "自定义"
        }
    }
    func size(for source: ClipGeometry, customSize: CGSize? = nil) -> CGSize {
        switch self {
        case .source: return source.displaySize
        case .custom: return customSize ?? .zero
        case .ultrawide: return CGSize(width: 2520, height: 1080)
        case .photo: return CGSize(width: 1620, height: 1080)
        case .verticalPhoto: return CGSize(width: 1080, height: 1620)
        case .landscape: return CGSize(width: 1920, height: 1080)
        case .portrait: return CGSize(width: 1080, height: 1920)
        case .square: return CGSize(width: 1080, height: 1080)
        case .standard: return CGSize(width: 1440, height: 1080)
        case .tall: return CGSize(width: 1080, height: 1440)
        case .social: return CGSize(width: 1080, height: 1350)
        }
    }
}

enum ClipCustomMode: String, CaseIterable, Identifiable {
    case ratio, pixels
    var id: String { rawValue }
    var label: String { self == .ratio ? "按比例" : "按像素" }
}

/// Shared by the editor and exporter, so invalid drafts cannot change only one side.
enum ClipCustomCanvas {
    static let maxPixels: CGFloat = 33_554_432
    enum ValidationError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }
    static func parse(width: String, height: String, mode: ClipCustomMode) throws -> CGSize {
        let w = width.trimmingCharacters(in: .whitespacesAndNewlines)
        let h = height.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .pixels {
            guard let width = Int(w), let height = Int(h) else {
                throw ValidationError.message("像素宽高请填写整数。")
            }
            return try validate(size: CGSize(width: width, height: height))
        }
        guard let width = Double(w), let height = Double(h), width.isFinite, height.isFinite,
              width > 0, height > 0, width <= 1000, height <= 1000 else {
            throw ValidationError.message("比例请填大于 0 且不超过 1000 的数字。")
        }
        let ratio = width / height
        guard ((1.0 / 128)...128).contains(ratio) else {
            throw ValidationError.message("比例过于狭长，请将宽高差控制在 128 倍以内。")
        }
        let raw = ratio >= 1 ? CGSize(width: 1080 * ratio, height: 1080) : CGSize(width: 1080, height: 1080 / ratio)
        let scale = min(1, 8192 / max(raw.width, raw.height), sqrt(maxPixels / (raw.width * raw.height)))
        let size = CGSize(width: (raw.width * scale / 2).rounded(.down) * 2,
                          height: (raw.height * scale / 2).rounded(.down) * 2)
        return try validate(size: size)
    }
    static func validate(size: CGSize) throws -> CGSize {
        guard size.width.isFinite, size.height.isFinite,
              (64...8192).contains(size.width), (64...8192).contains(size.height),
              size.width.rounded() == size.width, size.height.rounded() == size.height,
              Int(size.width) % 2 == 0, Int(size.height) % 2 == 0 else {
            throw ValidationError.message("像素宽高须为 64–8192 之间的偶数。")
        }
        guard size.width * size.height <= maxPixels else {
            throw ValidationError.message("画面总像素过大，请减小宽或高。")
        }
        return size
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
