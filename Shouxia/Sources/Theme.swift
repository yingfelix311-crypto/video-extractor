import SwiftUI

// One palette across the main window, popover and interaction states.
enum Ink {
    static let dark = Color(red: 0.065, green: 0.12, blue: 0.10)
    static let paper = Color(red: 0.95, green: 0.955, blue: 0.93)
    static let surface = Color(red: 0.985, green: 0.988, blue: 0.975)
    static let mint = Color(red: 0.69, green: 0.94, blue: 0.68)
    static let muted = Color(red: 0.37, green: 0.41, blue: 0.37)
    static let line = Color(red: 0.83, green: 0.85, blue: 0.81)
    static let danger = Color(red: 0.69, green: 0.20, blue: 0.14)
}

struct SoftButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(primary ? Ink.dark : Ink.dark)
            .background(primary ? Ink.mint : Ink.dark.opacity(configuration.isPressed ? 0.12 : 0.055))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .opacity(!isEnabled ? 0.4 : (configuration.isPressed ? 0.75 : 1))
    }
}

struct GlyphButton: View {
    let symbol: String
    let title: String
    var action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium))
                .frame(width: 30, height: 30)
                .background(hovered ? Ink.dark.opacity(0.075) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).help(title).accessibilityLabel(title)
        .onHover { hovered = $0 }
    }
}

struct ReceiveMark: View {
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: "arrow.down.to.line.compact")
            .font(.system(size: size * 0.58, weight: .semibold))
            .frame(width: size, height: size)
    }
}
