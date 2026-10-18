import Foundation
import AVFoundation

@main struct ClipAspectModelTests {
    @MainActor static func main() async throws {
        let model = ClipEditorModel(source:URL(fileURLWithPath:"/tmp/not-loaded-video.mp4"))
        precondition(model.canvas == .source)
        model.canvas = .custom
        model.customWidth = "5"; model.customHeight = "4"
        precondition(model.resolvedCustomSize == CGSize(width:1350,height:1080))
        model.setCustomMode(.pixels)
        precondition(model.customWidth == "1350" && model.customHeight == "1080")
        model.customWidth = "1280"; model.customHeight = "1024"
        model.setCustomMode(.ratio)
        precondition(model.customWidth == "5" && model.customHeight == "4")
        precondition(model.resolvedCustomSize == CGSize(width:1350,height:1080))
        model.setCustomMode(.pixels)
        model.customWidth = "4094"; model.customHeight = "4096"
        model.setCustomMode(.ratio)
        precondition(model.resolvedCustomSize != nil,"valid pixel dimensions must stay valid in ratio mode")
        model.setCustomMode(.pixels)
        model.customWidth = "8192"; model.customHeight = "64"
        model.setCustomMode(.ratio)
        precondition(model.resolvedCustomSize != nil,"extreme but valid pixel dimensions must convert safely")
        model.customWidth = "0"
        precondition(model.canvasValidationMessage != nil)
        model.canvas = .landscape
        precondition(model.canvasValidationMessage == nil,"unused custom draft must not block a preset")
        model.close()
        if CommandLine.arguments.count > 1 {
            let loaded = ClipEditorModel(source:URL(fileURLWithPath:CommandLine.arguments[1]))
            await loaded.load()
            precondition(loaded.geometry?.isValid == true)
            precondition(loaded.resolvedCanvasSize == loaded.geometry?.displaySize)
            loaded.canvas = .custom; loaded.setCustomMode(.pixels)
            loaded.customWidth = "1280"; loaded.customHeight = "1024"
            precondition(loaded.resolvedCanvasSize == CGSize(width:1280,height:1024))
            loaded.customWidth = "0"
            precondition(loaded.resolvedCanvasSize == nil && loaded.canvasValidationMessage != nil)
            loaded.canvas = .landscape
            precondition(loaded.resolvedCanvasSize == CGSize(width:1920,height:1080))
            loaded.canvas = .source
            precondition(loaded.resolvedCanvasSize == loaded.geometry?.displaySize)
            loaded.close()
        }
        print("PASS: custom mode conversion, preserved ratio and invalid-draft isolation")
    }
}
