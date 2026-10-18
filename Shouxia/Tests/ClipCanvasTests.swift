import Foundation
import AVFoundation
@main struct ClipCanvasTests {
 static func main() {
  let size = CGSize(width: 1920, height: 1080)
  let rotation = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
  let geometry = ClipGeometry(naturalSize: size, preferredTransform: rotation)
  precondition(geometry.displaySize == CGSize(width: 1080, height: 1920))
  precondition(ClipCanvas.source.size(for: geometry) == geometry.displaySize)
  let canvas = ClipCanvas.landscape.size(for: geometry)
  let rect = CGRect(origin: .zero, size: size).applying(geometry.fitTransform(in: canvas))
  precondition(abs(rect.height - 1080) < 0.01)
  precondition(abs(rect.midX - 960) < 0.01 && abs(rect.midY - 540) < 0.01)
  for transform in [CGAffineTransform.identity, rotation, CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 0, ty: 0), CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: -30, ty: 70)] {
   let source = ClipGeometry(naturalSize: size, preferredTransform: transform)
   for preset in ClipCanvas.allCases {
    let output = preset.size(for: source)
    let result = CGRect(origin: .zero, size: size).applying(source.fitTransform(in: output)).standardized
    precondition(result.minX >= -0.01 && result.minY >= -0.01 && result.maxX <= output.width + 0.01 && result.maxY <= output.height + 0.01)
    precondition(abs(result.midX - output.width / 2) < 0.01 && abs(result.midY - output.height / 2) < 0.01)
    precondition(abs(result.width / result.height - source.displaySize.width / source.displaySize.height) < 0.001)
   }
  }
  let preview = ClipGeometry.fit(size: canvas, inside: CGSize(width: 600, height: 260))
  precondition(preview.width <= 600 && preview.height <= 260)
  print("PASS: original rotated dimensions, centered aspect-fit and bounded preview")
 }
}
