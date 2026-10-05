import SwiftUI
import AVFoundation

@main struct ClipTimelineTests {
    @MainActor static func main() throws {
        let model = ClipEditorModel(source: URL(fileURLWithPath: "/tmp/clip-timeline-test.mp4"))
        precondition(model.setPlaybackSpeed(1.35))
        precondition(abs(model.playbackSpeed - 1.35) < 0.0001)
        for speed in [Double.nan, .infinity, 0, -1, 2.1] { precondition(!model.setPlaybackSpeed(speed)) }
        precondition(model.player.rate == 0, "setting speed while paused must not start playback")
        model.resetPreview()
        precondition(abs(model.playbackSpeed - 1.35) < 0.0001, "pause preserves speed")
        model.duration = 60
        model.loading = false
        model.endText = ClipRange.format(40)
        model.moveBoundary(12.345, start: true)
        precondition(model.range?.start == 12.345)
        model.moveBoundary(50, start: true)
        precondition(model.range != nil && model.range!.start < 40)
        model.moveBoundary(-10, start: true)
        precondition(model.range?.start == 0)
        model.moveBoundary(100, start: false)
        precondition(model.range?.end == 60)
        model.moveBoundary(-20, start: false)
        precondition(model.range != nil && model.range!.end > 0)
        model.moveBoundary(45, start: false)
        model.moveBoundary(15, start: true)
        model.position = 24
        let renderer = ImageRenderer(content: ClipTimeline(model: model).padding(24).frame(width: 700).background(Ink.paper))
        renderer.scale = 2
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: URL(fileURLWithPath: "/tmp/clip-timeline-preview.png"))
        }
        model.close()
        print("PASS: boundary dragging clamps at duration and prevents crossing; timeline rendered")
    }
}
