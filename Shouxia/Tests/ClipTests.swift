import Foundation
import AVFoundation
@main struct ClipTests {
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
   let exported = try Data(contentsOf: target)
   do { try await service.export(source: source, target: target, range: range); preconditionFailure("must not overwrite") } catch {}
   precondition(try! Data(contentsOf: target) == exported)
   precondition(try! Data(contentsOf: source) == original)
   let cancelledTarget = directory.appendingPathComponent("cancelled.mp4")
   let task = Task { try await service.export(source: source, target: cancelledTarget, range: range) }
   await Task.yield()
   service.cancel()
   do { try await task.value; preconditionFailure("expected cancellation") } catch is CancellationError {}
   precondition(!FileManager.default.fileExists(atPath: cancelledTarget.path))
   precondition(try! FileManager.default.contentsOfDirectory(atPath: directory.path) == ["clip.mp4"])
   print("PASS: short export, audio/video, original preserved, no overwrite, cancellation cleanup; elapsed \(Date().timeIntervalSince(began))s")
  }
 }
}
