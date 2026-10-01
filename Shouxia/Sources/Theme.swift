import SwiftUI
import AppKit
import CoreText

enum Ink {
    static let paper = Color(red:20/255,green:21/255,blue:20/255)
    static let dark = Color(red:240/255,green:240/255,blue:233/255)
    static let surface = Color(red:32/255,green:34/255,blue:31/255)
    static let mint = Color(red:173/255,green:207/255,blue:55/255)
    static let purple = Color(red:76/255,green:42/255,blue:113/255)
    static let muted = Color(red:166/255,green:169/255,blue:160/255)
    static let line = Color(red:54/255,green:59/255,blue:47/255)
    static let danger = Color(red:1,green:0.57,blue:0.48)
}
enum TypeStyle {
    static func heading(_ size: CGFloat) -> Font { .custom("Sora-SemiBold", size:size) }
    static func body(_ size: CGFloat = 13) -> Font { .custom("Manrope-Regular", size:size) }
    static func medium(_ size: CGFloat = 13) -> Font { .custom("Manrope-Medium", size:size) }
    static func register() {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("Fonts"), let files = try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil) else { return }
        for file in files where file.pathExtension == "ttf" { CTFontManagerRegisterFontsForURL(file as CFURL,.process,nil) }
    }
}
struct SoftButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(TypeStyle.medium()).padding(.horizontal,16).padding(.vertical,11)
            .foregroundStyle(primary ? Ink.paper : Ink.dark)
            .background(primary ? Ink.mint : Ink.surface)
            .clipShape(RoundedRectangle(cornerRadius:10))
            .opacity(!isEnabled ? 0.4 : (configuration.isPressed ? 0.75 : 1))
    }
}
struct GlyphButton: View {
    let symbol: String; let title: String; var action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action:action) { Image(systemName:symbol).font(.system(size:13,weight:.medium)).frame(width:30,height:30).background(hovered ? Ink.surface : .clear).clipShape(RoundedRectangle(cornerRadius:8)) }
            .buttonStyle(.plain).help(title).accessibilityLabel(title).onHover { hovered=$0 }
    }
}
struct ReceiveMark: View {
    var size: CGFloat = 40
    var body: some View {
        Group {
            if let path = Bundle.main.path(forResource:"Mascot",ofType:"png"), let image = NSImage(contentsOfFile:path) {
                Image(nsImage:image).resizable().interpolation(.high).scaledToFit()
            } else { Image(systemName:"play.rectangle.fill").resizable().scaledToFit().padding(8) }
        }.frame(width:size,height:size).clipShape(RoundedRectangle(cornerRadius:size*0.23))
    }
}
