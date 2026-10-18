import Foundation
import AVFoundation

@main struct ClipAspectExportTests {
    static func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating:0,count:image.width*image.height*4)
        bytes.withUnsafeMutableBytes { memory in
            let context=CGContext(data:memory.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
            context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
        }
        let offset=(y*image.width+x)*4
        return Array(bytes[offset..<offset+3])
    }
    @MainActor static func main() async throws {
        let source=URL(fileURLWithPath:CommandLine.arguments[1])
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("clip-aspects-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:directory)}
        let track=try await AVURLAsset(url:source).loadTracks(withMediaType:.video)[0]
        let geometry=ClipGeometry(naturalSize:try await track.load(.naturalSize),preferredTransform:try await track.load(.preferredTransform))
        let customRatio=try ClipCustomCanvas.parse(width:"5",height:"4",mode:.ratio)
        let cases:[(ClipCanvas,CGSize?,CGSize)] = [(.source,nil,geometry.displaySize),(.ultrawide,nil,CGSize(width:2520,height:1080)),(.custom,CGSize(width:1280,height:1024),CGSize(width:1280,height:1024)),(.custom,customRatio,CGSize(width:1350,height:1080))]
        let range=try ClipRange(start:0.2,end:0.7,duration:1)
        let exporter=ClipExporter()
        for (index,entry) in cases.enumerated() {
            let (canvas,custom,expected)=entry
            let target=directory.appendingPathComponent("\(index).mp4")
            try await exporter.export(source:source,target:target,range:range,canvas:canvas,customSize:custom)
            let result=AVURLAsset(url:target)
            let outputTrack=try await result.loadTracks(withMediaType:.video)[0]
            let output=ClipGeometry(naturalSize:try await outputTrack.load(.naturalSize),preferredTransform:try await outputTrack.load(.preferredTransform))
            precondition(output.displaySize==expected,"preview/export canvas dimensions differ")
            let duration=try await result.load(.duration).seconds
            let audio=try await result.loadTracks(withMediaType:.audio)
            precondition(abs(duration-0.5)<0.1)
            precondition(!audio.isEmpty)
            let generator=AVAssetImageGenerator(asset:result);generator.appliesPreferredTrackTransform=true
            let image=try await generator.image(at:CMTime(seconds:0.2,preferredTimescale:600)).image
            let center=pixel(image,x:image.width/2,y:image.height/2)
            precondition(center[0]>150 && center[1]<80 && center[2]<80,"content changed or vanished")
            let fit=min(expected.width/geometry.displaySize.width,expected.height/geometry.displaySize.height)
            let padX=(expected.width-geometry.displaySize.width*fit)/2
            let padY=(expected.height-geometry.displaySize.height*fit)/2
            if padX>2 {precondition(pixel(image,x:Int(padX/2),y:image.height/2).allSatisfy{$0<20},"side padding missing")}
            if padY>2 {precondition(pixel(image,x:image.width/2,y:Int(padY/2)).allSatisfy{$0<20},"top padding missing")}
        }
        let invalid=directory.appendingPathComponent("invalid.mp4")
        do {try await exporter.export(source:source,target:invalid,range:range,canvas:.custom,customSize:CGSize(width:1279,height:720));preconditionFailure("odd custom size accepted")} catch {}
        precondition(!FileManager.default.fileExists(atPath:invalid.path))
        print("PASS: source/21:9/custom ratio/custom pixels actual exports, orientation, audio, fit and black padding")
    }
}
