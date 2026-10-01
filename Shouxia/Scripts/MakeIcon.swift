import AppKit
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let factor = CGFloat(pixels) / 1024
        let transform = NSAffineTransform()
        transform.scale(by: factor)
        transform.concat()
        NSColor(calibratedRed: 0.065, green: 0.12, blue: 0.10, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 200, yRadius: 200).fill()
        NSColor(calibratedRed: 0.69, green: 0.94, blue: 0.68, alpha: 1).setStroke()
        let arrow = NSBezierPath()
        arrow.lineWidth = 66; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
        arrow.move(to: NSPoint(x: 512,y: 730)); arrow.line(to: NSPoint(x: 512,y: 363))
        arrow.move(to: NSPoint(x: 355,y: 505)); arrow.line(to: NSPoint(x: 512,y: 348)); arrow.line(to: NSPoint(x: 669,y: 505))
        arrow.move(to: NSPoint(x: 325,y: 275)); arrow.line(to: NSPoint(x: 699,y: 275)); arrow.stroke()
        image.unlockFocus()
        let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let suffix = scale == 2 ? "@2x" : ""
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/icon_\(size)x\(size)\(suffix).png"))
    }
}
