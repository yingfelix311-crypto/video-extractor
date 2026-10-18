import Foundation
import CoreGraphics

@main struct ClipCustomCanvasTests {
    static func main() throws {
        func ratio(_ w: String, _ h: String) throws -> CGSize {
            try ClipCustomCanvas.parse(width:w,height:h,mode:.ratio)
        }
        func pixels(_ w: String, _ h: String) throws -> CGSize {
            try ClipCustomCanvas.parse(width:w,height:h,mode:.pixels)
        }
        precondition(try! ratio("5","4") == CGSize(width:1350,height:1080))
        precondition(try! ratio("2.35","1") == CGSize(width:2538,height:1080))
        precondition(try! ratio("9","16") == CGSize(width:1080,height:1920))
        precondition(try! pixels("1280","1024") == CGSize(width:1280,height:1024))
        precondition(try! pixels(" 1920 ","1080") == CGSize(width:1920,height:1080))
        for (w,h) in [("","9"),("0","9"),("-1","9"),("nan","9"),("inf","9"),("1001","1"),("129","1"),("1","129"),("16x","9")] {
            precondition((try? ratio(w,h)) == nil,"invalid ratio accepted")
        }
        for (w,h) in [("63","64"),("8194","1080"),("1279","720"),("1280.5","720"),("8192","8192"),("nan","720"),("0","720")] {
            precondition((try? pixels(w,h)) == nil,"invalid pixels accepted")
        }
        let huge = try ratio("20","1")
        precondition(huge.width <= 8192 && huge.height >= 64)
        precondition(Int(huge.width)%2 == 0 && Int(huge.height)%2 == 0)
        precondition(abs(huge.width/huge.height - 20) < 0.1)
        precondition(try! ClipCustomCanvas.validate(size:CGSize(width:7680,height:4320)) == CGSize(width:7680,height:4320))
        precondition((try? ClipCustomCanvas.validate(size:CGSize(width:CGFloat.nan,height:100))) == nil)
        let source=ClipGeometry(naturalSize:CGSize(width:640,height:360),preferredTransform:.identity)
        precondition(ClipCanvas.custom.size(for:source,customSize:try! pixels("1280","1024")) == CGSize(width:1280,height:1024))
        print("PASS: custom ratio/pixel validation, decimal ratio, dimension and resource bounds")
    }
}
