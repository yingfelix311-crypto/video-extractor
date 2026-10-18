import Foundation
import AVFoundation
struct ClipTestPixels {
 let width: Int
 let height: Int
 var bytes: [UInt8]
 init(_ image: CGImage) {
  width = image.width; height = image.height
  bytes = [UInt8](repeating: 0, count: width * height * 4)
  bytes.withUnsafeMutableBytes { buffer in
   let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
   context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
  }
 }
 func pixel(_ x: Double, _ y: Double) -> [Int] {
  let index = (min(height - 1, max(0, Int(y))) * width + min(width - 1, max(0, Int(x)))) * 4
  return bytes[index..<index + 3].map(Int.init)
 }
}
@main struct ClipTests {
 static func verifyContent(source: CGImage, output: CGImage, fixture: Bool) {
  let reference = ClipTestPixels(source), result = ClipTestPixels(output)
  // Independent oracle: displayed source image, fit by image dimensions, never production geometry.
  let scale = min(Double(output.width) / Double(source.width), Double(output.height) / Double(source.height))
  let w = Double(source.width) * scale, h = Double(source.height) * scale
  let x = (Double(output.width) - w) / 2, y = (Double(output.height) - h) / 2
  let points: [(Double, Double)] = [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75), (0.01, 0.5), (0.99, 0.5), (0.5, 0.01), (0.5, 0.99)]
  for (u, v) in points {
   let expected = reference.pixel(Double(source.width) * u, Double(source.height) * v)
   let actual = result.pixel(x + w * u, y + h * v)
   // AVFoundation may change the decoded color profile during H.264 export;
   // this tolerance retains quadrant identity while allowing that conversion.
   precondition(zip(expected, actual).allSatisfy { abs($0 - $1) < 85 }, "displayed content mismatch at \(u),\(v): \(expected) vs \(actual)")
   if fixture { precondition(actual.max()! > 100, "fixture content must not be black") }
  }
  if x > 2 {
   for px in [x / 2, Double(output.width) - x / 2] {
    precondition(result.pixel(px, Double(output.height) / 2).allSatisfy { $0 < 16 }, "both side pads must be black")
   }
  }
  if y > 2 {
   for py in [y / 2, Double(output.height) - y / 2] {
    precondition(result.pixel(Double(output.width) / 2, py).allSatisfy { $0 < 16 }, "both top/bottom pads must be black")
   }
  }
 }

 @MainActor static func main() async throws {
  precondition(ClipRange.parse("01:02.500") == 62.5)
  precondition(ClipRange.parse("1:02:03.125") == 3723.125)
  for value in ["", "-1", "nan", "1:60", "1:2:3:4", "1::2"] { precondition(ClipRange.parse(value) == nil, value) }
  precondition(ClipRange.format(62.5) == "00:01:02.500")
  precondition(ClipRange.format(59.9999) == "00:01:00.000")
  precondition((try? ClipRange(start: 2, end: 1, duration: 10)) == nil)
  precondition((try? ClipRange(start: 0, end: 11, duration: 10)) == nil)
  precondition((try? ClipRange(start: .nan, end: 1, duration: 10)) == nil)
  let range = try ClipRange(start: 1.25, end: 2.75, duration: 10)
  precondition(range.length == 1.5)
  print("PASS: clip time parsing, rounding and range validation")
  if CommandLine.arguments.count > 1 {
   let source = URL(fileURLWithPath: CommandLine.arguments[1])
   let original = try Data(contentsOf: source)
   let directory = FileManager.default.temporaryDirectory.appendingPathComponent("clip-check-" + UUID().uuidString)
   try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
   defer { try? FileManager.default.removeItem(at: directory) }
   let target = directory.appendingPathComponent("clip.mp4")
   let service = ClipExporter()
   let began = Date()
   try await service.export(source: source, target: target, range: range)
   let asset = AVURLAsset(url: target)
   let duration = try await asset.load(.duration).seconds
   precondition(abs(duration - range.length) < 0.12, "wrong output duration")
   let video = try await asset.loadTracks(withMediaType: .video)
   let audio = try await asset.loadTracks(withMediaType: .audio)
   precondition(!video.isEmpty && !audio.isEmpty, "video and audio required")
   for speed in [0.5, 1.35, 2.0] {
    let changed = directory.appendingPathComponent("speed-\(speed).mp4")
    try await service.export(source: source, target: changed, range: range, speed: speed)
    let output = AVURLAsset(url: changed)
    let actual = try await output.load(.duration).seconds
    precondition(abs(actual - range.length / speed) < 0.12, "speed duration mismatch")
    let tracks = try await output.loadTracks(withMediaType: .audio)
    precondition(!tracks.isEmpty, "speed export must retain audio")
    let audioRange = try await tracks[0].load(.timeRange)
    precondition(abs(audioRange.duration.seconds - actual) < 0.15, "audio/video duration mismatch")
    try FileManager.default.removeItem(at: changed)
   }
   print("PASS: 0.5x, 1.35x and 2x exports have expected duration and synchronized audio duration")
   let sourceTrack = try await AVURLAsset(url: source).loadTracks(withMediaType: .video)[0]
   let sourceGeometry = ClipGeometry(naturalSize: try await sourceTrack.load(.naturalSize), preferredTransform: try await sourceTrack.load(.preferredTransform))
   let originalTrack = video[0]
   let originalGeometry = ClipGeometry(naturalSize: try await originalTrack.load(.naturalSize), preferredTransform: try await originalTrack.load(.preferredTransform))
   precondition(originalGeometry.displaySize == sourceGeometry.displaySize, "source export must preserve display dimensions")
   let sourceGenerator = AVAssetImageGenerator(asset: AVURLAsset(url: source))
   sourceGenerator.appliesPreferredTrackTransform = true
   let reference = try await sourceGenerator.image(at: CMTime(seconds: range.start + 0.3 * 1.35, preferredTimescale: 60000)).image
   let originalGenerator = AVAssetImageGenerator(asset: asset)
   originalGenerator.appliesPreferredTrackTransform = true
   let originalImage = try await originalGenerator.image(at: CMTime(seconds: 0.3 * 1.35, preferredTimescale: 60000)).image
   verifyContent(source: reference, output: originalImage, fixture: CommandLine.arguments.contains("--fixture"))
   for canvas in ClipCanvas.allCases where canvas != .source {
    let changed = directory.appendingPathComponent("canvas-\(canvas.rawValue).mp4")
    try await service.export(source: source, target: changed, range: range, speed: 1.35, canvas: canvas)
    let output = AVURLAsset(url: changed)
    let track = try await output.loadTracks(withMediaType: .video)[0]
    let geometry = ClipGeometry(naturalSize: try await track.load(.naturalSize), preferredTransform: try await track.load(.preferredTransform))
    precondition(geometry.displaySize == canvas.size(for: sourceGeometry), "wrong canvas dimensions")
    let actual = try await output.load(.duration).seconds
    precondition(abs(actual - range.length / 1.35) < 0.12)
    let canvasAudio = try await output.loadTracks(withMediaType: .audio)
    precondition(!canvasAudio.isEmpty)
    let image = try await AVAssetImageGenerator(asset: output).image(at: CMTime(seconds: 0.3, preferredTimescale: 600)).image
    precondition(image.width == Int(geometry.displaySize.width) && image.height == Int(geometry.displaySize.height))
    verifyContent(source: reference, output: image, fixture: CommandLine.arguments.contains("--fixture"))
    try FileManager.default.removeItem(at: changed)
   }
   print("PASS: source orientation/dimensions preserved; all six preset canvases preserve oriented content and black pads, match with 1.35x and audio")
   let exported = try Data(contentsOf: target)
   do { try await service.export(source: source, target: target, range: range); preconditionFailure("must not overwrite") } catch {}
   precondition(try! Data(contentsOf: target) == exported)
   precondition(try! Data(contentsOf: source) == original)
   for (name, canvas) in [("cancelled-source.mp4", ClipCanvas.source), ("cancelled-preset.mp4", ClipCanvas.square)] {
    let cancelledTarget = directory.appendingPathComponent(name)
    let task = Task { try await service.export(source: source, target: cancelledTarget, range: range, canvas: canvas) }
    await Task.yield()
    service.cancel()
    do { try await task.value; preconditionFailure("expected cancellation") } catch is CancellationError {}
    precondition(!FileManager.default.fileExists(atPath: cancelledTarget.path))
   }
   precondition(try! FileManager.default.contentsOfDirectory(atPath: directory.path) == ["clip.mp4"])
   print("PASS: short export, audio/video, original preserved, no overwrite, cancellation cleanup; elapsed \(Date().timeIntervalSince(began))s")
  }
 }
}
