import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NotificationCenter.default.post(name: .showShouxiaWindow, object: nil) }
        return true
    }
}
extension Notification.Name { static let showShouxiaWindow = Notification.Name("showShouxiaWindow") }

@main
struct ShouxiaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var store = DownloadStore()
    // A dedicated monochrome glyph keeps the mascot legible at menu-bar scale.
    private static let menuBarMascot: NSImage = {
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()
            let outline = NSBezierPath()
            outline.move(to: NSPoint(x: 9.1, y: 19))
            outline.curve(to: NSPoint(x: 12.9, y: 19), controlPoint1: NSPoint(x: 10, y: 20.5), controlPoint2: NSPoint(x: 12, y: 20.5))
            outline.line(to: NSPoint(x: 19.3, y: 6.5))
            outline.curve(to: NSPoint(x: 17.2, y: 3.4), controlPoint1: NSPoint(x: 20.3, y: 4.5), controlPoint2: NSPoint(x: 19.1, y: 3.4))
            outline.line(to: NSPoint(x: 4.8, y: 3.4))
            outline.curve(to: NSPoint(x: 2.7, y: 6.5), controlPoint1: NSPoint(x: 2.9, y: 3.4), controlPoint2: NSPoint(x: 1.7, y: 4.5))
            outline.close()
            outline.lineWidth = 1.7
            outline.lineJoinStyle = .round
            outline.stroke()
            for x in [8.5, 12.1] {
                NSBezierPath(ovalIn: NSRect(x: x, y: 12.6, width: 1.5, height: 1.8)).fill()
            }
            let wrap = NSBezierPath()
            wrap.move(to: NSPoint(x: 4.5, y: 8.9))
            wrap.line(to: NSPoint(x: 7.9, y: 7.5))
            wrap.move(to: NSPoint(x: 14.2, y: 7.5))
            wrap.line(to: NSPoint(x: 17.6, y: 9.2))
            wrap.lineWidth = 1.5
            wrap.lineCapStyle = .round
            wrap.stroke()
            let play = NSBezierPath()
            play.move(to: NSPoint(x: 9.5, y: 10.3))
            play.line(to: NSPoint(x: 13.4, y: 8))
            play.line(to: NSPoint(x: 9.5, y: 5.7))
            play.close(); play.fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
    init() { TypeStyle.register() }
    var body: some Scene {
        Window("Video Extractor", id: "main") {
            MainView(store: store)
                .preferredColorScheme(.dark)
                .task { store.start() }
        }
        .defaultSize(width: 900, height: 780)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("截取本地视频…") { ClipWindow.shared.choose() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Button("快捷输入") { QuickWindow.shared.show(store: store) }
                Button("打开下载文件夹") { FileActions.revealFolder(store.destinationPath) }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("刷新下载任务") { Task { await store.refresh() } }
                    .keyboardShortcut("r")
            }
            CommandGroup(replacing: .help) {
                Button("使用说明") { FileActions.showHelp() }
                Button("打开后台日志") { FileActions.openLog() }
            }
        }
        MenuBarExtra {
            QuickPanel(store: store)
                .preferredColorScheme(.dark)
        } label: {
            Image(nsImage: Self.menuBarMascot)
                .renderingMode(.template)
                .accessibilityLabel("Video Extractor")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor enum FileActions {
    static var root: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/MeTube", isDirectory: true) }
    static func revealFolder(_ path: String? = nil) { NSWorkspace.shared.open(path.map { URL(fileURLWithPath:$0) } ?? root) }
    @discardableResult static func chooseFolder(store: DownloadStore) -> Bool {
        let panel = NSOpenPanel()
        panel.title = "选择视频保存文件夹"; panel.prompt = "选择文件夹"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = true
        panel.directoryURL = URL(fileURLWithPath:store.destinationPath,isDirectory:true)
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        store.setDestination(url)
        return true
    }
    static func reveal(_ item: DownloadItem) {
        if let url = item.localFileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    static func open(_ item: DownloadItem) {
        if let url = item.localFileURL { NSWorkspace.shared.open(url) }
    }
    static func openLog() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Shouxia/backend.log")
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
    }
    static func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Video Extractor · 本地影音下载"
        alert.informativeText = "粘贴或拖入分享文字或视频链接，选择视频/音频与画质后提取。抖音精选页会自动转换为标准视频地址。解析时可停止并核对；超时后不要重复提交未决任务。\n\n任务列表可独立筛选媒体类型和失败状态。失败时可修正链接、画质和格式后重试；默认保留原始最佳格式，MP4 源格式不等于转码。\n\n下载设置中可手动导入 Netscape Cookie 文件、设置代理与请求头、检查后台依赖。Cookie 需由你提供，有效性由网站决定。快捷输入会显示参数和提交结果。\n\n已提交任务保留原保存位置；完成后可打开文件、在 Finder 中显示或截取片段。退出应用不会中断后台下载。"
        alert.addButton(withTitle: "知道了")
        alert.runModal()
    }
}
